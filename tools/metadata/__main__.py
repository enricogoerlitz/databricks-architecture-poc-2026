"""CLI: ``python -m tools.metadata validate`` | ``python -m tools.metadata render --env dev``."""

from __future__ import annotations

import argparse
import json
import sys

from tools.metadata import validate


def main() -> int:
    parser = argparse.ArgumentParser(prog="python -m tools.metadata")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate", help="JSON Schema + Querverweise prüfen")
    render = sub.add_parser("render", help="generierte Bundle-Ressourcen als JSON ausgeben")
    render.add_argument("--env", default="dev", choices=["dev", "tst", "prd"])
    args = parser.parse_args()

    if args.cmd == "validate":
        errors = validate()
        for e in errors:
            print(f"FEHLER {e}", file=sys.stderr)
        print("metadata: ok" if not errors else f"metadata: {len(errors)} Fehler")
        return 1 if errors else 0

    errors = validate()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    from bundles.ingestion.resources.generator import build

    print(json.dumps(build(args.env), indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
