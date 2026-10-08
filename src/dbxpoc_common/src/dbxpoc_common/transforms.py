"""PySpark-Varianten der Funktionen aus :mod:`dbxpoc_common.text`.

Bewusst als Column-Ausdrücke (keine Python-UDF): laufen vektorisiert in Photon.
PySpark wird erst beim Aufruf importiert, damit das Paket ohne Spark installierbar bleibt.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:  # pragma: no cover
    from pyspark.sql import Column

_DATE_FORMATS = ("yyyy-MM-dd", "dd.MM.yyyy", "MM/dd/yyyy", "yyyyMMdd")


def _f():
    from pyspark.sql import functions as F  # noqa: N812

    return F


def clean_string(col: str | Column) -> Column:
    F = _f()  # noqa: N806
    c = F.col(col) if isinstance(col, str) else col
    trimmed = F.trim(F.regexp_replace(c, r"\s+", " "))
    return F.when(trimmed == "", F.lit(None)).otherwise(trimmed)


def normalize_email(col: str | Column) -> Column:
    F = _f()  # noqa: N806
    c = F.lower(F.regexp_replace(clean_string(col), " ", ""))
    return F.when(c.rlike(r"^[^@]+@[^@]+$"), c).otherwise(F.lit(None))


def lower_clean(col: str | Column) -> Column:
    F = _f()  # noqa: N806
    return F.lower(clean_string(col))


def parse_date_multi(col: str | Column) -> Column:
    F = _f()  # noqa: N806
    c = clean_string(col)
    return F.coalesce(*[F.to_date(F.try_to_timestamp(c, F.lit(fmt))) for fmt in _DATE_FORMATS])


#: Registry für metadatengesteuerte Transformationen (Name in YAML -> Funktion)
REGISTRY = {
    "clean_string": clean_string,
    "normalize_email": normalize_email,
    "parse_date_multi": parse_date_multi,
    "lower_clean": lower_clean,
}
