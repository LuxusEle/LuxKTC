from pathlib import Path
import json,math,ezdxf
from collections import Counter
base=Path(__file__).resolve().parent.parent
count=0
for folder in (base/'test_output'/'connector_checks').iterdir():
    for p in json.loads((folder/'parts.json').read_text()):
        setups=['A','B']+['EDGE_'+s for s in sorted({o['edge'] for o in p['operations'] if o['face']=='EDGE'})]
        for setup in setups:
            doc=ezdxf.readfile(folder/(p['number']+'_'+setup+'.dxf'))
            audit=doc.audit();assert not audit.errors and not audit.fixes
            assert any(e.dxftype()=='LINE' and e.dxf.layer.startswith('NONCUT_LABEL_') for e in doc.modelspace())
            actual=[(e.dxf.center.x,e.dxf.center.y,e.dxf.radius) for e in doc.modelspace().query('CIRCLE')]
            ops=[o for o in p['operations'] if o['kind']=='drill' and (setup=='EDGE_'+str(o.get('edge')) if setup.startswith('EDGE') else o['face']==setup)]
            expected=[]
            for o in ops:
                x,y=(o['y'],p['t']/2) if setup.startswith('EDGE') else (p['w']-o['x'] if setup=='B' else o['x'],o['y'])
                expected.append((x,y,o['diameter']/2))
                layer=f"_Z{round(o['depth'],2)}".replace('.','p')
                assert any(layer in e.dxf.layer for e in doc.modelspace().query('CIRCLE'))
            rounded=lambda points:Counter(tuple(round(v,4) for v in p) for p in points)
            assert rounded(actual)==rounded(expected),(folder.name,p['number'],setup)
            count+=1
result={'passed':True,'connector_recipes':6,'dxf_setups_checked':count,'checks':['Visible line labels','Exact face/edge centers and radii','B-face mirroring','Depth layers','No DXF errors or repairs']}
(base/'test'/'connector_dxf_results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
