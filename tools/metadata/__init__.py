"""Metadaten-Werkzeuge: Validierung (JSON Schema + Querverweise) und Vorschau der Bundle-Ressourcen."""

from __future__ import annotations

import json
from pathlib import Path

import jsonschema
import yaml

ROOT = Path(__file__).resolve().parents[2]
METADATA = ROOT / "metadata"


def _schema(name: str) -> dict:
    return json.loads((METADATA / "schema" / name).read_text(encoding="utf-8"))


def validate(metadata_dir: Path = METADATA) -> list[str]:
    """Gibt eine Liste von Fehlern zurück (leer = gültig)."""
    errors: list[str] = []
    src_schema = _schema("source.schema.json")
    env_schema = _schema("environment.schema.json")

    envs = {}
    for path in sorted((metadata_dir / "environments").glob("*.yml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        for e in jsonschema.Draft202012Validator(env_schema).iter_errors(data):
            errors.append(f"{path.name}: {e.json_path}: {e.message}")
        envs[path.stem] = data
        if data.get("env") != path.stem:
            errors.append(f"{path.name}: env '{data.get('env')}' passt nicht zum Dateinamen")

    names = set()
    for path in sorted((metadata_dir / "sources").glob("*.yml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        for e in jsonschema.Draft202012Validator(src_schema).iter_errors(data):
            errors.append(f"{path.name}: {e.json_path}: {e.message}")
        src = data.get("source", {})
        if src.get("name") != path.stem:
            errors.append(f"{path.name}: source.name '{src.get('name')}' passt nicht zum Dateinamen")
        if src.get("name") in names:
            errors.append(f"{path.name}: doppelte Quelle {src.get('name')}")
        names.add(src.get("name"))
        sched = src.get("schedule")
        for env, cfg in envs.items():
            if sched and sched not in cfg.get("schedules", {}):
                errors.append(f"{path.name}: schedule '{sched}' fehlt in environments/{env}.yml")
        for t in data.get("tables", []):
            cols = {x["column"] for x in t.get("silver", {}).get("transforms", [])}
            keys = set(t.get("keys", []))
            if src.get("type") == "sqlserver" and "source_object" not in t:
                errors.append(f"{path.name}: Tabelle {t.get('name')} braucht source_object")
            if keys & cols and src.get("type") == "sqlserver":
                errors.append(f"{path.name}: {t.get('name')}: Keys dürfen nicht transformiert werden ({keys & cols})")
    return errors
