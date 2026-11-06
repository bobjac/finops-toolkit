# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Prepare explicitly labeled history and applicable prices for hub ingestion."""

import argparse
import csv
import hashlib
import json
import math
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[3]
EXPORT_SCHEMAS = ROOT / "src/templates/finops-hub/modules/Microsoft.CostManagement/Exports/schemas"
HISTORY = "dto-history-v1"
RETAIL = "dto-retail-public-v1"
SAMPLE = "sample-history-v1"
MODEL_SKUS = {
    "input": "GPT 5 Mini Inpt Glbl",
    "cachedInput": "GPT 5 Mini cchd Inpt Glbl",
    "output": "GPT 5 Mini outpt Glbl",
}


def timestamp(value):
    if not value:
        return None
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        result = datetime.strptime(value, "%m/%d/%Y %H:%M:%S").replace(tzinfo=timezone.utc)
    if result.tzinfo is None:
        raise ValueError(f"Timestamp has no time zone: {value}")
    return result.astimezone(timezone.utc)


def number(value):
    if value in ("", None):
        return None
    result = float(value)
    if not math.isfinite(result):
        raise ValueError("Nonfinite numeric value in seed data")
    return result


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        if stream.readline().rstrip("\r\n") == "version https://git-lfs.github.com/spec/v1":
            raise ValueError(f"Git LFS content is missing for {path.name}; run git lfs pull for the required samples")
        stream.seek(0)
        yield from csv.DictReader(stream)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def typed_table(rows, schema_name, source_name, source_type, version):
    mappings = json.loads((EXPORT_SCHEMAS / schema_name).read_text())["translator"]["mappings"]
    fields = []
    converted = {}
    for mapping in mappings:
        source, sink = mapping["source"], mapping["sink"]["name"]
        kind = source["type"]
        if kind in ("Decimal", "Double"):
            arrow_type, convert = pa.float64(), number
        elif kind in ("DateTimeOffset", "DateTime"):
            arrow_type, convert = pa.timestamp("us", tz="UTC"), timestamp
        elif kind == "Boolean":
            arrow_type = pa.bool_()

            def convert(value):
                if value in ("", None):
                    return None
                if str(value).casefold() not in ("true", "false"):
                    raise ValueError(f"Invalid Boolean value: {value}")
                return str(value).casefold() == "true"
        elif kind == "String":
            arrow_type, convert = pa.string(), lambda value: value or None
        else:
            raise ValueError(f"Unsupported repository schema type: {kind}")
        fields.append(pa.field(sink, arrow_type))
        converted[sink] = [convert(row.get(source["name"])) for row in rows]
    for name, value in {
        "x_SourceName": source_name,
        "x_SourceProvider": "Microsoft",
        "x_SourceType": source_type,
        "x_SourceVersion": version,
    }.items():
        fields.append(pa.field(name, pa.string()))
        converted[name] = [value] * len(rows)
    return pa.Table.from_pydict(converted, schema=pa.schema(fields))


