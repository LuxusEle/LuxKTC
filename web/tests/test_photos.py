from __future__ import annotations

import base64
import io
import tempfile
import unittest
from unittest.mock import patch

import cv2
import numpy as np
from fastapi.testclient import TestClient
from PIL import Image

from server.main import create_app
from server.photos import decode_image, rectify_image


class RectificationTests(unittest.TestCase):
    def test_homography_maps_corners_and_preserves_long_wall_aspect(self):
        image = Image.new("RGB", (400, 250), "white")
        quad = [[30, 15], [380, 35], [350, 230], [20, 215]]
        corrected, matrix = rectify_image(image, quad, 9000, 2500)
        self.assertEqual(corrected.width, 1800)
        self.assertLess(abs(corrected.width / corrected.height - 9000 / 2500), 0.01)
        mapped = cv2.perspectiveTransform(np.float64(quad).reshape(-1, 1, 2), np.array(matrix)).reshape(-1, 2)
        np.testing.assert_allclose(mapped, [[0, 0], [corrected.width - 1, 0],
                                           [corrected.width - 1, corrected.height - 1], [0, corrected.height - 1]], atol=1e-5)

    def test_invalid_planes_are_rejected_instead_of_guessing(self):
        image = Image.new("RGB", (300, 200))
        bad = [
            [[0, 0], [200, 180], [200, 0], [0, 180]],
            [[0, 0], [0, 0], [200, 180], [0, 180]],
            [[0, 0], [1, 0], [2, 0], [3, 0]],
            [[-1, 0], [200, 0], [200, 180], [0, 180]],
            [[0, 0], [float("nan"), 0], [200, 180], [0, 180]],
        ]
        for quad in bad:
            with self.subTest(quad=quad), self.assertRaises(ValueError):
                rectify_image(image, quad, 3000, 2400)

    def test_exif_orientation_uses_same_frame_as_displayed_photo(self):
        image = Image.new("RGB", (100, 200), "white")
        exif = image.getexif()
        exif[274] = 6
        data = io.BytesIO()
        image.save(data, "JPEG", exif=exif)
        oriented, mime = decode_image(data.getvalue())
        self.assertEqual(oriented.size, (200, 100))
        self.assertEqual(mime, "image/jpeg")


class PhotoApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.app = create_app(self.temp.name)
        self.client = TestClient(self.app, base_url="http://127.0.0.1:8740")
        self.project = self.client.post("/api/projects", json={"template": "10ft"}).json()
        self.route = "/api/projects/" + self.project["id"]
        self.project["room"]["walls"][0]["measurements_confirmed"] = True
        response = self.client.put(self.route, json={"base_revision": 1, "project": self.project})
        self.assertEqual(response.status_code, 200, response.text)
        self.project = response.json()
        self.wall_id = self.project["room"]["walls"][0]["id"]
        image = Image.new("RGB", (400, 250), "#e1d8c6")
        raw = io.BytesIO()
        image.save(raw, "PNG")
        self.raw = raw.getvalue()
        response = self.client.post(self.route + "/photos", json={"base_revision": self.project["revision"],
                                   "wall_id": self.wall_id, "filename": "wall.png",
                                   "data_base64": base64.b64encode(self.raw).decode()})
        self.assertEqual(response.status_code, 200, response.text)
        self.project = response.json()["project"]

    def tearDown(self):
        self.client.close()
        self.temp.cleanup()

    def test_immutable_original_and_separate_measured_texture(self):
        wall = self.project["room"]["walls"][0]
        self.assertEqual(self.client.get("/api/assets/" + wall["photo_asset_id"]).content, self.raw)
        response = self.client.post(self.route + "/rectify", json={"base_revision": self.project["revision"],
                                   "wall_id": self.wall_id, "quad": [[30, 15], [380, 35], [350, 230], [20, 215]],
                                   "width_mm": wall["width_mm"], "height_mm": wall["height_mm"]})
        self.assertEqual(response.status_code, 200, response.text)
        project = response.json()
        corrected = project["room"]["walls"][0]
        self.assertNotEqual(corrected["photo_asset_id"], corrected["rectified_asset_id"])
        self.assertNotEqual(corrected["annotated_asset_id"], corrected["rectified_asset_id"])
        self.assertEqual(corrected["rectification"]["measurement_source"], "user_confirmed")
        self.assertEqual(self.client.get("/api/assets/" + wall["photo_asset_id"]).content, self.raw)
        project["room"]["walls"][0]["width_mm"] += 10
        updated = self.client.put(self.route, json={"base_revision": project["revision"], "project": project})
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertIsNone(updated.json()["room"]["walls"][0].get("rectified_asset_id"))

    def test_ai_proposals_are_cached_and_do_not_become_confirmed_measurements(self):
        proposal = {"wall_quad": [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9], [0.1, 0.9]],
                    "detections": [{"type": "window", "label": "Window", "bbox": [0.2, 0.2, 0.2, 0.3],
                                    "confidence": 0.8, "needs_measurement": True}],
                    "questions": ["Measure the window width and sill height."], "notes": []}
        before = self.project["room"]["walls"][0]
        with patch("server.photos.analyze_wall", return_value=proposal) as analyze:
            response = self.client.post(self.route + "/analyze", json={"base_revision": self.project["revision"], "wall_id": self.wall_id})
            self.assertEqual(response.status_code, 200, response.text)
            saved = response.json()["project"]
            after = saved["room"]["walls"][0]
            self.assertEqual(after["width_mm"], before["width_mm"])
            self.assertEqual(after["openings"], before["openings"])
            self.assertIsNone(after["photo_quad"])
            cached = self.client.post(self.route + "/analyze", json={"base_revision": saved["revision"], "wall_id": self.wall_id})
            self.assertEqual(cached.status_code, 200, cached.text)
            self.assertTrue(cached.json()["cached"])
            self.assertEqual(analyze.call_count, 1)

    def test_conflict_cannot_replace_photo_and_cross_project_assets_are_refused(self):
        revision = self.project["revision"]
        response = self.client.post(self.route + "/photos", json={"base_revision": revision - 1,
                                   "wall_id": self.wall_id, "filename": "wall.png",
                                   "data_base64": base64.b64encode(self.raw).decode()})
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.client.get(self.route).json()["revision"], revision)
        second = self.client.post("/api/projects", json={"template": "10ft"}).json()
        second["room"]["walls"][0]["measurements_confirmed"] = True
        second["room"]["walls"][0]["photo_asset_id"] = self.project["room"]["walls"][0]["photo_asset_id"]
        response = self.client.put("/api/projects/" + second["id"], json={"base_revision": second["revision"], "project": second})
        second = response.json()
        response = self.client.post("/api/projects/" + second["id"] + "/rectify", json={
            "base_revision": second["revision"], "wall_id": second["room"]["walls"][0]["id"],
            "quad": [[0, 0], [399, 0], [399, 249], [0, 249]], "width_mm": 3048, "height_mm": 2600})
        self.assertEqual(response.status_code, 404)


if __name__ == "__main__":
    unittest.main()
