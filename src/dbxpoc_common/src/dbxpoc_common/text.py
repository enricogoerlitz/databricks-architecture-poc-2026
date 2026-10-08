"""Reine Python-Funktionen ohne Spark-Abhängigkeit.

Diese Funktionen laufen überall: in Unit-Tests, in UC Python UDFs (Sandbox ohne Spark) und als
Referenz-Implementierung für die Spark-Varianten in :mod:`dbxpoc_common.transforms`.
"""

from __future__ import annotations

import re
from datetime import date, datetime

_WS = re.compile(r"\s+")
_DATE_FORMATS = ("%Y-%m-%d", "%d.%m.%Y", "%m/%d/%Y", "%Y%m%d")


def clean_string(value: str | None) -> str | None:
    """Trimmt und reduziert Mehrfach-Leerzeichen. Leere Strings werden zu ``None``."""
    if value is None:
        return None
    cleaned = _WS.sub(" ", value).strip()
    return cleaned or None


def normalize_email(value: str | None) -> str | None:
    """Kleinbuchstaben, ohne Leerzeichen. Ungültige Adressen (ohne genau ein @) -> ``None``."""
    cleaned = clean_string(value)
    if cleaned is None:
        return None
    cleaned = cleaned.replace(" ", "").lower()
    return cleaned if cleaned.count("@") == 1 and not cleaned.startswith("@") else None


def parse_date_multi(value: str | None) -> date | None:
    """Parst Datumswerte in mehreren gängigen Formaten (ISO, DE, US, kompakt)."""
    cleaned = clean_string(value)
    if cleaned is None:
        return None
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(cleaned, fmt).date()
        except ValueError:
            continue
    return None


def lower_clean(value: str | None) -> str | None:
    """Wie :func:`clean_string`, zusätzlich in Kleinbuchstaben (z. B. für Status-/Kategorie-Codes)."""
    cleaned = clean_string(value)
    return cleaned.lower() if cleaned is not None else None
