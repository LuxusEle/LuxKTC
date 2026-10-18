"""DXF regression: importable label strokes, unchanged geometry and document integrity."""
from pathlib import Path
from collections import Counter
import json
import math
import ezdxf

base=Path(__file__).resolve().parent.parent
root=base/'example_export'
job=json.loads((root/'job.json').read_text())
parts=[p for c in job['cabinets'] for p in c['parts'] if p['kind']=='panel']

def geometry(e):
    kind=e.dxftype()
    if kind=='LINE': values=(*e.dxf.start,*e.dxf.end)
    elif kind=='CIRCLE': values=(*e.dxf.center,e.dxf.radius)
    else: raise AssertionError(kind)
    assert all(math.isfinite(v) for v in values)
    return (kind,e.dxf.layer,*(round(v,6) for v in values))

count=0
for regular,review in [('parts_dxf','parts'),('sheets_dxf','sheets')]:
    expected_files={p.name for p in (root/'cad_dxf'/review).glob('*.dxf')}
    assert expected_files=={p.name for p in (root/regular).glob('*.dxf')}
    assert expected_files=={p.name for p in (root/'sketchup_dxf'/review).glob('*.dxf')}
    for name in sorted(expected_files):
        src=ezdxf.readfile(root/'cad_dxf'/review/name)
        dst=ezdxf.readfile(root/regular/name)
        assert (root/regular/name).read_bytes()==(root/'sketchup_dxf'/review/name).read_bytes()
        audit=dst.audit()
        assert not audit.errors and not audit.fixes,(name,audit.errors,audit.fixes)
        assert dst.units==4 and dst.dxfversion=='AC1015'
        before=Counter(geometry(e) for e in src.modelspace() if e.dxftype()!='TEXT')
        after=Counter(geometry(e) for e in dst.modelspace() if not e.dxf.layer.startswith('NONCUT_LABEL_'))
        assert before==after,('Changed machining or cut geometry',name)
        assert not list(dst.modelspace().query('TEXT MTEXT'))
        labels=[e for e in dst.modelspace() if e.dxf.layer.startswith('NONCUT_LABEL_')]
        assert labels and all(e.dxftype()=='LINE' and e.dxf.start.distance(e.dxf.end)>0 for e in labels),name
        assert any(e.dxf.layer=='NONCUT_LABEL_PART_NAME' for e in labels),name
        count+=1

for p in parts:
    for face in ('A','B'):
        doc=ezdxf.readfile(root/'cad_dxf'/'parts'/f"{p['number']}_{face}.dxf")
        texts=list(doc.modelspace().query('TEXT'))
        inside=[e for e in texts if 0<=e.dxf.insert.x<=p['w'] and 0<=e.dxf.insert.y<=p['h']]
        for layer,want in [('PART_ID',p['number']),('PART_NAME',p['name'].upper()),('EDGEBAND_LABEL','EB')]:
            got=''.join(e.dxf.text for e in inside if e.dxf.layer==layer).replace(' ','')
            assert want.replace(' ','') in got,(p['number'],face,layer,want,got)
        assert all(e.dxf.rotation==0 for e in texts)
        if job['settings'].get('label_detail')=='full' and any(o['face']==face for o in p['operations']):
            assert any(e.dxf.layer=='MACHINING_LABEL' for e in inside),(p['number'],face)
        if job['settings'].get('label_detail')=='compact':
            assert not any(e.dxf.layer=='MACHINING_LABEL' for e in inside)
            assert all(e.dxf.height<=8 for e in inside)

report={'passed':True,'default_labelled_dxfs':count,'legacy_review_copies_identical':count,'panels_with_inside_names_and_edgebands':len(parts),
        'cut_and_machining_geometry':'identical to CAD set','audit_errors':0,'audit_repairs':0,
        'labels':'Visible LINE labels in main parts_dxf/sheets_dxf; optional TEXT in cad_dxf','native_import':'not_verified'}
(base/'test'/'visible_label_results.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))

# View the actual label strokes; no external text renderer substitutes for them.
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.patches import Circle

door=next(p for p in parts if any(o['recipe']=='review-cup35' for o in p['operations']))
examples=[('P001','B'),(door['number'],'A')]
fig,axes=plt.subplots(1,2,figsize=(10,13),layout='constrained')
for ax,(part_id,face) in zip(axes,examples):
    p=next(p for p in parts if p['number']==part_id)
    doc=ezdxf.readfile(root/'parts_dxf'/f'{part_id}_{face}.dxf')
    groups={}
    for e in doc.modelspace():
        layer=e.dxf.layer
        if layer=='NONCUT_LABEL_NOTES':continue
        color='#064c9a' if layer.startswith('NONCUT_LABEL_') else '#bd4929' if layer.startswith('REVIEW_') else '#218453' if layer.startswith('EDGE') else '#333333'
        if e.dxftype()=='LINE':groups.setdefault(color,[]).append([tuple(e.dxf.start)[:2],tuple(e.dxf.end)[:2]])
        elif e.dxftype()=='CIRCLE':ax.add_patch(Circle(tuple(e.dxf.center)[:2],e.dxf.radius,fill=False,color=color,linewidth=.7))
    for color,lines in groups.items():ax.add_collection(LineCollection(lines,colors=color,linewidths=.65))
    ax.set(xlim=(-20,p['w']+20),ylim=(-20,p['h']+20),aspect='equal',title=f'{part_id} / {p["name"]} / Face {face}')
    ax.axis('off')
out=base.parent.parent/'output'/'label_checks';out.mkdir(parents=True,exist_ok=True)
fig.savefig(out/'visible_labels.png',dpi=160,facecolor='white')
