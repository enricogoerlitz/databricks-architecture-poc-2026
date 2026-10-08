"""Generische Silver-Pipeline (Lakeflow pipelines), gesteuert über Metadaten.

Die Konfiguration kommt als JSON in ``spark.conf["dbxpoc.config"]`` (vom Bundle-Generator aus
metadata/ erzeugt). Je Tabelle entstehen:

- sqlserver (Full Load): View auf den Bronze-Snapshot → ``AUTO CDC FROM SNAPSHOT`` (SCD1/SCD2)
- files: Bronze-Streaming-Table per Auto Loader → View → ``AUTO CDC`` (SCD1/SCD2)

Transformationen und Klassen kommen aus dem zentralen Wheel ``dbxpoc_common``.
"""

import json

from dbxpoc_common.scd import TableConfig
from dbxpoc_common.transforms import REGISTRY
from pyspark import pipelines as dp
from pyspark.sql import DataFrame
from pyspark.sql import functions as F  # noqa: N812

CONFIG = json.loads(spark.conf.get("dbxpoc.config"))  # noqa: F821 - spark kommt von der Runtime
SRC = CONFIG["source"]
BRONZE = f"{SRC['bronze_catalog']}.{SRC['bronze_schema']}"
TECH_COLUMNS = ["_ingested_at", "_file_path", "_file_modification_time"]


def apply_transforms(df: DataFrame, cfg: TableConfig) -> DataFrame:
    for t in cfg.transforms:
        df = df.withColumn(t["column"], REGISTRY[t["fn"]](t["column"]))
    return df


def with_expectations(fn, cfg: TableConfig):
    """Expectations aus den Metadaten als Decorators anwenden."""
    for action, deco in (("drop", dp.expect_all_or_drop), ("warn", dp.expect_all), ("fail", dp.expect_all_or_fail)):
        rules = cfg.expectations_by_action(action)
        if rules:
            fn = deco(rules)(fn)
    return fn


def track_history(cfg: TableConfig) -> dict:
    return (
        {"track_history_column_list": cfg.track_history_columns}
        if cfg.scd_type == 2 and cfg.track_history_columns
        else {}
    )


def define_sqlserver_table(cfg: TableConfig) -> None:
    view_name = f"v_{cfg.name}_snapshot"

    drop_rules = cfg.expectations_by_action("drop")

    def snapshot():
        # Technische Spalten raus, sonst wäre jede Zeile bei jedem Full Load "geändert".
        df = spark.read.table(f"{BRONZE}.{cfg.name}").drop(*TECH_COLUMNS)  # noqa: F821
        df = apply_transforms(df, cfg)
        # AUTO CDC FROM SNAPSHOT wertet Expectations der Quell-View nicht aus -> drop-Regeln als Filter
        for rule in drop_rules.values():
            df = df.filter(F.expr(f"coalesce({rule}, false)"))
        return df

    snapshot.__name__ = view_name
    dp.view(name=view_name, comment=f"Bereinigter Snapshot von {BRONZE}.{cfg.name}")(with_expectations(snapshot, cfg))

    dp.create_streaming_table(name=cfg.name, comment=f"Silver {cfg.name} (SCD{cfg.scd_type}, aus Snapshot)")
    dp.create_auto_cdc_from_snapshot_flow(
        target=cfg.name,
        source=view_name,
        keys=cfg.keys,
        stored_as_scd_type=cfg.scd_type,
        **track_history(cfg),
    )


def define_files_table(cfg: TableConfig, table_meta: dict) -> None:
    bronze_table = f"{BRONZE}.{cfg.name}"
    reader_opts = {f"cloudFiles.{k}" if k in ("schemaHints",) else k: v for k, v in SRC.get("options", {}).items()}

    @dp.table(name=bronze_table, comment=f"Bronze {cfg.name} (Auto Loader, append-only)")
    def bronze():
        return (
            spark.readStream.format("cloudFiles")  # noqa: F821
            .option("cloudFiles.format", SRC["format"])
            .option("pathGlobFilter", table_meta.get("pattern", "*"))
            .options(**reader_opts)
            .load(SRC["location"])
            .select(
                "*",
                F.col("_metadata.file_path").alias("_file_path"),
                F.col("_metadata.file_modification_time").alias("_file_modification_time"),
                F.current_timestamp().alias("_ingested_at"),
            )
        )

    view_name = f"v_{cfg.name}_changes"

    def changes():
        df = spark.readStream.table(bronze_table)  # noqa: F821
        # Exakte Dubletten innerhalb einer Datei (messy Export) entfernen; AUTO CDC verlangt
        # eindeutige (Key, Sequence)-Paare.
        df = df.dropDuplicates([*cfg.keys, cfg.sequence_by or "_file_modification_time"])
        return apply_transforms(df, cfg)

    changes.__name__ = view_name
    dp.view(name=view_name)(with_expectations(changes, cfg))

    dp.create_streaming_table(name=cfg.name, comment=f"Silver {cfg.name} (SCD{cfg.scd_type}, aus Dateien)")
    dp.create_auto_cdc_flow(
        target=cfg.name,
        source=view_name,
        keys=cfg.keys,
        sequence_by=F.col(cfg.sequence_by or "_file_modification_time"),
        except_column_list=["_file_path", "_ingested_at"],
        stored_as_scd_type=cfg.scd_type,
        **track_history(cfg),
    )


for table_meta in CONFIG["tables"]:
    table_cfg = TableConfig.from_dict(table_meta)
    if SRC["type"] == "sqlserver":
        define_sqlserver_table(table_cfg)
    else:
        define_files_table(table_cfg, table_meta)
