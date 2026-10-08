"""Konfigurationsobjekt für die generische Silver-Verarbeitung (Beispiel für Klassen im Wheel)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class TableConfig:
    """Beschreibt eine Tabelle, wie sie aus den Metadaten in die Silver-Pipeline kommt."""

    name: str
    keys: list[str]
    scd_type: int = 1
    track_history_columns: list[str] | None = None
    transforms: list[dict[str, str]] = field(default_factory=list)
    expectations: dict[str, dict[str, str]] = field(default_factory=dict)
    sequence_by: str | None = None

    def __post_init__(self) -> None:
        if self.scd_type not in (1, 2):
            raise ValueError(f"{self.name}: scd_type muss 1 oder 2 sein, nicht {self.scd_type}")
        if not self.keys:
            raise ValueError(f"{self.name}: mindestens ein Key ist nötig")

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> TableConfig:
        silver = data.get("silver", {})
        return cls(
            name=data["name"],
            keys=list(data["keys"]),
            scd_type=int(silver.get("scd_type", 1)),
            track_history_columns=silver.get("track_history_columns"),
            transforms=list(silver.get("transforms", [])),
            expectations=dict(silver.get("expectations", {})),
            sequence_by=silver.get("sequence_by"),
        )

    def expectations_by_action(self, action: str) -> dict[str, str]:
        """Expectations einer Aktion (``drop``, ``warn``, ``fail``) als ``{name: expr}``."""
        return {n: e["expr"] for n, e in self.expectations.items() if e.get("action") == action}
