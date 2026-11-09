# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import json
from dataclasses import dataclass
from typing import Protocol

from .contracts import ModelUsage, QueryData

QUESTIONS = {
    "What were the top five product categories by revenue last month?": "category-revenue",
    "Which products are below their reorder point?": "inventory-below-reorder",
    "How many open orders are waiting for shipment?": "open-orders",
    "What is the average fulfillment time by region?": "fulfillment-by-region",
    "Which orders have missed their promised ship date?": "missed-ship-date",
    "Why were shipments delayed after leaving the warehouse?": "shipment-delay-cause",
}
SCOPES = {
    "category-revenue": ["products", "order_items", "orders"],
    "inventory-below-reorder": ["products", "inventory"],
    "open-orders": ["orders"],
    "fulfillment-by-region": ["orders", "customers"],
    "missed-ship-date": ["orders"],
}
QUERIES = {
    "category-revenue": """
        SELECT p.category, SUM(i.quantity * i.unit_price) AS revenue
        FROM order_items i JOIN products p ON p.product_id = i.product_id
        JOIN orders o ON o.order_id = i.order_id
        WHERE o.order_date >= :start AND o.order_date < :end
        GROUP BY p.category ORDER BY revenue DESC, p.category LIMIT 5
    """,
    "inventory-below-reorder": """
        SELECT p.product_id AS productId, p.product_name AS product,
               i.on_hand_quantity AS onHand, p.reorder_point AS reorderPoint
        FROM products p JOIN inventory i ON i.product_id = p.product_id
        WHERE i.on_hand_quantity < p.reorder_point ORDER BY p.product_id
    """,
    "open-orders": """
        SELECT COUNT(*) AS openOrders FROM orders WHERE status = 'open' AND shipped_date IS NULL
    """,
    "fulfillment-by-region": """
        SELECT c.region, AVG(julianday(o.shipped_date) - julianday(o.order_date)) AS days
        FROM orders o JOIN customers c ON c.customer_id = o.customer_id
        WHERE o.shipped_date IS NOT NULL GROUP BY c.region ORDER BY c.region
    """,
    "missed-ship-date": """
        SELECT order_id AS orderId, promised_ship_date AS promisedShipDate
        FROM orders
        WHERE shipped_date > promised_ship_date
           OR (shipped_date IS NULL AND promised_ship_date < :asOf)
        ORDER BY order_id
    """,
}


def summary(pattern: str, data: QueryData) -> str:
    if pattern == "open-orders":
        return f"Open orders waiting for shipment: {data.rows[0][0]}."
    return {
        "category-revenue": "Top categories by revenue for September 2026, in synthetic USD.",
        "inventory-below-reorder": "Products below their reorder point.",
        "fulfillment-by-region": "Average fulfillment time by region, in days.",
        "missed-ship-date": "Orders that missed their promised ship date as of 2026-10-01.",
    }[pattern]


class ModelDependencyError(RuntimeError):
    pass


@dataclass(frozen=True)
class ModelResponse:
    content: str
    usage: ModelUsage
    complete: bool = True


class ModelClient(Protocol):
    mode: str

    async def complete(self, role: str, context: dict[str, object]) -> str | ModelResponse:
        """Return JSON for one agent call, or raise ModelDependencyError."""
        ...


class DeterministicModel:
    """Explicit offline adapter, not evidence of live model or token behavior."""

    mode = "deterministic"

    async def complete(self, role: str, context: dict[str, object]) -> str:
        pattern = str(context.get("pattern", ""))
        if role == "coordinator":
            question = str(context["question"]).strip().rstrip("?").casefold()
            matched = next(
                (
                    value
                    for text, value in QUESTIONS.items()
                    if text.rstrip("?").casefold() == question
                ),
                "unknown",
            )
            return json.dumps({"pattern": matched})
        if role == "schema-agent":
            return json.dumps({"tables": SCOPES[pattern]})
        if role == "sql-agent":
            parameters: dict[str, str] = {}
            if pattern == "category-revenue":
                parameters = {"start": "2026-09-01", "end": "2026-10-01"}
            elif pattern == "missed-ship-date":
                parameters = {"asOf": "2026-10-01"}
            return json.dumps({"sql": QUERIES[pattern], "parameters": parameters})
        if role == "analysis-agent":
            data = QueryData.model_validate(context["data"])
            return json.dumps({"answer": summary(pattern, data)})
        raise ModelDependencyError("The offline adapter received an unsupported agent role.")
