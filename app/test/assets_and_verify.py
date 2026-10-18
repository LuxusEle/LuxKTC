import pathlib,json,math,fitz,ezdxf
from PIL import Image,ImageDraw,ImageFont
base=pathlib.Path(__file__).resolve().parent.parent
font=ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf' if pathlib.Path('C:/Windows/Fonts/segoeuib.ttf').exists() else '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',20)
for key,letter in {'settings':'AJ','connectors':'C','hinges':'H','doors':'D','faces':'F','boxes':'B','drill':'+','bands':'E','labels':'#','all':'A','home':'K','sheets':'S','export':'DX'}.items():
    im=Image.new('RGBA',(32,32),(0,0,0,0));draw=ImageDraw.Draw(im)
    draw.rounded_rectangle((1,1,30,30),radius=6,fill='#24594c')
    box=draw.textbbox((0,0),letter,font=font);draw.text(((32-box[2])/2,(32-(box[3]-box[1]))/2-box[1]),letter,font=font,fill='#ffffff')
    im.save(base/'assets'/f'{key}.png')
roots=list((base/'test_output').glob('AJ_Board_*'))
if not roots: roots=[base/'example_export']
root=max(roots,key=lambda p:p.stat().st_mtime)
job=json.loads((root/'job.json').read_text());parts=[p for c in job['cabinets'] for p in c['parts'] if p['kind']=='panel']
count=0
for p in parts:
    for face in ['A','B']:
        doc=ezdxf.readfile(root/'parts_dxf'/f"{p['number']}_{face}.dxf");audit=doc.audit()
        assert not audit.errors and not audit.fixes,(p['number'],audit.errors,audit.fixes)
        circles=list(doc.modelspace().query('CIRCLE'));ops=[o for o in p['operations'] if o['face']==face and o['kind']=='drill']
        assert len(circles)==len(ops),(p['number'],face)
        for circle,op in zip(circles,ops):
            x=op['x'] if face=='A' else p['w']-op['x']
            assert math.isclose(circle.dxf.center.x,x,abs_tol=1e-4)
            assert math.isclose(circle.dxf.center.y,op['y'],abs_tol=1e-4)
            assert math.isclose(circle.dxf.radius,op['diameter']/2,abs_tol=1e-4)
        assert all(t.dxf.rotation==0 for t in doc.modelspace().query('TEXT'))
        count+=len(circles)
    for edge in {o['edge'] for o in p['operations'] if o['face']=='EDGE'}:
        doc=ezdxf.readfile(root/'parts_dxf'/f"{p['number']}_EDGE_{edge}.dxf")
        count+=len(list(doc.modelspace().query('CIRCLE')))
assert count==sum(sum(o['kind']=='drill' for o in p['operations']) for p in parts)
sheets=json.loads((root/'nesting.json').read_text());lookup={p['number']:p for p in parts}
for s in sheets:
    for face in ['A','B']:
        doc=ezdxf.readfile(root/'sheets_dxf'/f"{s['id']}_{face}.dxf")
        expected=sum(len([o for o in lookup[a['part']]['operations'] if o['face']==face and o['kind']=='drill']) for a in s['placements'])
        assert len(list(doc.modelspace().query('CIRCLE')))==expected
        assert all(t.dxf.rotation==0 for t in doc.modelspace().query('TEXT'))
def groove_lines(doc,ops,transform):
    lines=[e for e in doc.modelspace().query('LINE') if '_GROOVE_' in e.dxf.layer]
    assert len(lines)==4*len(ops),'Missing groove contours'
    for i,op in enumerate(ops):
        x,y,w,h=op['x'],op['y'],op['w'],op['h']
        points=[(x,y),(x+w,y),(x+w,y+h),(x,y+h)]
        for j in range(4):
            a=transform(*points[j]);b=transform(*points[(j+1)%4]);line=lines[4*i+j]
            assert all(math.isclose(v,t,abs_tol=1e-4) for v,t in zip([line.dxf.start.x,line.dxf.start.y,line.dxf.end.x,line.dxf.end.y],[*a,*b]))
            assert f"_Z{round(op['depth'],2)}".replace('.','p') in line.dxf.layer
    return len(ops)
grooves=0
for p in parts:
    for face in ['A','B']:
        doc=ezdxf.readfile(root/'parts_dxf'/f"{p['number']}_{face}.dxf")
        ops=[o for o in p['operations'] if o['kind']=='groove' and o['face']==face]
        grooves+=groove_lines(doc,ops,lambda x,y:(x if face=='A' else p['w']-x,y))
assert grooves==36
for s in sheets:
    for face in ['A','B']:
        doc=ezdxf.readfile(root/'sheets_dxf'/f"{s['id']}_{face}.dxf")
        expected=[]
        for a in s['placements']:
            p=lookup[a['part']]
            for o in p['operations']:
                if o['kind']!='groove' or o['face']!=face: continue
                x,y,w,h=o['x'],o['y'],o['w'],o['h']
                for xx,yy in [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]:
                    xx,yy=(a['x']+p['h']-yy,a['y']+xx) if a['rotated'] else (a['x']+xx,a['y']+yy)
                    expected.append((s['w']-xx if face=='B' else xx,yy))
        actual=[(e.dxf.start.x,e.dxf.start.y) for e in doc.modelspace().query('LINE') if '_GROOVE_' in e.dxf.layer]
        assert len(actual)==len(expected)
        assert all(math.isclose(a,b,abs_tol=1e-4) for aa,bb in zip(actual,expected) for a,b in zip(aa,bb))
previews=base/'test'/'pdf_previews';previews.mkdir(exist_ok=True)
summary={}
for name in ['BOM','Part_Stickers','Nested_Sheets']:
    doc=fitz.open(root/(name+'.pdf'));thumbs=[]
    for i,page in enumerate(doc):
        pix=page.get_pixmap(matrix=fitz.Matrix(.5,.5),alpha=False)
        img=Image.frombytes('RGB',(pix.width,pix.height),pix.samples)
        thumbs.append(img)
        # No text outside page crop.
        for block in page.get_text('blocks'):
            assert block[0]>=0 and block[1]>=0 and block[2]<=page.rect.width+1 and block[3]<=page.rect.height+1,(name,i,block)
    cols=4;rows=math.ceil(len(thumbs)/cols)
    montage=Image.new('RGB',(cols*310,rows*440),'#bcc9c5');draw=ImageDraw.Draw(montage)
    for i,img in enumerate(thumbs):
        x=(i%cols)*310;y=(i//cols)*440;montage.paste(img,(x+6,y+15));draw.text((x+8,y+2),str(i+1),fill='black')
    montage.save(previews/(name+'_contact.png'))
    doc[0].get_pixmap(matrix=fitz.Matrix(1.5,1.5),alpha=False).save(previews/(name+'_page1.png'))
    summary[name]=len(doc)
result={'passed':True,'drills_matched':count,'grooves_matched':grooves,'machining_operations_matched':count+grooves,'pdf_pages':summary,'export_folder':str(root)}
(base/'test'/'export_results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
