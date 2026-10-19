"""Dimensions-only projects must never depend on a photo or an AI request."""
from __future__ import annotations

import tempfile
import unittest
import uuid
import copy
from unittest.mock import patch

from fastapi.testclient import TestClient

from server.main import create_app, ruby_command
from server.models import APP_DIR


PHOTO_FIELDS = {"photo_asset_id", "original_photo_asset_id", "rectified_asset_id", "annotated_asset_id", "photo_quad", "photo_width_px", "photo_height_px", "rectification", "analysis", "analysis_input_hash"}
RUBY_AVAILABLE = bool(ruby_command() and (APP_DIR / "project_bridge.rb").is_file())


class PhotolessProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.client = TestClient(create_app(self.temp.name), base_url="http://127.0.0.1:8740")

    def tearDown(self):
        self.client.close()
        self.temp.cleanup()

    def create_measured_project(self):
        response = self.client.post("/api/projects", json={"name": "මගේ කුස්සිය · சமையலறை · Café", "client": "Asanka — site measurements", "template": "empty"})
        self.assertEqual(response.status_code, 201, response.text)
        p = response.json()
        self.assertEqual(p["room"]["walls"], [])
        wall = {"id": str(uuid.uuid4()), "name": "උතුරු බිත්තිය / வடக்கு சுவர்", "width_mm": 3200, "height_mm": 2600, "measurements_confirmed": True, "openings": []}
        self.assertFalse(PHOTO_FIELDS.intersection(wall))
        p["room"]["walls"] = [wall]
        response = self.client.put("/api/projects/" + p["id"], json={"base_revision": p["revision"], "project": p})
        self.assertEqual(response.status_code, 200, response.text)
        p = response.json()
        self.assertEqual(p["revision"], 2)
        saved_wall = p["room"]["walls"][0]
        self.assertFalse(PHOTO_FIELDS.intersection(saved_wall))
        self.assertEqual(saved_wall["origin_mm"], [0, 0, 0])
        self.assertEqual(saved_wall["thickness_mm"], 150)
        return p

    def test_measured_wall_saves_without_any_photo_fields(self):
        p = self.create_measured_project()
        loaded = self.client.get("/api/projects/" + p["id"]).json()
        self.assertEqual(loaded["name"], "මගේ කුස්සිය · சமையலறை · Café")
        self.assertEqual(loaded["room"]["walls"], p["room"]["walls"])
        self.assertEqual(loaded["manufacturing"]["status"], "needs_regeneration")

    @unittest.skipUnless(RUBY_AVAILABLE, "A local Ruby worker is required for manufacturing integration")
    def test_photoless_cabinets_generate_and_price_from_the_actual_ruby_parts(self):
        p = self.create_measured_project()
        wall_id = p["room"]["walls"][0]["id"]
        p["design"]["cabinets"] = [
            {"id": str(uuid.uuid4()), "local_id": "B01", "name": "පහළ කැබිනට් / கீழ் பெட்டி", "type": "base_single", "wall_id": wall_id, "width_mm": 600, "height_mm": 720, "depth_mm": 560, "x_mm": 0, "y_mm": 0, "z_mm": 0, "rotation_deg": 0, "options": {}},
            {"id": str(uuid.uuid4()), "local_id": "W01", "name": "ඉහළ විවෘත රාක්කය", "type": "wall_open", "wall_id": wall_id, "width_mm": 300, "height_mm": 600, "depth_mm": 330, "x_mm": 600, "y_mm": 0, "z_mm": 1600, "rotation_deg": 0, "options": {}},
        ]
        route = "/api/projects/" + p["id"]
        response = self.client.put(route, json={"base_revision": p["revision"], "project": p})
        self.assertEqual(response.status_code, 200, response.text)
        p = response.json()
        # Any accidental image or paid-vision dependency fails this flow.
        with patch("server.photos.AssetStore", side_effect=AssertionError("Dimensions-only projects must not access photo assets")), patch("server.photos.analyze_wall", side_effect=AssertionError("Dimensions-only projects must not call AI")):
            response = self.client.post(route + "/generate", json={"base_revision": p["revision"]})
        self.assertEqual(response.status_code, 200, response.text)
        p = response.json()
        generated_revision = p["revision"]
        self.assertEqual(p["manufacturing"]["status"], "current")
        self.assertFalse(PHOTO_FIELDS.intersection(p["room"]["walls"][0]))
        job = p["manufacturing"]["job"]
        self.assertEqual(job["room"]["walls"], p["room"]["walls"])
        self.assertEqual({c["id"] for c in job["cabinets"]}, {"B01", "W01"})
        self.assertEqual(job["cabinets"][0]["name"], "පහළ කැබිනට් / கீழ் பெட்டி")
        self.assertTrue(any(op["kind"] == "groove" for c in job["cabinets"] for part in c["parts"] for op in part["operations"]))
        for key in p["quote"]["rates"]:
            p["quote"]["rates"][key] = 1000
        p["quote"].update(labour=1500, markup_pct=10, tax_pct=5)
        response = self.client.put(route, json={"base_revision": p["revision"], "project": p})
        self.assertEqual(response.status_code, 200, response.text)
        priced = response.json()
        self.assertEqual(priced["manufacturing"]["status"], "current")
        bom = self.client.get(route + "/bom").json()
        quote = self.client.get(route + "/quote").json()
        self.assertEqual(bom["status"], "current")
        self.assertEqual(bom["source_revision"], generated_revision)
        self.assertEqual(bom["totals"]["cabinet_count"], 2)
        self.assertGreater(bom["totals"]["part_count"], 0)
        self.assertGreater(bom["totals"]["operation_count"], 0)
        self.assertEqual(quote["status"], "estimate")
        self.assertEqual(quote["manufacturing_status"], "current")
        self.assertEqual(quote["missing_rates"], [])
        self.assertGreater(quote["total"], 1500)
        self.assertIn("මගේ කුස්සිය", self.client.get(route + "/print").text)
        self.assertEqual(next(part for part in bom["parts"] if part["cabinet_id"] == "B01")["cabinet_name"], "පහළ කැබිනට් / கீழ் பெட்டி")
        self.assertIn(priced["name"], self.client.get(route + "/bom.csv").text)

    def test_preview_uses_the_same_bom_and_quote_without_saving_a_revision(self):
        p = self.client.post("/api/projects", json={"name": "Local preview", "template": "10ft"}).json()
        route = "/api/projects/" + p["id"]
        original = self.client.get(route).json()
        saved_bom = self.client.get(route + "/bom").json()
        saved_quote = self.client.get(route + "/quote").json()
        generated = {key: p["manufacturing"][key] for key in ("job", "nesting")}
        response = self.client.post("/api/preview", json={"project": p, "generated": generated})
        self.assertEqual(response.status_code, 200, response.text)
        report = response.json()
        self.assertTrue(report["preview"])
        self.assertTrue(report["bom"].pop("preview"))
        self.assertTrue(report["quote"].pop("preview"))
        self.assertEqual(report["bom"], saved_bom)
        self.assertEqual(report["quote"]["notices"].pop(0), "Local preview - not saved to web")
        self.assertEqual(report["quote"], saved_quote)
        self.assertEqual(self.client.get(route).json(), original)
        self.assertEqual(len(self.client.get("/api/projects").json()), 1)
        # A not-yet-saved local project is also a valid preview, without creating
        # a project row or changing the existing project's accepted revision.
        draft = copy.deepcopy(p)
        draft["id"] = str(uuid.uuid4())
        draft["revision"] = 0
        response = self.client.post("/api/preview", json={"project": draft, "generated": generated})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["bom"]["source_revision"], 0)
        self.assertEqual(self.client.get("/api/projects/" + draft["id"]).status_code, 404)
        self.assertEqual(self.client.get(route).json(), original)

    def test_preview_rejects_old_manifest_and_invalid_geometry_without_saving(self):
        p = self.client.post("/api/projects", json={"template": "10ft"}).json()
        generated = {key: p["manufacturing"][key] for key in ("job", "nesting")}
        route = "/api/projects/" + p["id"]
        for change in ("manifest", "geometry"):
            with self.subTest(change=change):
                bad = copy.deepcopy(p)
                if change == "manifest":
                    bad["design"]["cabinets"][4]["options"]["role"] = "standard"
                else:
                    bad["room"]["walls"][0]["width_mm"] = -100
                response = self.client.post("/api/preview", json={"project": bad, "generated": generated})
                self.assertEqual(response.status_code, 422, response.text)
                self.assertEqual(self.client.get(route).json(), p)

    @unittest.skipUnless(RUBY_AVAILABLE, "A local Ruby worker is required for room handoff integration")
    def test_measured_wall_without_cabinets_generates_room_handoff(self):
        p = self.create_measured_project()
        route = "/api/projects/" + p["id"]
        with patch("server.photos.AssetStore", side_effect=AssertionError("An empty measured room needs no photo assets")), patch("server.photos.analyze_wall", side_effect=AssertionError("An empty measured room needs no AI")):
            response = self.client.post(route + "/generate", json={"base_revision": p["revision"]})
        self.assertEqual(response.status_code, 200, response.text)
        generated = response.json()
        self.assertEqual(generated["manufacturing"]["status"], "current")
        self.assertEqual(generated["manufacturing"]["job"]["cabinets"], [])
        self.assertEqual(generated["manufacturing"]["nesting"], [])
        self.assertEqual(generated["manufacturing"]["job"]["room"]["walls"], p["room"]["walls"])
        self.assertEqual(self.client.get(route + "/bom").json()["totals"]["part_count"], 0)
        self.assertEqual(self.client.get(route + "/quote").json()["status"], "unpriced")


if __name__ == "__main__":
    unittest.main()
