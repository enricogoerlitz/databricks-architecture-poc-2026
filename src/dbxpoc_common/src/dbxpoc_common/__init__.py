"""dbxpoc_common – zentrale, wiederverwendbare Logik für Silver.

- :mod:`dbxpoc_common.text`: reine Python-Funktionen (auch als UC Python UDF registriert)
- :mod:`dbxpoc_common.transforms`: PySpark-Column-Ausdrücke (performant, ohne UDF)
- :mod:`dbxpoc_common.scd`: Konfigurationsklasse für SCD-Verarbeitung
"""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("dbxpoc-common")
except PackageNotFoundError:  # pragma: no cover - z. B. bei Import aus dem Quellbaum
    __version__ = "0.0.0"
