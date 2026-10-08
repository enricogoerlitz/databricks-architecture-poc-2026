import json

import pytest

from bundles.ingestion.resources.generator import build
from tools.metadata import validate


def test_metadata_is_valid():
    assert validate() == []


@pytest.mark.parametrize("env", ["dev", "tst", "prd"])
def test_generator_builds_resources(env):
    res = build(env)
    assert set(res) == {"schemas", "pipelines", "jobs"}
    assert {"ingest_salesdb", "ingest_crm_files", "publish_metadata"} <= set(res["jobs"])
    # Catalogs je Stage, Schemas als Ressourcen-Referenz (Präfix im Modus development)
    assert res["schemas"]["bronze_salesdb"]["catalog_name"] == f"{env}_bronze"
    pipe = res["pipelines"]["silver_salesdb"]
    assert pipe["catalog"] == f"{env}_silver"
    assert pipe["schema"] == "${resources.schemas.silver_salesdb.name}"
    assert pipe["serverless"] is True
    assert pipe["environment"]["dependencies"][0].startswith(f"/Volumes/{env}_platform/libs/wheels/")


def test_full_load_job_uses_for_each_over_tables():
    job = build("dev")["jobs"]["ingest_salesdb"]
    first = job["tasks"][0]
    assert first["task_key"] == "bronze_full_load"
    inputs = json.loads(first["for_each_task"]["inputs"])
    assert {i["target_table"] for i in inputs} == {"customers", "orders"}
    assert job["tasks"][1]["depends_on"] == [{"task_key": "bronze_full_load"}]
    assert job["schedule"]["pause_status"] == "PAUSED"


def test_files_job_has_file_arrival_trigger():
    job = build("prd")["jobs"]["ingest_crm_files"]
    assert job["trigger"]["file_arrival"]["url"] == "/Volumes/prd_bronze/landing/files/products/"
    assert [t["task_key"] for t in job["tasks"]] == ["silver"]


def test_no_secrets_in_generated_resources():
    blob = json.dumps(build("prd")).lower()
    assert "password" not in blob
