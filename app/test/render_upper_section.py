"""Dimensioned section from the generated W01 parts; not a SketchUp render."""
from pathlib import Path
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Rectangle

base=Path(__file__).resolve().parent.parent
root=base/'example_export'
job=json.loads((root/'job.json').read_text())
cab=next(c for c in job['cabinets'] if c['id']=='W01')
ps=cab['parts']
cover=next(p for p in ps if p.get('upper_cover'))
floor=next(p for p in ps if p['name']=='Bottom')
pull=next(p for p in ps if p.get('section')=='upper_l_pull')
door=next(p for p in ps if p['category']=='Doors')
door_z=door['o'][2]-door['edges'].get('B',0)
cover_front=cover['o'][1]-cover['edges'].get('B',0)+330
fig,ax=plt.subplots(figsize=(10,6.8),layout='constrained')
fig.patch.set_facecolor('#f8f7f3');ax.set_facecolor('#f8f7f3')
ax.add_patch(Rectangle((-18,door_z),18,door['finished_h'],facecolor='#526e65',edgecolor='#243f38'))
ax.add_patch(Rectangle((0,floor['o'][2]),330,18,facecolor='#d7d2bf',edgecolor='#5a584e'))
ax.add_patch(Rectangle((cover_front,cover['o'][2]),330-cover_front,18,facecolor='#e8d4a5',edgecolor='#655c46'))
poly=[(pull['o'][1]+y+330,pull['o'][2]+z) for y,z in pull['outline']]
ax.add_patch(Polygon(poly,facecolor='#708b9e',edgecolor='#264c65'))
ax.text(69,53.5,'Carcass bottom 18 mm',ha='center',va='center',fontsize=11)
ax.text(74,35.5,'Underside cover 18 mm',ha='center',va='center',fontsize=11)
ax.text(-9,76,'Door\n18 mm',ha='center',va='center',color='white',fontsize=11)
ax.annotate('Fixed L opens down',xy=(15,42),xytext=(59,9),fontsize=12,
            arrowprops=dict(arrowstyle='->',color='#264c65'),color='#264c65')
ax.annotate('',xy=(8,cover['o'][2]+6),xytext=(8,8),arrowprops=dict(arrowstyle='->',lw=2,color='#264c65'))
ax.annotate('',xy=(-30,cover['o'][2]),xytext=(-30,door_z),arrowprops=dict(arrowstyle='<->',color='#354c45'))
ax.text(-33,(cover['o'][2]+door_z)/2,f"{job['settings']['upper_finger_gap']:g} mm clear",rotation=90,ha='right',va='center',fontsize=10)
ax.plot([-29,-18],[door_z,door_z],color='#718079',lw=.8)
ax.plot([-29,cover_front],[cover['o'][2],cover['o'][2]],color='#718079',lw=.8,ls=':')
ax.annotate('',xy=(0,-5),xytext=(cover_front,-5),arrowprops=dict(arrowstyle='<->',color='#354c45'))
ax.text(cover_front/2,-10,f'{cover_front:g} mm recess',ha='center',va='top',fontsize=10)
ax.set_xlim(-45,130);ax.set_ylim(-20,92);ax.set_aspect('equal');ax.axis('off')
fig.suptitle('Regular upper cupboard — underside section',fontsize=18,color='#24453c')
ax.set_title('W01 / W02 only · No finger pull on tall, hood or open units',fontsize=11,pad=15,color='#4d655c')
fig.text(.5,.02,'Generated geometry detail · dimensions in millimetres · native SketchUp check pending',ha='center',fontsize=9,color='#60746a')
fig.savefig(root/'Upper_Underside_Section.png',dpi=160,facecolor=fig.get_facecolor())
print(root/'Upper_Underside_Section.png')
