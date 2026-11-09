# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import random
import sqlite3
import time
from contextlib import closing
from pathlib import Path

import sqlglot
from sqlglot import exp
from sqlglot.errors import ParseError

from .contracts import QueryData, QueryPlan

TABLES = frozenset({"customers", "products", "inventory", "orders", "order_items", "shipments"})
FUNCTIONS = frozenset({"count", "sum", "avg", "julianday", "coalesce", "round", "abs"})
SCHEMA = """
CREATE TABLE customers(customer_id TEXT PRIMARY KEY, region TEXT, customer_segment TEXT);
CREATE TABLE products(
    product_id TEXT PRIMARY KEY, product_name TEXT, category TEXT,
    unit_price INTEGER, reorder_point INTEGER
);
CREATE TABLE inventory(
    product_id TEXT REFERENCES products, warehouse TEXT, on_hand_quantity INTEGER,
    reserved_quantity INTEGER, updated_at TEXT
);
CREATE TABLE orders(
    order_id TEXT PRIMARY KEY, customer_id TEXT REFERENCES customers, order_date TEXT,
    promised_ship_date TEXT, shipped_date TEXT, delivered_date TEXT, status TEXT,
    total_amount INTEGER
);
CREATE TABLE order_items(
    order_id TEXT REFERENCES orders, product_id TEXT REFERENCES products,
    quantity INTEGER, unit_price INTEGER
);
CREATE TABLE shipments(
    shipment_id TEXT PRIMARY KEY, order_id TEXT REFERENCES orders, carrier TEXT,
    current_status TEXT, shipped_at TEXT, delivered_at TEXT
);
PRAGMA user_version = 1;
"""


class QueryRejected(ValueError):
    pass


class QueryFailed(RuntimeError):
    pass


class DatabaseUnavailable(RuntimeError):
    pass


