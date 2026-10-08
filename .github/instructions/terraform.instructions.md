---
applyTo: "infra/**/*.tf"
---
- Regeln aus `infra/AGENTS.md` gelten: kein apply/destroy ohne Freigabe, keine State-Dateien lesen.
- Secrets nur über `ephemeral` + `*_wo`-Attribute, nie als `value` oder Output.
- Namen `<typ>-${var.prefix}-${var.env}-<region>`; Tags über `local.tags`.
- Neue Stage-Werte als Variablen-Map mit Schlüssel `dev|tst|prd`, nicht als tfvars mit IDs.
- Danach: `terraform fmt -recursive infra/terraform` und `make tf-validate`.
