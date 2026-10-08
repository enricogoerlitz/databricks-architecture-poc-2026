# Lokale Befehle für Entwickler und Agents. Die CI nutzt dieselben Targets.
# Beispiele:
#   make check                         # alle lokalen Checks (lint, test, validate)
#   make tf-plan ENV=dev STACK=azure   # Terraform-Plan einer Stage/eines Stacks
#   make bundle-deploy ENV=dev BUNDLE=platform
# Lokale, nicht versionierte Werte (z. B. Databricks-Account-ID) stehen in .env.local.

SHELL := /bin/bash
ENV    ?= dev
STACK  ?= azure
BUNDLE ?= platform

-include .env.local
export

PREFIX ?= dbxpoc
SUFFIX ?= eg26
TF_ROOT := infra/terraform
TF_DIR  := $(TF_ROOT)/stacks/$(STACK)
TFLINT  ?= $(shell command -v tflint 2>/dev/null || echo mise exec -- tflint)

# Werte für Terraform (keine tfvars-Dateien mit IDs im Repo)
export TF_VAR_env                      := $(ENV)
export TF_VAR_prefix                   := $(PREFIX)
export TF_VAR_suffix                   := $(SUFFIX)
export TF_VAR_tfstate_resource_group   := rg-$(PREFIX)-shared-weu
export TF_VAR_tfstate_storage_account  := st$(PREFIX)tfstate$(SUFFIX)
export TF_VAR_subscription_id          ?= $(shell az account show --query id -o tsv 2>/dev/null)
export ARM_SUBSCRIPTION_ID             ?= $(TF_VAR_subscription_id)

.PHONY: help check lint test tf-fmt tf-validate tf-init tf-plan tf-apply tf-destroy \
        bundle-validate bundle-deploy bundle-destroy deploy-sp-id

help: ## Diese Hilfe
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-18s %s\n",$$1,$$2}'

# ---------------------------------------------------------------- Checks
check: lint test tf-validate bundle-validate-offline ## Alle lokalen Checks

lint: ## ruff + terraform fmt + tflint + metadata schema
	uv run ruff check .
	uv run ruff format --check .
	terraform fmt -check -recursive $(TF_ROOT)
	cd $(TF_ROOT) && $(TFLINT) --recursive --config "$$(pwd)/.tflint.hcl"
	uv run python -m tools.metadata validate

test: ## pytest
	uv run pytest -q

tf-fmt: ## terraform fmt (schreibend)
	terraform fmt -recursive $(TF_ROOT)

tf-validate: ## terraform validate für alle Stacks (ohne Backend)
	@for d in $(TF_ROOT)/bootstrap $(TF_ROOT)/account $(TF_ROOT)/stacks/*; do \
	  echo "== $$d"; terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate -no-color || exit 1; \
	done

bundle-validate-offline: ## Bundles syntaktisch prüfen (Generator + Schema, ohne Workspace)
	uv run python -m tools.metadata render --env $(ENV) >/dev/null

# ---------------------------------------------------------------- Terraform
deploy-sp-id:
	@az ad sp list --display-name sp-$(PREFIX)-$(ENV)-deploy --query "[0].appId" -o tsv

tf-init: ## terraform init (ENV, STACK)
	terraform -chdir=$(TF_DIR) init -reconfigure -input=false \
	  -backend-config=../../envs/backend.hcl -backend-config=key=$(ENV)/$(STACK).tfstate

# Objekt-/Client-IDs: in der CI kommen sie als Secrets (die CI-SPs haben keine Graph-Rechte),
# lokal werden sie per az (Graph) nachgeschlagen, falls nicht gesetzt.
define tf_ids
	export TF_VAR_deploy_sp_client_id=$${TF_VAR_deploy_sp_client_id:-$$($(MAKE) -s deploy-sp-id)}; \
	export TF_VAR_azure_databricks_sp_object_id=$${TF_VAR_azure_databricks_sp_object_id:-$$(az ad sp show --id 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query id -o tsv)}; \
	export TF_VAR_kv_admin_object_ids=$${TF_VAR_kv_admin_object_ids:-$$(printf '["%s","%s"]' \
	  "$$(az ad sp list --display-name sp-$(PREFIX)-$(ENV)-infra --query '[0].id' -o tsv)" \
	  "$$(az ad group show -g sg-$(PREFIX)-$(ENV)-ws-admins --query id -o tsv)")};
endef

tf-plan: tf-init ## terraform plan (ENV, STACK)
	@$(tf_ids) terraform -chdir=$(TF_DIR) plan -input=false -out=tfplan

tf-apply: ## terraform apply des zuletzt erzeugten Plans (ENV, STACK)
	terraform -chdir=$(TF_DIR) apply -input=false tfplan

tf-destroy: tf-init ## terraform destroy (ENV, STACK) – nur nach Freigabe!
	@$(tf_ids) terraform -chdir=$(TF_DIR) destroy -input=false

# ---------------------------------------------------------------- Bundles
bundle-validate: ## databricks bundle validate (ENV, BUNDLE)
	cd bundles/$(BUNDLE) && databricks bundle validate -t $(ENV)

bundle-deploy: ## databricks bundle deploy (ENV, BUNDLE)
	cd bundles/$(BUNDLE) && databricks bundle deploy -t $(ENV)

bundle-destroy: ## databricks bundle destroy (ENV, BUNDLE) – nur nach Freigabe!
	cd bundles/$(BUNDLE) && databricks bundle destroy -t $(ENV) --auto-approve

# ---------------------------------------------------------------- Lokal wie die CI
ws-host: ## URL des ersten Workspaces der Stage (aus dem Terraform-Output)
	@terraform -chdir=$(TF_ROOT)/stacks/azure output -json workspaces | python3 -c "import json,sys; print(json.load(sys.stdin)['01']['url'])"

wheel: ## Wheel bauen (dist/)
	uv build --wheel src/dbxpoc_common -o dist
