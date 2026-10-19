"""BOM and indicative prices derived only from stored Ruby part snapshots."""
from __future__ import annotations

import csv
import html
import io
from collections import Counter, defaultdict

from .models import RATE_KEYS


def build_bom(project):
    m = project["manufacturing"]
    job = m.get("job")
    result = {"status": m["status"], "source_revision": m.get("source_revision"), "parts": [], "hardware": [], "totals": {"cabinet_count": 0, "part_count": 0, "panel_count": 0, "panel_area_m2": 0, "board_area_m2": 0, "front_area_m2": 0, "back_area_m2": 0, "worktop_area_m2": 0, "profile_length_m": 0, "band_length_m": 0, "hardware_count": 0, "operation_count": 0}}
    if not job:
        return result
    totals = result["totals"]
    hardware = defaultdict(float)
    for cabinet in job.get("cabinets", []):
        if cabinet.get("type") and cabinet.get("type") != "room" and not cabinet.get("accessory"):
            totals["cabinet_count"] += 1
        for p in cabinet.get("parts", []):
            row = {key: p.get(key) for key in ("id", "number", "name", "cabinet_id", "cabinet_name", "kind", "category", "material", "w", "h", "t", "finished_w", "finished_h", "edges", "operations")}
            row["finished_w"] = p.get("finished_w", p["w"])
            row["finished_h"] = p.get("finished_h", p["h"])
            row["edges"] = p.get("edges", {})
            row["operations"] = p.get("operations", [])
            row["area_m2"] = round(p["w"] * p["h"] / 1e6, 8) if p.get("kind") == "panel" else 0
            row["band_length_m"] = round(sum((row["finished_h"] if side in ("L", "R") else row["finished_w"]) / 1000 for side, thickness in row["edges"].items() if thickness > 0), 6)
            result["parts"].append(row)
            totals["part_count"] += 1
            totals["operation_count"] += len(row["operations"])
            totals["band_length_m"] += row["band_length_m"]
            if p.get("kind") == "profile":
                # The Ruby scaffold's profile t is its extrusion length.
                totals["profile_length_m"] += p["t"] / 1000
            if p.get("kind") == "panel":
                totals["panel_count"] += 1
                totals["panel_area_m2"] += row["area_m2"]
                material = str(p.get("material", "")).lower()
                key = "front_area_m2" if material == "front" else "back_area_m2" if material == "back" else "worktop_area_m2" if material == "worktop" else "board_area_m2"
                totals[key] += row["area_m2"]
        for h in cabinet.get("hardware", []):
            hardware[(h.get("name", "Hardware"), h.get("recipe", ""))] += h.get("quantity", 1)
    result["hardware"] = [{"name": name, "recipe": recipe, "quantity": count} for (name, recipe), count in sorted(hardware.items())]
    totals["hardware_count"] = sum(row["quantity"] for row in result["hardware"])
    for key, value in list(totals.items()):
        if isinstance(value, float):
            totals[key] = round(value, 6)
    return result


def build_quote(project):
    bom = build_bom(project)
    q = project["quote"]
    rates = q["rates"]
    mapping = [("board_per_m2", "Carcass panels", "board_area_m2", "m²"), ("front_per_m2", "Front panels", "front_area_m2", "m²"), ("back_per_m2", "Back panels", "back_area_m2", "m²"), ("worktop_per_m2", "Worktops", "worktop_area_m2", "m²"), ("profile_per_m", "Gola / finger-pull profiles", "profile_length_m", "m"), ("band_per_m", "Edgebanding", "band_length_m", "m"), ("hardware_each", "Hardware (aggregate allowance)", "hardware_count", "each")]
    lines, missing = [], []
    for key, label, quantity_key, unit in mapping:
        quantity = bom["totals"][quantity_key]
        rate = rates.get(key, 0)
        lines.append({"key": key, "description": label, "quantity": quantity, "unit": unit, "rate": rate, "amount": round(quantity * rate, 2)})
        if quantity > 0 and rate == 0:
            missing.append(key)
    subtotal = round(sum(line["amount"] for line in lines) + q["labour"], 2)
    markup = round(subtotal * q["markup_pct"] / 100, 2)
    tax = round((subtotal + markup) * q["tax_pct"] / 100, 2)
    notices = ["Indicative cost estimate: net cut-part areas, excluding sheet yield/waste and delivery. Hardware uses an aggregate per-item allowance."]
    if bom["status"] != "current":
        notices.append("Geometry needs regeneration. These quantities are stale or unavailable.")
    if missing:
        notices.append("Unpriced: enter all missing material and hardware rates before using this estimate.")
    if not bom["parts"]:
        notices.append("No generated parts are available.")
    return {"project_id": project["id"], "revision": project["revision"], "status": "unpriced" if missing or not bom["parts"] else "stale" if bom["status"] != "current" else "estimate", "manufacturing_status": bom["status"], "source_revision": bom["source_revision"], "currency": q["currency"], "lines": lines, "missing_rates": missing, "labour": q["labour"], "subtotal": subtotal, "markup_pct": q["markup_pct"], "markup": markup, "tax_pct": q["tax_pct"], "tax": tax, "total": round(subtotal + markup + tax, 2), "notices": notices}


