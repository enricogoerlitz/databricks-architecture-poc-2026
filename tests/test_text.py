from datetime import date

import pytest
from dbxpoc_common.text import clean_string, lower_clean, normalize_email, parse_date_multi


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("  Anna   Müller ", "Anna Müller"), ("", None), ("   ", None), (None, None), ("a\tb", "a b")],
)
def test_clean_string(raw, expected):
    assert clean_string(raw) == expected


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (" ANNA@Example.COM ", "anna@example.com"),
        ("anna example@x.de", "annaexample@x.de"),
        ("annaexample.com", None),
        ("@example.com", None),
        (None, None),
    ],
)
def test_normalize_email(raw, expected):
    assert normalize_email(raw) == expected


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("2026-02-01", date(2026, 2, 1)),
        ("01.02.2026", date(2026, 2, 1)),
        ("02/01/2026", date(2026, 2, 1)),
        ("20260201", date(2026, 2, 1)),
        ("kein datum", None),
        (None, None),
    ],
)
def test_parse_date_multi(raw, expected):
    assert parse_date_multi(raw) == expected


@pytest.mark.parametrize(("raw", "expected"), [(" SHIPPED ", "shipped"), ("  Open", "open"), ("", None), (None, None)])
def test_lower_clean(raw, expected):
    assert lower_clean(raw) == expected