def select_history(cost_path, price_path, units_path):
    units = {row["UnitOfMeasure"]: row for row in read_csv(units_path)}
    costs = [
        row for row in read_csv(cost_path)
        if row["x_SkuMeterCategory"] == "Virtual Machines"
        and row["ChargeCategory"] == "Usage"
        and row["PricingCategory"] == "Standard"
        and row["BillingCurrency"] == "USD"
        and number(row["BilledCost"]) is not None and number(row["BilledCost"]) > 0
        and number(row["PricingQuantity"]) is not None and number(row["PricingQuantity"]) > 0
        and row["ChargePeriodStart"].startswith("2024-06-")
        and not row["ChargeClass"]
    ]

    def key(row):
        return row["x_SkuMeterId"], row["x_SkuOfferId"], row["x_BillingProfileId"]

    required = {key(row) for row in costs}
    prices = defaultdict(list)
    for row in read_csv(price_path):
        price_key = row["MeterID"], row["OfferID"], row["EnrollmentNumber"]
        if (
            price_key in required and row["CurrencyCode"] == "USD"
            and row["PriceType"] == "Consumption" and not row["Term"]
            and number(row["MarketPrice"]) is not None and number(row["MarketPrice"]) > 0
            and number(row["UnitPrice"]) is not None and number(row["UnitPrice"]) > 0
            and row["UnitOfMeasure"] in units
        ):
            prices[price_key].append(row)
    selected, matched = [], {}
    excluded = defaultdict(int)
    for row in costs:
        matches = [
            price for price in prices[key(row)]
            if timestamp(price["EffectiveStartDate"]) <= timestamp(row["ChargePeriodStart"])
            and timestamp(price["EffectiveEndDate"]) >= timestamp(row["ChargePeriodEnd"])
            and price["MeterRegion"] == row["x_SkuRegion"]
            and row["x_PricingUnitDescription"] in units
            and units[price["UnitOfMeasure"]]["DistinctUnits"] == units[row["x_PricingUnitDescription"]]["DistinctUnits"]
        ]
        if len(matches) != 1:
            excluded["missingOrAmbiguousApplicablePrice"] += 1
            continue
        if key(row) in matched and matched[key(row)] != matches[0]:
            raise ValueError("Selected monthly history requires multiple price variants for one meter and offer")
        selected.append(row)
        matched[key(row)] = matches[0]
    if not selected:
        raise ValueError("No VM history has unambiguous date, region, offer, currency, and unit price coverage")
    selected.sort(key=lambda row: (row["ChargePeriodStart"], row["ResourceId"], row["x_SkuMeterId"], row["BilledCost"]))
    source_profiles = sorted({row["x_BillingProfileId"] for row in selected})
    for row in selected:
        row["BillingAccountId"] = f"/providers/Microsoft.Billing/billingAccounts/{HISTORY}"
        row["BillingAccountName"] = "Hack sample history (June 2024)"
        for field in ("x_BillingAccountId", "x_BillingProfileId"):
            row[field] = HISTORY
        for field in ("x_BillingAccountName", "x_BillingProfileName"):
            row[field] = "Hack sample history (June 2024)"
        row["x_AccountOwnerId"] = ""
        tags = json.loads(row["Tags"] or "{}")
        tags["ftk-dataset"] = SAMPLE
        row["Tags"] = json.dumps(tags, sort_keys=True)
    historical_prices = sorted(matched.values(), key=lambda row: (row["MeterID"], row["OfferID"]))
    for row in historical_prices:
        row["EnrollmentNumber"] = HISTORY
    return selected, historical_prices, {
        "candidateRows": len(costs), "selectedRows": len(selected),
        "excluded": dict(excluded), "sourceBillingProfiles": source_profiles,
        "requiredMeterOffers": len(matched), "coveredMeterOffers": len(matched),
        "dateTreatment": "Original June 2024 dates; no date shifting",
        "priceTimestampTreatment": "Timezone-free EA sample timestamps use UTC, matching the FOCUS usage dates",
        "identityTreatment": "Billing identity isolated as dto-history-v1; resource/subscription IDs remain sample context, never mutation targets",
    }


def fetch_retail(region):
    query = urllib.parse.urlencode({
        "api-version": "2023-01-01-preview",
        "$filter": f"armRegionName eq '{region}' and contains(meterName, 'GPT 5 Mini')",
    })
    url = f"https://prices.azure.com/api/retail/prices?{query}"
    source_url, items, seen = url, [], set()
    while url:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" or parsed.netloc != "prices.azure.com" or parsed.path != "/api/retail/prices" or url in seen or len(seen) >= 20:
            raise ValueError("Invalid, repeated, or excessive retail catalog pagination")
        seen.add(url)
        for attempt in range(4):
            try:
                with urllib.request.urlopen(url, timeout=60) as response:
                    page = json.load(response)
                break
            except urllib.error.HTTPError as error:
                if error.code not in (429, 503) or attempt == 3:
                    raise
                delay = int(error.headers.get("Retry-After", "15"))
                if not 0 <= delay <= 120:
                    raise ValueError("Retail catalog retry delay exceeds the bounded limit") from error
                time.sleep(delay)
        items.extend(page["Items"])
        url = page.get("NextPageLink")
    return {"sourceUrl": source_url, "retrievedAt": datetime.now(timezone.utc).isoformat(), "Items": items}