def initialize(path: Path, seed: int = 42) -> None:
    """Create a new database; never overwrite an existing workload."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb"):
        pass
    rng = random.Random(seed)
    products = [
        ("P-1001", "Tent", "Camping", 100, 10),
        ("P-1002", "Lantern", "Camping", 20, 5),
        ("P-1003", "Boots", "Footwear", 80, 8),
        ("P-1004", "Jacket", "Apparel", 60, 5),
        ("P-1005", "Kayak", "Water sports", 200, 4),
        ("P-1006", "Backpack", "Packs", 50, 10),
    ]
    # Curated dates make time-based questions independent of the machine clock.
    orders = [
        ("O-1", "C-1", "2026-09-01", "2026-09-03", "2026-09-02", "2026-09-05", "P-1001", 2),
        ("O-2", "C-2", "2026-09-05", "2026-09-07", "2026-09-08", "2026-09-10", "P-1003", 3),
        ("O-3", "C-3", "2026-09-10", "2026-09-12", "2026-09-11", "2026-09-14", "P-1004", 3),
        ("O-4", "C-1", "2026-09-15", "2026-09-17", None, None, "P-1005", 2),
        ("O-5", "C-2", "2026-09-20", "2026-09-22", "2026-09-21", "2026-09-24", "P-1006", 3),
        ("O-6", "C-3", "2026-09-25", "2026-09-27", None, None, "P-1002", 4),
        ("O-7", "C-1", "2026-10-01", "2026-10-03", None, None, "P-1001", 1),
    ]
    with closing(sqlite3.connect(path)) as connection, connection:
        connection.execute("PRAGMA foreign_keys = ON")
        connection.executescript(SCHEMA)
        connection.executemany(
            "INSERT INTO customers VALUES (?, ?, ?)",
            [
                (f"C-{index}", region, rng.choice(["retail", "business"]))
                for index, region in enumerate(["North", "South", "West"], 1)
            ],
        )
        connection.executemany("INSERT INTO products VALUES (?, ?, ?, ?, ?)", products)
        connection.executemany(
            "INSERT INTO inventory VALUES (?, ?, ?, ?, ?)",
            [
                (product[0], "W-1", stock, rng.randint(0, 2), "2026-10-01")
                for product, stock in zip(products, [30, 3, 20, 2, 10, 25], strict=True)
            ],
        )
        prices = {product[0]: product[3] for product in products}
        for (
            order_id,
            customer,
            ordered,
            promised,
            shipped,
            delivered,
            product_id,
            quantity,
        ) in orders:
            price = prices[product_id]
            connection.execute(
                "INSERT INTO orders VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    order_id,
                    customer,
                    ordered,
                    promised,
                    shipped,
                    delivered,
                    "delivered" if delivered else "open",
                    price * quantity,
                ),
            )
            connection.execute(
                "INSERT INTO order_items VALUES (?, ?, ?, ?)",
                (order_id, product_id, quantity, price),
            )
            if shipped:
                connection.execute(
                    "INSERT INTO shipments VALUES (?, ?, ?, ?, ?, ?)",
                    (f"S-{order_id}", order_id, "Contoso Carrier", "delivered", shipped, delivered),
                )


class Store:
    def __init__(self, path: Path, *, row_limit: int = 100, timeout_seconds: float = 1.0):
        if row_limit < 1 or timeout_seconds <= 0:
            raise ValueError("Query limits must be positive.")
        self.path = path
        self.row_limit = row_limit
        self.timeout_seconds = timeout_seconds

    def connect(self) -> sqlite3.Connection:
        try:
            connection = sqlite3.connect(
                f"{self.path.resolve().as_uri()}?mode=ro", uri=True, timeout=self.timeout_seconds
            )
            connection.execute("PRAGMA query_only = ON")
            return connection
        except sqlite3.Error as error:
            raise DatabaseUnavailable("The synthetic database is unavailable.") from error

    def verify(self) -> None:
        with closing(self.connect()) as connection:
            try:
                version = connection.execute("PRAGMA user_version").fetchone()[0]
                tables = {
                    row[0]
                    for row in connection.execute(
                        "SELECT name FROM sqlite_master WHERE type = 'table'"
                    )
                }
                if version != 1 or tables != TABLES:
                    raise DatabaseUnavailable("The synthetic database schema is not initialized.")
            except sqlite3.Error as error:
                raise DatabaseUnavailable("The synthetic database cannot be read.") from error

    def query(self, plan: QueryPlan, allowed_tables: frozenset[str]) -> QueryData:
        if not allowed_tables or not allowed_tables <= TABLES:
            raise QueryRejected("The query scope is not approved.")
        try:
            statements = sqlglot.parse(plan.sql, read="sqlite")
        except ParseError as error:
            raise QueryRejected("The SQL syntax is invalid.") from error
        if len(statements) != 1 or not isinstance(statements[0], exp.Select):
            raise QueryRejected("Only one SELECT statement is permitted.")
        statement = statements[0]
        if statement.find(exp.With) or statement.find(exp.Into):
            raise QueryRejected("CTEs and SELECT INTO are not permitted.")
        for table in statement.find_all(exp.Table):
            if table.name.lower() not in allowed_tables or table.db or table.catalog:
                raise QueryRejected("The query references a table outside its approved scope.")
        if "_sample_limit" in plan.parameters:
            raise QueryRejected("The query uses a reserved parameter.")

        def authorize(
            action: int,
            first: str | None,
            second: str | None,
            database: str | None,
            source: str | None,
        ) -> int:
            if action == sqlite3.SQLITE_SELECT:
                return sqlite3.SQLITE_OK
            if action == sqlite3.SQLITE_READ and first and first.lower() in allowed_tables:
                return sqlite3.SQLITE_OK
            if action == sqlite3.SQLITE_FUNCTION and second and second.lower() in FUNCTIONS:
                return sqlite3.SQLITE_OK
            return sqlite3.SQLITE_DENY

        deadline = time.monotonic() + self.timeout_seconds
        with closing(self.connect()) as connection:
            connection.set_authorizer(authorize)
            connection.set_progress_handler(lambda: int(time.monotonic() >= deadline), 100)
            try:
                cursor = connection.execute(
                    f"SELECT * FROM ({statement.sql(dialect='sqlite')}) LIMIT :_sample_limit",
                    {**plan.parameters, "_sample_limit": self.row_limit + 1},
                )
                rows = cursor.fetchall()
                if len(rows) > self.row_limit:
                    raise QueryFailed(
                        "The query exceeded its row limit; no partial answer returned."
                    )
                return QueryData(
                    columns=[column[0] for column in cursor.description],
                    rows=[list(row) for row in rows],
                )
            except sqlite3.DatabaseError as error:
                if "not authorized" in str(error) or "prohibited" in str(error):
                    raise QueryRejected("SQLite denied an unapproved operation.") from error
                raise QueryFailed("The query failed or exceeded its execution timeout.") from error
