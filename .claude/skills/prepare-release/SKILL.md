---
name: prepare-release
description: Release nach tst/prd vorbereiten und auslösen (Checks, Versionsprüfung, Tag). Verwenden bei "Release", "nach prd deployen", "Tag setzen", "Promotion".
---

# Release vorbereiten

Promotion-Modell: `main` ist bereits in dev und, nach Approval, in tst deployt. prd deployt nur
ein Release-Tag `vX.Y.Z`, ebenfalls nach Approval im GitHub Environment `prd`.

1. Stand prüfen: `git fetch --tags && git status`. `main` ist aktuell, und der letzte Lauf von
   `infra-deploy` und `bundles-deploy` auf `main` ist grün (`gh run list --branch main -L 5`).
2. Checks lokal: `make check`.
3. Wheel-Version: Hat sich `src/dbxpoc_common` seit dem letzten Tag geändert
   (`git diff <letzter-tag> -- src/dbxpoc_common`), muss die Version in `pyproject.toml` erhöht
   sein. Serverless cacht Umgebungen je Version.
4. Nächste Version bestimmen (SemVer) und Release-Notes aus
   `git log <letzter-tag>..HEAD --oneline` zusammenfassen.
5. **Rückfrage beim Menschen** mit Version, Änderungen und Kostenhinweis. Erst dann:
   `git tag -a vX.Y.Z -m "<notes>" && git push origin vX.Y.Z`.
6. Approval im GitHub-UI abwarten (Environment `prd`). Danach den Lauf überwachen
   (`gh run watch`).

**Rollback prd:** Workflow `bundles-deploy` per `workflow_dispatch` mit `env=prd` auf dem
vorherigen Tag starten (`gh workflow run bundles-deploy.yml --ref vX.Y.(Z-1) -f env=prd`).
