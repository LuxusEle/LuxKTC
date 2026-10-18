"""Inspect saved text/CSV outputs only; no Ruby, native DLLs or app execution."""
from pathlib import Path
from collections import Counter, defaultdict
import csv
import json
import re

base = Path(__file__).resolve().parent.parent
root = base / 'example_export'

def records(path):
    lines = path.read_text(encoding='ascii').splitlines()
    assert len(lines) % 2 == 0, f'Odd DXF stream: {path}'
    rows, row = [], []
    for i in range(0, len(lines), 2):
        code, value = int(lines[i]), lines[i + 1]
        if code == 0 and row:
            rows.append(row)
            row = []
        row.append((code, value))
    if row:
        rows.append(row)
    return rows

def geometry(rows):
    active, poly, output = False, None, []
    for row in rows:
        r = dict(row)
        kind, layer = r.get(0), r.get(8)
        if kind == 'SECTION':
            active = r.get(2) == 'ENTITIES'
            continue
        if kind == 'ENDSEC':
            active = False
            continue
        if not active:
            continue
        def numbers(*codes):
            return tuple(round(float(r[c]), 6) for c in codes)
        if kind == 'LINE':
            output.append((layer, kind, *numbers(10, 20, 11, 21)))
        elif kind == 'CIRCLE':
            output.append((layer, kind, *numbers(10, 20, 40)))
        elif kind == 'POLYLINE':
            assert poly is None and r[70] == '1' and r[66] == '1'
            poly = (layer, [])
        elif kind == 'VERTEX':
            assert poly is not None and poly[0] == layer
            poly[1].append(numbers(10, 20))
        elif kind == 'SEQEND':
            assert poly is not None and len(poly[1]) >= 3
            points = poly[1]
            for a, b in zip(points, points[1:] + points[:1]):
                output.append((poly[0], 'LINE', *a, *b))
            poly = None
        else:
            raise AssertionError(f'Unexpected entity: {kind}')
    assert poly is None
    return Counter(output)

count = 0
all_layers = set()
for kind in ('parts', 'sheets'):
    for path in sorted((root / 'aspire_dxf' / kind).glob('*.dxf')):
        rows = records(path)
        assert any((1, 'AC1009') in row for row in rows)
        assert not any(code in (100, 330, 390) for row in rows for code, _ in row)
        layers = [dict(row)[2] for row in rows if dict(row).get(0) == 'LAYER']
        assert len(layers) == len(set(layers))
        assert all(re.fullmatch(r'[A-Za-z0-9_]{1,31}', name) for name in layers)
        used = {dict(row)[8] for row in rows if 8 in dict(row)}
        assert used <= set(layers)
        assert any(name.startswith('NONCUT_LABEL_PART') for name in used)
        assert all(re.match(r'(CUT_|REVIEW_(A|B|EDGE)_(DRILL|POCKET|GROOVE)_|NONCUT_)', name) for name in used)
        reference = root / (kind + '_dxf') / path.name
        assert geometry(rows) == geometry(records(reference)), f'Geometry differs: {path}'
        all_layers.update(used)
        count += 1
assert count == 436, count

pocket_recipes = {'review-cup35', 'review-minifix-cam', 'review-rafix20-housing', 'review-screw-recess'}
processes, layer_types = Counter(), defaultdict(set)
with (root / 'machining.csv').open(newline='', encoding='utf-8') as stream:
    for row in csv.DictReader(stream):
        expected = 'GROOVE' if row['Kind'] == 'groove' else 'POCKET' if row['Recipe'] in pocket_recipes else 'DRILL'
        assert row['Process'] == expected
        layer = row['DXF_Layer']
        assert layer in all_layers and ('_' + expected + '_') in layer
        assert layer.startswith('REVIEW_' + row['Face'] + '_')
        layer_types[layer].add(expected)
        processes[expected] += 1
assert sum(processes.values()) == 922
assert all(len(types) == 1 for types in layer_types.values())
report = {
    'passed': True,
    'version': json.loads((root / 'job.json').read_text())['version'],
    'scope': 'Static inspection of saved DXF and CSV files; no app or Ruby execution',
    'aspire_files': count, 'labelled_files': count,
    'geometry': 'All R12 contours, circles, bands and labels match R2000 counterparts',
    'processes': dict(processes), 'layer_processes_unique': True,
    'native_aspire_import': 'not_verified',
    'extended_ruby_test': 'blocked_by_automatic_approval_review_due_to_unexpected_external_telemetry'
}
(base / 'test' / 'aspire_static_results.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
