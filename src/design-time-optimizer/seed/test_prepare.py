# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import copy
import csv
import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

import prepare


class SeedPreparationTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.now(timezone.utc)
        self.catalog = {
            "sourceUrl": "https://prices.azure.com/api/retail/prices?test",
            "retrievedAt": self.now.isoformat(),
            "Items": [
                {
                    "skuName": sku, "armRegionName": "eastus2", "currencyCode": "USD",
                    "type": "Consumption", "tierMinimumUnits": 0, "unitOfMeasure": "1M",
                    "isPrimaryMeterRegion": True, "effectiveStartDate": "2025-08-01T00:00:00Z",
                    "retailPrice": price, "meterId": role, "meterName": f"{sku} 1M Tokens",
                    "serviceName": "Foundry Models", "productName": "Azure OpenAI GPT5",
                    "serviceFamily": "AI + Machine Learning", "skuId": f"product/{role}",
                    "productId": "product", "location": "US East 2",
                }
                for (role, sku), price in zip(prepare.MODEL_SKUS.items(), (0.25, 0.025, 2.0))
            ],
        }

    def test_unhydrated_lfs_samples_fail_with_actionable_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "sample.csv"
            path.write_text("version https://git-lfs.github.com/spec/v1\noid sha256:" + "a" * 64 + "\nsize 100\n")
            with self.assertRaisesRegex(ValueError, "git lfs pull"):
                next(prepare.read_csv(path))

    def test_typed_conversion_uses_canonical_mapping_and_rejects_bad_values(self):
        row = {
            "BilledCost": "1.25", "ChargePeriodStart": "2024-06-01T00:00:00Z",
            "x_SkuIsCreditEligible": "false",
        }
        table = prepare.typed_table([row], "focuscost_1.0.json", "Sample", "FocusCost", "1.0")
        self.assertEqual(table.schema.field("BilledCost").type, pa.float64())
        self.assertEqual(table["ChargePeriodStart"][0].as_py(), datetime(2024, 6, 1, tzinfo=timezone.utc))
        self.assertFalse(table["x_SkuIsCreditEligible"][0].as_py())
        self.assertEqual(table["x_SourceType"][0].as_py(), "FocusCost")
        for bad in ("NaN", "inf", "not-a-number"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                prepare.typed_table([{"BilledCost": bad}], "focuscost_1.0.json", "Sample", "FocusCost", "1.0")
        with self.assertRaises(ValueError):
            prepare.timestamp("2024-06-01T00:00:00")
        with self.assertRaises(ValueError):
            prepare.typed_table([{"x_SkuIsCreditEligible": "yes"}], "focuscost_1.0.json", "Sample", "FocusCost", "1.0")

    def test_global_standard_excludes_batch_and_zone_prices(self):
        for row in copy.deepcopy(self.catalog["Items"]):
            row["skuName"] += " Batch"
            row["retailPrice"] /= 2
            self.catalog["Items"].append(row)
        rows, coverage = prepare.select_model_prices(self.catalog, "eastus2", self.now)
        self.assertEqual([row["MarketPrice"] for row in rows], [0.25, 0.025, 2.0])
        self.assertEqual(coverage["requiredMeters"]["cachedInput"]["tokensPerBillingUnit"], 1000000)
        self.assertTrue(all(row["EnrollmentNumber"] == prepare.RETAIL for row in rows))
        self.assertTrue(all(row["EffectiveEndDate"] == "" for row in rows))

    def test_missing_stale_ambiguous_and_inapplicable_prices_fail(self):
        changes = (
            lambda c: c["Items"].pop(),
            lambda c: c.update(retrievedAt=(self.now - timedelta(days=8)).isoformat()),
            lambda c: c.update(retrievedAt=(self.now + timedelta(hours=1)).isoformat()),
            lambda c: c["Items"].append(copy.deepcopy(c["Items"][0])),
            lambda c: c["Items"][0].update(retailPrice=0),
            lambda c: c["Items"][0].update(retailPrice=float("nan")),
            lambda c: c["Items"][0].update(armRegionName="eastus"),
            lambda c: c["Items"][0].update(currencyCode="EUR"),
            lambda c: c["Items"][0].update(unitOfMeasure="1K"),
            lambda c: c["Items"][0].update(skuName="GPT 5 Mini Inpt DZone"),
            lambda c: c.update(sourceUrl="https://example.com/prices"),
        )
        for change in changes:
            catalog = copy.deepcopy(self.catalog)
            change(catalog)
            with self.subTest(catalog=catalog), self.assertRaises(ValueError):
                prepare.select_model_prices(catalog, "eastus2", self.now)

    def test_history_requires_applicable_date_offer_region_and_units(self):
        cost = next(
            row for row in prepare.read_csv(prepare.ROOT / "src/open-data/dataset-examples/EA-Cost-FOCUS_1.0.csv")
            if row["x_SkuMeterCategory"] == "Virtual Machines"
            and row["PricingCategory"] == "Standard" and float(row["BilledCost"] or 0) > 0
        )
        price = next(
            row for row in prepare.read_csv(prepare.ROOT / "src/open-data/dataset-examples/EA-Prices.csv")
            if row["MeterID"] == cost["x_SkuMeterId"] and row["OfferID"] == cost["x_SkuOfferId"]
            and row["EnrollmentNumber"] == cost["x_BillingProfileId"] and row["PriceType"] == "Consumption"
            and row["MeterRegion"] == cost["x_SkuRegion"]
        )
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)

            def save(name, rows):
                path = directory / name
                with path.open("w", newline="") as stream:
                    writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
                    writer.writeheader()
                    writer.writerows(rows)
                return path

            cost_path = save("costs.csv", [cost])
            units_path = prepare.ROOT / "src/open-data/PricingUnits.csv"
            selected, prices, coverage = prepare.select_history(cost_path, save("prices.csv", [price]), units_path)
            self.assertEqual(coverage["coveredMeterOffers"], 1)
            self.assertEqual(selected[0]["ChargePeriodStart"], cost["ChargePeriodStart"])
            self.assertEqual(selected[0]["x_AccountOwnerId"], "")
            self.assertEqual(json.loads(selected[0]["Tags"])["ftk-dataset"], prepare.SAMPLE)
            self.assertEqual(prices[0]["EnrollmentNumber"], prepare.HISTORY)
            for change in (
                {"OfferID": "wrong"}, {"MeterRegion": "wrong"}, {"UnitOfMeasure": "1 GB"},
                {"EffectiveStartDate": "07/01/2024 00:00:00"}, {"MarketPrice": "0"},
            ):
                bad = dict(price, **change)
                with self.subTest(change=change), self.assertRaises(ValueError):
                    prepare.select_history(cost_path, save("prices.csv", [bad]), units_path)
            with self.assertRaises(ValueError):
                prepare.select_history(cost_path, save("prices.csv", [price, price]), units_path)

    def test_repeat_packages_replace_one_logical_partition_with_fresh_run_ids(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            results = [
                prepare.prepare(prepare.ROOT / "hack/sandbox.config.json", directory / str(run), "a" * 40, self.catalog)
                for run in (1, 2)
            ]
            self.assertEqual(results[0]["historicalCoverage"], results[1]["historicalCoverage"])
            self.assertEqual(results[0]["historicalCoverage"]["selectedRows"], 1878)
            for first, second in zip(results[0]["packages"], results[1]["packages"]):
                self.assertEqual(first["folder"], second["folder"])
                self.assertNotEqual(first["file"], second["file"])
                a = pq.read_table(directory / "1" / first["label"] / first["file"])
                b = pq.read_table(directory / "2" / second["label"] / second["file"])
                self.assertTrue(a.equals(b))
                manifest = json.loads((directory / "1" / first["label"] / "manifest.json").read_text())
                self.assertEqual(manifest["dataRowCount"], a.num_rows)
                self.assertEqual(manifest["blobCount"], 1)
                self.assertEqual(first["sha256"], prepare.digest(directory / "1" / first["label"] / first["file"]))
            with self.assertRaisesRegex(ValueError, "empty package"):
                prepare.prepare(prepare.ROOT / "hack/sandbox.config.json", directory / "1", "a" * 40, self.catalog)


if __name__ == "__main__":
    unittest.main()
