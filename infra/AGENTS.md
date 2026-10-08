# AGENTS.md (infra/)

Ergänzt das Root-[AGENTS.md](../AGENTS.md). Infrastruktur ist teuer und schwer rückgängig zu machen:

- **Nie** `terraform apply`, `destroy`, `import`, `state rm/mv` oder `force-unlock` ohne
  ausdrückliche Freigabe des Menschen. `plan` ist erlaubt.
- **Nie** State-Dateien lesen, ausgeben oder committen (enthalten Ressourcen-Details).
- Secrets nur ephemeral/write-only (`*_wo`, `ephemeral "random_password"`). Kein `value =` mit
  Passwörtern, keine `output`s mit Secrets.
- Neue Ressourcen bekommen die Standard-Tags (`local.tags`) und folgen der Namenskonvention.
- Nach Änderungen: `terraform fmt -recursive`, `make tf-validate`, `tflint` (siehe Makefile).
- Account-Ebene (`account/`) und `bootstrap/` laufen nur lokal durch einen Menschen.
