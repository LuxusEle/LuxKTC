from __future__ import annotations

import copy
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from server.bom import build_bom, build_quote, print_html
from server.models import ValidationError
from server.store import ProjectNotFound, ProjectStore, RevisionConflict


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = ProjectStore(Path(self.temp.name) / "projects.sqlite3")
        self.project = self.store.create("Kitchen <script>test</script>", template="10ft")

    def tearDown(self):
        self.temp.cleanup()

    def test_template_contains_real_parts_and_worktop_without_extra_cabinet(self):
        b = build_bom(self.project)
        self.assertEqual(b["status"], "current")
        self.assertEqual(b["totals"]["cabinet_count"], 10)
        self.assertEqual(b["totals"]["part_count"], 153)
        self.assertGreater(b["totals"]["worktop_area_m2"], 0)
        self.assertTrue(any(op["kind"] == "groove" for p in b["parts"] for op in p["operations"]))
        self.assertEqual(build_quote(self.project)["status"], "unpriced")
        self.assertIn("worktop_per_m2", build_quote(self.project)["missing_rates"])
        self.assertNotIn("<script>", print_html(self.project))

    def test_quote_only_edit_preserves_manufacturing_design_edit_marks_stale(self):
        p = copy.deepcopy(self.project)
        p["name"] = "Renamed project"
        p["quote"]["rates"]["board_per_m2"] = 3000
        p = self.store.update(p["id"], 1, p)
        self.assertEqual(p["manufacturing"]["status"], "current")
        self.assertEqual(p["manufacturing"]["source_revision"], 1)
        p["design"]["cabinets"][0]["width_mm"] = 500
        p["manufacturing"]["status"] = "current"  # client cannot forge state
        p = self.store.update(p["id"], 2, p)
        self.assertEqual(build_bom(p)["status"], "stale")
        self.assertEqual(build_quote(p)["manufacturing_status"], "stale")

    def test_changed_settings_reject_old_generated_snapshot_atomically(self):
        p = copy.deepcopy(self.project)
        p["design"]["settings"]["edge"] = 2
        with self.assertRaises(ValidationError):
            self.store.update(p["id"], 1, p, {"job": p["manufacturing"]["job"], "nesting": p["manufacturing"]["nesting"]})
        self.assertEqual(self.store.get(p["id"])["revision"], 1)
        self.assertEqual(len(self.store.history(p["id"])), 1)

    def test_generated_manifest_covers_role_style_accessories_and_is_required(self):
        for change in ("role", "style", "accessories", "missing_manifest"):
            with self.subTest(change=change):
                p = copy.deepcopy(self.project)
                generated = copy.deepcopy(self.project["manufacturing"])
                if change == "role":
                    p["design"]["cabinets"][4]["options"]["role"] = "standard"
                elif change == "style":
                    p["design"]["style"] = "handled"
                elif change == "accessories":
                    p["design"]["accessories"]["worktops"] = False
                else:
                    del generated["job"]["input_manifest"]
                expected_error = "supports modern_gola" if change == "style" else "manifest"
                with self.assertRaisesRegex(ValidationError, expected_error):
                    self.store.update(p["id"], 1, p, generated)
                self.assertEqual(self.store.get(p["id"])["revision"], 1)
        unchanged = copy.deepcopy(self.project["manufacturing"])
        saved = self.store.update(self.project["id"], 1, self.project, unchanged)
        self.assertEqual(saved["manufacturing"]["status"], "current")
        self.assertEqual(saved["revision"], 2)

    def test_bad_generated_cabinet_and_nesting_are_rejected(self):
        for change in ("width", "id", "nesting"):
            with self.subTest(change=change):
                generated = copy.deepcopy(self.project["manufacturing"])
                if change == "width":
                    generated["job"]["cabinets"][0]["w"] += 1
                elif change == "id":
                    generated["job"]["cabinets"][0]["id"] = "B99"
                else:
                    generated["nesting"][0]["placements"].pop()
                with self.assertRaises(ValidationError):
                    self.store.update(self.project["id"], 1, self.project, generated)

    def test_concurrent_edits_exactly_one_wins_and_history_is_complete(self):
        barrier = threading.Barrier(2)
        def edit(name):
            p = copy.deepcopy(self.project)
            p["name"] = name
            barrier.wait()
            try:
                return self.store.update(p["id"], 1, p)["revision"]
            except RevisionConflict as exc:
                return ("conflict", exc.current_revision)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(edit, ("Web edit", "SketchUp edit")))
        self.assertEqual(results.count(2), 1)
        self.assertIn(("conflict", 2), results)
        self.assertEqual([h["revision"] for h in self.store.history(self.project["id"])], [1, 2])

    def test_delete_requires_revision_and_leaves_tombstone(self):
        with self.assertRaises(RevisionConflict):
            self.store.delete(self.project["id"], 2)
        self.store.delete(self.project["id"], 1)
        self.assertEqual(self.store.list(), [])
        with self.assertRaises(ProjectNotFound):
            self.store.get(self.project["id"])
        self.assertTrue(self.store.history(self.project["id"])[-1]["deleted"])

    def test_invalid_geometry_never_advances_revision(self):
        for number in (-1, float("nan"), float("inf"), "600", True):
            with self.subTest(number=number):
                p = copy.deepcopy(self.project)
                p["design"]["cabinets"][0]["width_mm"] = number
                with self.assertRaises(ValidationError):
                    self.store.update(p["id"], 1, p)
        self.assertEqual(self.store.get(self.project["id"])["revision"], 1)

    def test_measurement_change_invalidates_old_wall_texture(self):
        p = copy.deepcopy(self.project)
        wall = p["room"]["walls"][0]
        wall.update(photo_asset_id="original", photo_quad=[[0, 0], [100, 0], [100, 100], [0, 100]], rectified_asset_id="texture", annotated_asset_id="labelled")
        wall["rectification"] = {"source_asset_id": "original", "quad": wall["photo_quad"], "width_mm": wall["width_mm"], "height_mm": wall["height_mm"]}
        p = self.store.update(p["id"], 1, p)
        p["room"]["walls"][0]["width_mm"] = 3200
        p = self.store.update(p["id"], 2, p)
        self.assertIsNone(p["room"]["walls"][0]["rectified_asset_id"])
        self.assertIsNone(p["room"]["walls"][0]["annotated_asset_id"])
        self.assertIsNone(p["room"]["walls"][0]["rectification"])


if __name__ == "__main__":
    unittest.main()