def select_model_prices(catalog, region, now):
    fetched = timestamp(catalog["retrievedAt"])
    if not fetched or not 0 <= (now - fetched).total_seconds() <= 7 * 86400:
        raise ValueError("Retail price snapshot must be no more than seven days old and not future-dated")
    if not catalog["sourceUrl"].startswith("https://prices.azure.com/api/retail/prices?"):
        raise ValueError("Model prices must identify the authoritative Azure retail catalog")
    rows, coverage = [], {}
    for role, sku in MODEL_SKUS.items():
        matches = [
            row for row in catalog["Items"]
            if row["skuName"] == sku and row["armRegionName"] == region
            and row["currencyCode"] == "USD" and row["type"] == "Consumption"
            and row["tierMinimumUnits"] == 0 and row["unitOfMeasure"] == "1M"
            and row["isPrimaryMeterRegion"] is True and timestamp(row["effectiveStartDate"]) <= now
        ]
        if matches:
            latest = max(row["effectiveStartDate"] for row in matches)
            matches = [row for row in matches if row["effectiveStartDate"] == latest]
        if len(matches) != 1 or number(matches[0]["retailPrice"]) is None or number(matches[0]["retailPrice"]) <= 0:
            raise ValueError(f"Missing, ambiguous, or invalid required model price: {role}")
        row = matches[0]
        rows.append({
            "EnrollmentNumber": RETAIL, "MeterID": row["meterId"], "MeterName": row["meterName"],
            "MeterType": row["type"], "MeterCategory": row["serviceName"],
            "MeterSubCategory": row["productName"], "ServiceFamily": row["serviceFamily"],
            "Product": row["productName"], "SkuID": row["skuId"].split("/")[-1],
            "ProductID": row["productId"], "MeterRegion": row["location"],
            "UnitOfMeasure": row["unitOfMeasure"], "EffectiveStartDate": row["effectiveStartDate"],
            "EffectiveEndDate": "", "UnitPrice": row["retailPrice"], "BasePrice": row["retailPrice"],
            "MarketPrice": row["retailPrice"], "CurrencyCode": "USD", "IncludedQuantity": 0,
            "OfferID": "PUBLIC-RETAIL", "PriceType": "Consumption",
        })
        coverage[role] = {
            "meterId": row["meterId"], "meterName": row["meterName"], "skuName": sku,
            "usdPerMillionTokens": row["retailPrice"], "tokensPerBillingUnit": 1000000,
            "effectiveStart": row["effectiveStartDate"],
        }
    return rows, {
        "model": "gpt-5-mini", "deploymentSku": "GlobalStandard", "region": region,
        "currency": "USD", "basis": "Public retail estimate, not a negotiated account price",
        "sourceUrl": catalog["sourceUrl"], "retrievedAt": catalog["retrievedAt"],
        "freshnessLimitDays": 7, "requiredMeters": coverage,
        "cachedInputSemantics": "Cached input is a separate rate, not an additional subtraction from an already uncached input quantity",
    }


def package(output, label, dataset, profile, period, rows, schema_name, source_name, source_type, source_version):
    directory = output / label
    directory.mkdir(parents=True, exist_ok=True)
    run_id = str(uuid.uuid4())
    filename = f"{run_id}__seed.parquet"
    table = typed_table(rows, schema_name, source_name, source_type, source_version)
    pq.write_table(table, directory / filename, compression="snappy")
    folder = f"{dataset}/{period[:4]}/{period[5:7]}/providers/microsoft.billing/billingaccounts/{profile}"
    manifest = {
        "version": 1, "blobCount": 1, "dataRowCount": len(rows),
        "runInfo": {"runId": run_id, "startDate": period},
        "blobs": [{"blobName": f"{folder}/{filename}", "dataRowCount": len(rows), "byteCount": (directory / filename).stat().st_size}],
        "sample": True,
    }
    write_json(directory / "manifest.json", manifest)
    result = {
        "label": label, "dataset": dataset, "profile": profile, "folder": folder,
        "file": filename, "sha256": digest(directory / filename), "rowCount": len(rows),
    }
    if dataset == "Costs":
        result["billedCost"] = math.fsum(number(row["BilledCost"]) for row in rows)
        result["pricingQuantity"] = math.fsum(number(row["PricingQuantity"]) for row in rows)
        result["startDate"] = min(row["ChargePeriodStart"] for row in rows)
        result["endDate"] = max(row["ChargePeriodEnd"] for row in rows)
    else:
        units = {row["UnitOfMeasure"]: row for row in read_csv(ROOT / "src/open-data/PricingUnits.csv")}
        result["prices"] = [
            {
                "meterId": row["MeterID"], "offer": row["OfferID"],
                "listPrice": number(row["MarketPrice"]), "contractedPrice": number(row["UnitPrice"]),
                "unit": row["UnitOfMeasure"],
                "blockSize": number(units[row["UnitOfMeasure"]]["PricingBlockSize"]),
                "region": row["MeterRegion"],
                "effectiveStart": timestamp(row["EffectiveStartDate"]).isoformat(),
            }
            for row in rows
        ]
    return result


