"""Strict document and machining checks: tolerant reader repairs are failures."""
from pathlib import Path
from collections import Counter
import json
import math
import ezdxf

base=Path(__file__).resolve().parent.parent
root=base/'example_export'
job=json.loads((root/'job.json').read_text())
panels=[p for c in job['cabinets'] for p in c['parts'] if p['kind']=='panel']
lookup={p['number']:p for p in panels}
sheets=json.loads((root/'nesting.json').read_text())

def signature(values):
    return tuple(round(float(v),4) if isinstance(v,(int,float)) else v for v in values)

def verify(path,expected_drills,expected_grooves):
    doc=ezdxf.readfile(path)
    audit=doc.audit()
    assert not audit.errors and not audit.fixes,(path,audit.errors,audit.fixes)
    assert doc.dxfversion=='AC1015' and doc.units==4,path
    owner=doc.modelspace().block_record_handle
    entities=list(doc.modelspace())
    assert all(e.dxf.owner==owner and e.dxf.handle for e in entities),path
    assert all(doc.layers.has_entry(e.dxf.layer) for e in entities),path
    actual_drills=[signature((e.dxf.center.x,e.dxf.center.y,e.dxf.radius)) for e in entities if e.dxftype()=='CIRCLE']
    actual_grooves=[signature((e.dxf.start.x,e.dxf.start.y,e.dxf.end.x,e.dxf.end.y)) for e in entities if e.dxftype()=='LINE' and '_GROOVE_' in e.dxf.layer]
    assert Counter(actual_drills)==Counter(map(signature,expected_drills)),path
    assert Counter(actual_grooves)==Counter(map(signature,expected_grooves)),path
    assert all(e.dxf.rotation==0 for e in entities if e.dxftype()=='TEXT'),path
    lines=path.read_text().splitlines()
    tags=[(int(lines[i]),lines[i+1].strip()) for i in range(0,len(lines),2)]
    sections=[tags[i+1][1] for i,t in enumerate(tags) if t==(0,'SECTION')]
    assert all(s in sections for s in ('HEADER','TABLES','BLOCKS','ENTITIES','OBJECTS')),path
    start=next(i+2 for i,t in enumerate(tags) if t==(0,'SECTION') and tags[i+1]==(2,'ENTITIES'))
    end=tags.index((0,'ENDSEC'),start)
    records=[]
    for t in tags[start:end]:
        if t[0]==0: records.append([])
        records[-1].append(t)
    handles=[]
    for record in records:
        kind=record[0][1]
        assert any(c==5 for c,v in record) and (330,owner) in record,path
        assert (100,'AcDbEntity') in record,path
        assert (100,{'LINE':'AcDbLine','CIRCLE':'AcDbCircle','TEXT':'AcDbText'}[kind]) in record,path
        handles.append(next(v for c,v in record if c==5))
    assert len(handles)==len(set(handles)),path
    return len(actual_drills),len(actual_grooves)//4

def expected(p,face,transform):
    drills=[];grooves=[]
    for o in p['operations']:
        if o['face']!=face:continue
        if o['kind']=='drill':drills.append((*transform(o['x'],o['y']),o['diameter']/2))
        else:
            x,y,w,h=o['x'],o['y'],o['w'],o['h']
            points=[(x,y),(x+w,y),(x+w,y+h),(x,y+h)]
            grooves.extend((*transform(*a),*transform(*points[(i+1)%4])) for i,a in enumerate(points))
    return drills,grooves

files=0;drills=0;grooves=0
for p in panels:
    for face in ('A','B'):
        trans=lambda x,y:(x if face=='A' else p['w']-x,y)
        d,g=verify(root/'parts_dxf'/f"{p['number']}_{face}.dxf",*expected(p,face,trans))
        files+=1;drills+=d;grooves+=g
    for edge in {o['edge'] for o in p['operations'] if o['face']=='EDGE'}:
        ops=[o for o in p['operations'] if o['face']=='EDGE' and o['edge']==edge]
        d,g=verify(root/'parts_dxf'/f"{p['number']}_EDGE_{edge}.dxf",[(o['y'],p['t']/2,o['diameter']/2) for o in ops],[])
        files+=1;drills+=d
for s in sheets:
    for face in ('A','B'):
        ds=[];gs=[]
        for a in s['placements']:
            p=lookup[a['part']]
            def trans(x,y):
                x,y=(a['x']+p['h']-y,a['y']+x) if a['rotated'] else (a['x']+x,a['y']+y)
                return (s['w']-x if face=='B' else x,y)
            d,g=expected(p,face,trans);ds.extend(d);gs.extend(g)
        verify(root/'sheets_dxf'/f"{s['id']}_{face}.dxf",ds,gs);files+=1
calibration=base.parent/'DXF_Import_Test'/'01_Calibration_100mm.dxf'
verify(calibration,[(50,50,10)],[])
assert drills==886 and grooves==36
report={'passed':True,'files_checked':files+1,'drills_matched':drills,'grooves_matched':grooves,'audit_errors':0,'audit_repairs':0,'format':'AC1015 / complete R2000','units':'mm','native_sketchup_import':'not_verified','checks':['A/B/EDGE machining coordinates','Rotated and mirrored nesting coordinates','Entity handles, owners and subclass markers','Complete document sections and layer references','Unrotated TEXT labels','100 mm calibration file']}
(base/'test'/'dxf_compatibility_results.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
