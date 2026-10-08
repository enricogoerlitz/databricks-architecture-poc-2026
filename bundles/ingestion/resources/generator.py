"""Erzeugt Bundle-Ressourcen (Jobs, Pipelines, Schemas) aus metadata/.

Bewusst ohne Abhängigkeit zu ``databricks-bundles``: liefert reine Dicts, damit Unit-Tests und
``python -m tools.metadata render`` ohne Databricks laufen. ``__init__.py`` reicht die Dicts an
Python for Bundles weiter.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
METADATA_DIR = REPO_ROOT / "metadata"

# Interpolationen bleiben stehen und werden von der CLI aufgelöst. Schema-Namen immer über
# Ressourcen-Referenzen: im Modus "development" setzt die CLI ein Präfix (dev_<user>_…).
WHEEL = "/Volumes/{platform}/libs/wheels/dbxpoc_common-${{var.lib_version}}-py3-none-any.whl"


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_environment(env: str, metadata_dir: Path = METADATA_DIR) -> dict[str, Any]:
    return load_yaml(metadata_dir / "environments" / f"{env}.yml")


def load_sources(env: str, metadata_dir: Path = METADATA_DIR) -> list[dict[str, Any]]:
    """Lädt alle Quellen und ersetzt ``${env}`` in String-Werten."""
    sources = []
    for path in sorted((metadata_dir / "sources").glob("*.yml")):
        raw = path.read_text(encoding="utf-8").replace("${env}", env)
        sources.append(yaml.safe_load(raw))
    return sources


def _tags(env: str, src: dict[str, Any]) -> dict[str, str]:
    return {"project": "dbxpoc", "env": env, "source": src["name"], **src.get("tags", {})}


def schema_ref(layer: str, source: str) -> str:
    return f"${{resources.schemas.{layer}_{source}.name}}"


def _pipeline_config(env_cfg: dict[str, Any], meta: dict[str, Any]) -> dict[str, Any]:
    src = meta["source"]
    cats = env_cfg["catalogs"]
    cfg = {
        "source": {
            "name": src["name"],
            "type": src["type"],
            "bronze_catalog": cats["bronze"],
            "bronze_schema": schema_ref("bronze", src["name"]),
            "silver_catalog": cats["silver"],
            "silver_schema": schema_ref("silver", src["name"]),
        },
        "tables": meta["tables"],
    }
    if src["type"] == "files":
        cfg["source"].update(
            location=f"/Volumes/{cats['bronze']}/landing/files/{src['location']}",
            format=src["format"],
            options=src.get("options", {}),
        )
    return cfg


def build(env: str, metadata_dir: Path = METADATA_DIR) -> dict[str, dict[str, Any]]:
    """Baut alle Ressourcen für eine Stage. Rückgabe: ``{"schemas": …, "pipelines": …, "jobs": …}``."""
    env_cfg = load_environment(env, metadata_dir)
    cats = env_cfg["catalogs"]
    wheel = WHEEL.format(platform=cats["platform"])
    perf = env_cfg["jobs"]["performance_target"]

    schemas: dict[str, Any] = {}
    pipelines: dict[str, Any] = {}
    jobs: dict[str, Any] = {}

    for meta in load_sources(env, metadata_dir):
        src = meta["source"]
        name = src["name"]
        tags = _tags(env, src)

        for layer, schema in (("bronze", src["bronze_schema"]), ("silver", src["silver_schema"])):
            schemas[f"{layer}_{name}"] = {
                "catalog_name": cats[layer],
                "name": schema,
                "comment": f"{layer.capitalize()} der Quelle {name} (generiert aus metadata/)",
            }

        config = json.dumps(_pipeline_config(env_cfg, meta), separators=(",", ":"))

        pipelines[f"silver_{name}"] = {
            "name": f"silver_{name}",
            "catalog": cats["silver"],
            "schema": schema_ref("silver", name),
            "serverless": True,
            "channel": "CURRENT",
            "libraries": [{"file": {"path": "src/silver_pipeline.py"}}],
            "configuration": {"dbxpoc.config": config},
            "environment": {"dependencies": [wheel]},
            "tags": tags,
        }

        tasks: list[dict[str, Any]] = []
        if src["type"] == "sqlserver" and src["ingestion_mode"] == "full_load":
            inputs = [
                {
                    "source_object": t["source_object"].lower(),
                    "target_table": t["name"],
                }
                for t in meta["tables"]
                if t.get("load", {}).get("type", "full") == "full"
            ]
            tasks.append(
                {
                    "task_key": "bronze_full_load",
                    "for_each_task": {
                        "inputs": json.dumps(inputs),
                        "concurrency": 4,
                        "task": {
                            "task_key": "bronze_full_load_table",
                            # Quelle (Serverless/Free-Offer-SQL) kann pausiert sein -> Retries
                            "max_retries": 3,
                            "min_retry_interval_millis": 60000,
                            "notebook_task": {
                                "notebook_path": "src/full_load.py",
                                "base_parameters": {
                                    "source_catalog": src["foreign_catalog"],
                                    "source_object": "{{input.source_object}}",
                                    "target_catalog": cats["bronze"],
                                    "target_schema": schema_ref("bronze", name),
                                    "target_table": "{{input.target_table}}",
                                },
                            },
                        },
                    },
                }
            )

        tasks.append(
            {
                "task_key": "silver",
                **({"depends_on": [{"task_key": tasks[-1]["task_key"]}]} if tasks else {}),
                "pipeline_task": {"pipeline_id": f"${{resources.pipelines.silver_{name}.id}}"},
            }
        )

        job: dict[str, Any] = {
            "name": f"ingest_{name}",
            "description": f"Source → Bronze → Silver für {name} (generiert aus metadata/sources/{name}.yml)",
            "tags": tags,
            "performance_target": perf,
            "max_concurrent_runs": 1,
            "tasks": tasks,
        }
        if "schedule" in src:
            sched = env_cfg["schedules"][src["schedule"]]
            job["schedule"] = {
                "quartz_cron_expression": sched["cron"],
                "timezone_id": sched["timezone"],
                "pause_status": sched["pause_status"],
            }
        if src.get("trigger") == "file_arrival":
            job["trigger"] = {
                "file_arrival": {"url": f"/Volumes/{cats['bronze']}/landing/files/{src['location']}"},
            }
        jobs[f"ingest_{name}"] = job

    # Metadaten zur Laufzeit als Delta-Tabellen spiegeln (Monitoring, Lineage-Joins)
    jobs["publish_metadata"] = {
        "name": "publish_metadata",
        "description": "Spiegelt metadata/ nach <env>_platform.meta (wird nach jedem Deploy ausgeführt)",
        "tags": {"project": "dbxpoc", "env": env},
        "performance_target": perf,
        "tasks": [
            {
                "task_key": "publish",
                "notebook_task": {
                    "notebook_path": "src/publish_metadata.py",
                    "base_parameters": {
                        "target_schema": f"{cats['platform']}.meta",
                        "metadata_json": json.dumps(load_sources(env, metadata_dir)),
                        "git_sha": "${var.git_sha}",
                    },
                },
            }
        ],
    }

    return {"schemas": schemas, "pipelines": pipelines, "jobs": jobs}
