"""Actual Ruby worker round trip; no native SketchUp UI or external API calls."""
from __future__ import annotations

import copy
import tempfile
import unittest
from uuid import uuid4

from fastapi.testclient import TestClient

from server.main import create_app, generate_project, ruby_command


@unittest.skipUnless(ruby_command(), "A Ruby manufacturing worker is required")
class RubyRoundTripTests(unittest.TestCase):
    def test_custom_wall_web_design_ruby_client_edit_and_shared_bom_quote(self):
        with tempfile.TemporaryDirectory() as directory:
            with TestClient(create_app(directory), base_url="http://127.0.0.1:8740") as client:
                project = client.post("/api/projects", json={"name": "Measured custom kitchen"}).json()
                route = "/api/projects/" + project["id"]
                wall_id = str(uuid4())
                project["room"]["walls"] = [{"id": wall_id, "name": "Measured return wall", "width_mm": 3600,
                    "height_mm": 2600, "thickness_mm": 150, "origin_mm": [400, 600, 0], "rotation_deg": 90,
                    "measurements_confirmed": True, "openings": []}]
                rows = [("B01", "tall_pantry", 450, 2100, 580, 24, 0),
                        ("B02", "tall_oven_micro", 600, 2100, 580, 474, 0),
                        ("B03", "base_sink", 600, 720, 560, 1074, 0),
                        ("B04", "base_gola", 600, 720, 560, 1674, 0),
                        ("B05", "base_pullout", 300, 720, 560, 2274, 0),
                        ("W01", "wall_double", 600, 600, 330, 1074, 1600),
                        ("W02", "wall_hood", 600, 600, 330, 1674, 1600),
                        ("W03", "wall_open", 300, 600, 330, 2274, 1600)]
                for local_id, kind, w, h, d, x, z in rows:
                    project["design"]["cabinets"].append({"id": str(uuid4()), "local_id": local_id,
                        "name": kind, "type": kind, "wall_id": wall_id, "width_mm": w, "height_mm": h,
                        "depth_mm": d, "x_mm": x, "y_mm": 0, "z_mm": z, "rotation_deg": 0,
                        "options": {"role": "hob"} if local_id == "B04" else {}})
                project["design"]["settings"]["front_edge"] = 2
                project["design"]["accessories"] = {"worktops": True, "end_scribe_mm": 0}
                response = client.put(route, json={"base_revision": project["revision"], "project": project})
                self.assertEqual(response.status_code, 200, response.text)
                project = response.json()
                response = client.post(route + "/generate", json={"base_revision": project["revision"]})
                self.assertEqual(response.status_code, 200, response.text)
                project = response.json()
                self.assertEqual(project["manufacturing"]["status"], "current")
                before = client.get(route + "/bom").json()
                self.assertEqual(before["totals"]["cabinet_count"], len(rows))
                self.assertGreater(before["totals"]["operation_count"], 0)
                self.assertGreater(before["totals"]["worktop_area_m2"], 0)
                identities = {part["id"]: part["number"] for part in before["parts"]}
                # Simulate the Ruby client's supported parametric edit and push.
                candidate = copy.deepcopy(project)
                candidate["design"]["cabinets"][0]["height_mm"] = 2150
                candidate["design"]["cabinets"][0]["options"] = {"joinery": "screw", "front_edge": 0.5}
                generated = generate_project(candidate)
                response = client.put(route, json={"base_revision": project["revision"],
                                                   "project": candidate, "generated": generated})
                self.assertEqual(response.status_code, 200, response.text)
                reloaded = client.get(route).json()
                self.assertEqual(reloaded["design"]["cabinets"][0]["height_mm"], 2150)
                after = client.get(route + "/bom").json()
                self.assertEqual(after["status"], "current")
                self.assertEqual({part["id"]: part["number"] for part in after["parts"]}, identities)
                recipes = [operation["recipe"] for part in after["parts"] if part["cabinet_id"] == "B01"
                           for operation in part["operations"]]
                self.assertFalse(any("minifix" in recipe for recipe in recipes))
                for key in reloaded["quote"]["rates"]:
                    reloaded["quote"]["rates"][key] = 100
                response = client.put(route, json={"base_revision": reloaded["revision"], "project": reloaded})
                self.assertEqual(response.status_code, 200, response.text)
                quote = client.get(route + "/quote").json()
                self.assertEqual(quote["status"], "estimate")
                self.assertEqual(quote["source_revision"], after["source_revision"])
                self.assertGreater(quote["total"], 0)
                self.assertEqual(client.get(route + "/bom").json(), after)


if __name__ == "__main__":
    unittest.main()
