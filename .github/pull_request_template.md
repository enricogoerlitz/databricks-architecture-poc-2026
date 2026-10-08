## Was und warum

<!-- 1–3 Sätze -->

## Checkliste

- [ ] `make check` bzw. `uv run pre-commit run --all-files` grün
- [ ] Keine Secrets oder IDs im Diff (gitleaks)
- [ ] READMEs, `AGENTS.md`-Index und Doku aktualisiert, falls Struktur geändert
- [ ] Entscheidung mit Tragweite als ADR unter `docs/adr/`
- [ ] Infra-Änderung: Plan-Zusammenfassung geprüft (Kosten?)
- [ ] Metadaten-Änderung: `python -m tools.metadata render --env dev` geprüft
