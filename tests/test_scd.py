import pytest
from dbxpoc_common.scd import TableConfig


def test_from_dict_and_expectations():
    cfg = TableConfig.from_dict(
        {
            "name": "customers",
            "keys": ["customer_id"],
            "silver": {
                "scd_type": 2,
                "expectations": {
                    "a": {"expr": "x IS NOT NULL", "action": "drop"},
                    "b": {"expr": "y > 0", "action": "warn"},
                },
            },
        }
    )
    assert cfg.scd_type == 2
    assert cfg.expectations_by_action("drop") == {"a": "x IS NOT NULL"}
    assert cfg.expectations_by_action("fail") == {}


def test_invalid_scd_type():
    with pytest.raises(ValueError):
        TableConfig(name="t", keys=["id"], scd_type=3)


def test_keys_required():
    with pytest.raises(ValueError):
        TableConfig(name="t", keys=[])
