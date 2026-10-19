from __future__ import annotations

import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from server.main import create_app


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.app = create_app(self.temp.name)
        self.client = TestClient(self.app, base_url="http://127.0.0.1:8740")

    def tearDown(self):
        self.client.close()
        self.temp.cleanup()

    def test_shared_crud_conflict_bom_exports_and_delete(self):
        response = self.client.post("/api/projects", json={"name": "Kitchen", "template": "10ft"})
        self.assertEqual(response.status_code, 201, response.text)
        p = response.json()
        route = "/api/projects/" + p["id"]
        self.assertEqual(len(self.client.get("/api/projects").json()), 1)
        p["client"] = "Measured on site"
        updated = self.client.put(route, json={"base_revision": 1, "project": p})
        self.assertEqual(updated.status_code, 200)
        conflict = self.client.put(route, json={"base_revision": 1, "project": p})
        self.assertEqual(conflict.status_code, 409)
        self.assertEqual(conflict.json()["current_revision"], 2)
        self.assertEqual(self.client.get(route + "/bom").json()["totals"]["cabinet_count"], 10)
        self.assertEqual(self.client.get(route + "/quote").json()["status"], "unpriced")
        self.assertIn("Band L mm", self.client.get(route + "/bom.csv").text)
        self.assertIn("Unpriced", self.client.get(route + "/quote.csv").text)
        self.assertIn("Print / save PDF", self.client.get(route + "/print").text)
        self.assertEqual(self.client.delete(route + "?base_revision=1").status_code, 409)
        self.assertEqual(self.client.delete(route + "?base_revision=2").status_code, 204)
        self.assertEqual(self.client.get(route).status_code, 404)

    def test_cross_site_and_rebinding_are_refused(self):
        self.assertEqual(self.client.post("/api/projects", json={}, headers={"Origin": "https://evil.example"}).status_code, 403)
        self.assertEqual(self.client.post("/api/projects", json={}, headers={"Host": "evil.example:8740"}).status_code, 403)
        self.assertEqual(self.client.get("/api/projects", headers={"Origin": "null"}).status_code, 403)
        self.assertEqual(self.client.get("/api/projects", headers={"Sec-Fetch-Site": "cross-site"}).status_code, 403)
        self.assertEqual(self.client.post("/api/projects", json={}, headers={"Origin": "http://127.0.0.1:8740"}).status_code, 201)

    def test_worker_unavailable_returns_503_without_revision_change(self):
        p = self.client.post("/api/projects", json={"template": "empty"}).json()
        with patch("server.main.ruby_command", return_value=None):
            response = self.client.post(f"/api/projects/{p['id']}/generate", json={"base_revision": 1})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(self.app.state.store.get(p["id"])["revision"], 1)

    def test_health_has_no_api_secret_and_catalog_has_no_bottom_open_shelves(self):
        response = self.client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("api_key", response.text.lower())
        types = {item["type"] for item in self.client.get("/api/catalog").json()["cabinets"]}
        self.assertIn("wall_open", types)
        self.assertNotIn("base_open", types)


if __name__ == "__main__":
    unittest.main()
