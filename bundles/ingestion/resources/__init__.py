"""Python for Bundles: lädt die aus metadata/ generierten Ressourcen."""

from databricks.bundles.core import Bundle, Resources

from .generator import build


def load_resources(bundle: Bundle) -> Resources:
    resources = Resources()
    generated = build(env=bundle.variables["env"])
    for key, schema in generated["schemas"].items():
        resources.add_schema(key, schema)
    for key, pipeline in generated["pipelines"].items():
        resources.add_pipeline(key, pipeline)
    for key, job in generated["jobs"].items():
        resources.add_job(key, job)
    return resources
