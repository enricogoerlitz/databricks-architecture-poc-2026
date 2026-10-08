---
name: teardown-env
description: Eine Stage (dev/tst/prd) abbauen, nur Workloads (Bundles) oder komplett inkl. Infrastruktur. Verwenden bei "abreißen", "teardown", "Kosten stoppen", "alles löschen".
---

# Stage abbauen

**Immer vorher fragen.** Was wird gelöscht? Ist es reversibel? Daten in den Catalogs gehen
verloren.

- **Nur Workloads** (Infra bleibt, z. B. vor einem Lernpfad):
  `gh workflow run teardown.yml -f env=<env> -f scope=workloads -f confirm=<env>`
- **Komplett:** `-f scope=all`. Reihenfolge: Bundles → Stack `databricks` → `sources` → `azure`.
  Lokal geht es auch mit
  `make tf-destroy ENV=<env> STACK=databricks|sources|azure`, in dieser Reihenfolge.

Danach prüfen:
```bash
az resource list --tag project=dbxpoc --query "[].{n:name,t:type,rg:resourceGroup}" -o table
```
Leer bis auf Bootstrap-Ressourcen (RGs, tfstate) heißt: erledigt. Metastore und Account bleiben
bestehen und kosten nichts.

Ganz am Ende (nur auf Wunsch): `infra/terraform/account` und `bootstrap` lokal destroyen. Danach
gibt es keine CI-Identitäten mehr.