def prepare(config_path, output, revision, catalog=None):
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Source revision must be a complete Git commit SHA")
    config = json.loads(config_path.read_text())
    if config["model"]["preferredNames"] != ["gpt-5-mini"] or config["model"]["deploymentSku"] != "GlobalStandard":
        raise ValueError("The seed price adapter requires the approved gpt-5-mini GlobalStandard profile")
    if not re.fullmatch(r"[a-z][a-z0-9]+", config["region"]):
        raise ValueError("Invalid sandbox region")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Use an empty package output directory to avoid mixing seed runs")
    output.mkdir(parents=True, exist_ok=True)
    sources = ROOT / "src/open-data/dataset-examples"
    costs, historical_prices, historical_coverage = select_history(
        sources / "EA-Cost-FOCUS_1.0.csv", sources / "EA-Prices.csv", ROOT / "src/open-data/PricingUnits.csv"
    )
    catalog = catalog if catalog is not None else fetch_retail(config["region"])
    now = datetime.now(timezone.utc)
    model_prices, model_coverage = select_model_prices(catalog, config["region"], now)
    write_json(output / "retail-source.json", catalog)
    packages = [
        package(output, "history-prices", "Prices", HISTORY, "2024-06-01T00:00:00Z", historical_prices, "pricesheet_2023-05-01_ea.json", "FinOps hack historical prices", "PriceSheet", "2023-05-01"),
        package(output, "model-prices", "Prices", RETAIL, "2024-06-01T00:00:00Z", model_prices, "pricesheet_2023-05-01_ea.json", "Azure retail catalog", "PriceSheet", "2023-05-01"),
        package(output, "history-costs", "Costs", HISTORY, "2024-06-01T00:00:00Z", costs, "focuscost_1.0.json", "FinOps hack sample history", "FocusCost", "1.0"),
    ]
    metadata = {
        "version": 1, "sourceRevision": revision, "seedVersion": SAMPLE,
        "sourceFiles": {name: digest(sources / name) for name in ("EA-Cost-FOCUS_1.0.csv", "EA-Prices.csv")},
        "schemaFiles": {name: digest(EXPORT_SCHEMAS / name) for name in ("focuscost_1.0.json", "pricesheet_2023-05-01_ea.json")},
        "historicalCoverage": historical_coverage, "modelCoverage": model_coverage, "packages": packages,
        "provenance": "Historical toolkit samples, not measured sandbox usage or savings. Prices use canonical EA-shaped raw normalization; PUBLIC-RETAIL is a synthetic label, not a contract offer. Original retail units 1M are retained; token semantics come from the authoritative meter names.",
        "partition": "June 2024 is a stable replacement partition for all seed packages, not the retail price effective period. Original effectiveStartDate values are preserved.",
    }
    write_json(output / "seed.json", metadata)
    return metadata


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "hack/sandbox.config.json")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--retail-snapshot", type=Path, help="Explicitly reuse the first pass's unchanged, freshness-checked public snapshot")
    arguments = parser.parse_args()
    snapshot = json.loads(arguments.retail_snapshot.read_text()) if arguments.retail_snapshot else None
    result = prepare(arguments.config, arguments.output, arguments.source_revision, snapshot)
    print(json.dumps({"packages": [(item["label"], item["rowCount"]) for item in result["packages"]], "modelCoverage": result["modelCoverage"]}, indent=2))
