# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

from pathlib import Path

import pytest

from sample_workload.contracts import QueryPlan
from sample_workload.database import QueryFailed, QueryRejected, Store, initialize


@pytest.fixture
def store(tmp_path: Path) -> Store:
    path = tmp_path / "retail.db"
    initialize(path)
    return Store(path)


@pytest.mark.parametrize(
    "sql",
    [
        "DELETE FROM products",
        "UPDATE products SET unit_price = 0",
        "INSERT INTO products VALUES ('x', 'x', 'x', 0, 0)",
        "DROP TABLE products",
        "CREATE TABLE copied AS SELECT * FROM products",
        "ATTACH DATABASE ':memory:' AS external",
        "PRAGMA query_only = OFF",
        "SELECT * FROM products; DELETE FROM products",
        "SELECT * FROM sqlite_master",
        "SELECT * FROM orders",
        "SELECT * FROM main.products",
        "SELECT load_extension('malicious')",
        "WITH RECURSIVE x(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM x) SELECT * FROM x",
        "SELECT * INTO copied FROM products",
        "SELECT FROM",
    ],
)
def test_unsafe_sql_is_rejected_without_writing(store: Store, sql: str) -> None:
    before = store.path.read_bytes()
    with pytest.raises(QueryRejected):
        store.query(QueryPlan(sql=sql), frozenset({"products"}))
    assert store.path.read_bytes() == before


def test_parameter_binding_treats_injection_as_data(store: Store) -> None:
    result = store.query(
        QueryPlan(
            sql="SELECT product_id FROM products WHERE product_name = :name",
            parameters={"name": "Tent' OR 1=1; DROP TABLE products; --"},
        ),
        frozenset({"products"}),
    )
    assert result.rows == []
    assert store.query(
        QueryPlan(sql="SELECT COUNT(*) FROM products"), frozenset({"products"})
    ).rows == [[6]]


def test_row_limit_does_not_return_a_partial_answer(store: Store) -> None:
    limited = Store(store.path, row_limit=1)
    with pytest.raises(QueryFailed, match="no partial answer"):
        limited.query(QueryPlan(sql="SELECT * FROM products"), frozenset({"products"}))


def test_query_timeout_is_enforced(store: Store) -> None:
    limited = Store(store.path, timeout_seconds=0.000000001)
    with pytest.raises(QueryFailed, match="timeout"):
        limited.query(
            QueryPlan(
                sql="SELECT COUNT(*) FROM products a CROSS JOIN products b CROSS JOIN products c"
            ),
            frozenset({"products"}),
        )


def test_reserved_parameter_is_rejected(store: Store) -> None:
    with pytest.raises(QueryRejected, match="reserved"):
        store.query(
            QueryPlan(sql="SELECT * FROM products", parameters={"_sample_limit": 10000}),
            frozenset({"products"}),
        )


def test_subqueries_cannot_escape_schema_scope(store: Store) -> None:
    with pytest.raises(QueryRejected, match="scope"):
        store.query(
            QueryPlan(sql="SELECT product_id, (SELECT COUNT(*) FROM orders) FROM products"),
            frozenset({"products"}),
        )


def test_valid_aggregate_and_single_semicolon(store: Store) -> None:
    result = store.query(
        QueryPlan(sql="SELECT COUNT(*) AS count FROM products;"), frozenset({"products"})
    )
    assert result.columns == ["count"]
    assert result.rows == [[6]]