def _csv(rows):
    out = io.StringIO(newline="")
    writer = csv.writer(out)
    # Keep user-editable names from becoming spreadsheet formulas.
    for row in rows:
        writer.writerow(["'" + cell if isinstance(cell, str) and cell.startswith(("=", "+", "-", "@", "\t", "\r")) else cell for cell in row])
    return "\ufeff" + out.getvalue()


def bom_csv(project):
    b = build_bom(project)
    rows = [["LuxKTC BOM", project["name"]], ["Manufacturing status", b["status"], "Source revision", b["source_revision"]], ["Part", "Cabinet", "Name", "Material", "Cut W mm", "Cut H mm", "Thickness mm", "Finished W mm", "Finished H mm", "Band L mm", "Band R mm", "Band B mm", "Band T mm", "Machining operations"]]
    for p in b["parts"]:
        rows.append([p["number"], p["cabinet_id"], p["name"], p["material"], p["w"], p["h"], p["t"], p["finished_w"], p["finished_h"], *[p["edges"].get(side, 0) for side in "LRBT"], len(p["operations"])])
    rows += [[], ["Hardware", "Recipe", "Quantity"]]
    rows += [[p["name"], p["recipe"], p["quantity"]] for p in b["hardware"]]
    return _csv(rows)


def quote_csv(project):
    q = build_quote(project)
    rows = [["LuxKTC indicative quote", project["name"]], ["Status", q["status"], "Geometry", q["manufacturing_status"]], ["Currency", q["currency"]], ["Description", "Quantity", "Unit", "Rate", "Amount"]]
    rows += [[x["description"], x["quantity"], x["unit"], x["rate"], x["amount"]] for x in q["lines"]]
    rows += [["Labour", "", "", "", q["labour"]], ["Markup", "", "%", q["markup_pct"], q["markup"]], ["Tax", "", "%", q["tax_pct"], q["tax"]], ["Total", "", "", q["currency"], q["total"]], ["Missing rates", ", ".join(q["missing_rates"])]]
    rows += [[n] for n in q["notices"]]
    return _csv(rows)


def print_html(project):
    b, q = build_bom(project), build_quote(project)
    e = lambda value: html.escape(str(value if value is not None else ""), quote=True)
    parts = "".join("<tr>" + "".join(f"<td>{e(v)}</td>" for v in [p["number"], p["cabinet_id"], p["name"], p["material"], f'{p["w"]:g} × {p["h"]:g} × {p["t"]:g}', ", ".join(f"{s}:{n:g}" for s, n in p["edges"].items()), len(p["operations"])]) + "</tr>" for p in b["parts"])
    lines = "".join(f'<tr><td>{e(x["description"])}</td><td>{e(x["quantity"])}</td><td>{e(x["unit"])}</td><td>{e(x["rate"])}</td><td>{e(x["amount"])}</td></tr>' for x in q["lines"])
    notices = "".join(f"<p>{e(n)}</p>" for n in q["notices"])
    return f'''<!doctype html><html lang="en"><meta charset="utf-8"><title>{e(project['name'])} — LuxKTC</title><style>body{{font:13px system-ui;margin:30px;color:#172e33}}table{{border-collapse:collapse;width:100%;margin:16px 0}}th,td{{text-align:left;padding:6px;border-bottom:1px solid #ccd8d8}}th{{background:#edf3f2}}h1{{font-size:24px}}h2{{margin-top:28px}}tr{{break-inside:avoid}}@media print{{button{{display:none}}body{{margin:0}}thead{{display:table-header-group}}}}</style><body><button onclick="print()">Print / save PDF</button><h1>{e(project['name'])}</h1><p>{e(project['client'])} · Revision {project['revision']} · {e(project['updated_at'])}</p><p>Manufacturing: <b>{e(b['status'])}</b> · Part source revision {e(b['source_revision'])}</p><h2>Indicative quote — {e(q['status'])}</h2>{notices}<table><thead><tr><th>Description</th><th>Quantity</th><th>Unit</th><th>Rate</th><th>Amount</th></tr></thead><tbody>{lines}</tbody></table><p>Labour: {e(q['labour'])} · Markup: {e(q['markup'])} · Tax: {e(q['tax'])}</p><p><b>Total: {e(q['currency'])} {q['total']:,.2f}</b></p><h2>Bill of materials</h2><p>{b['totals']['cabinet_count']} cabinets · {b['totals']['part_count']} parts · all dimensions in mm. Band sides use the part's local L/R/B/T frame.</p><table><thead><tr><th>Part</th><th>Cabinet</th><th>Name</th><th>Material</th><th>Cut size mm</th><th>Bands mm</th><th>Operations</th></tr></thead><tbody>{parts}</tbody></table></body></html>'''
