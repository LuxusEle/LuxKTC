let cabinetList=[];
for(const [target,source] of [['cabJoinery','joinery'],['cabHinge','hinge'],['cabEdge','edge'],['cabFrontEdge','front_edge']]) {
  const select=document.getElementById(target), inherit=document.createElement('option');
  inherit.value='inherit';inherit.textContent='Use job setting';select.appendChild(inherit);
  for(const option of document.querySelector(`[name="${source}"]`).options) select.appendChild(option.cloneNode(true));
}
function loadCabinets(cabinets,settings,version,selected) {
  cabinetList=cabinets;currentConfig=settings;
  document.getElementById('version').textContent='Loaded '+version+' | Visible LINE labels in main DXFs';
  const select=document.getElementById('cabinetId'), old=selected||select.value;select.innerHTML='';
  for(const c of cabinets) { const o=document.createElement('option');o.value=c.id;o.textContent=c.id+' / '+c.name;select.appendChild(o); }
  if(cabinets.some(c=>c.id===old)) select.value=old;
  const run=document.querySelector('.run');run.innerHTML='';
  for(const c of cabinets.filter(c=>c.id.startsWith('B'))) {
    const b=document.createElement('button');b.type='button';b.className='unit';b.style.flex=c.w;
    b.textContent=c.id+' / '+Number(c.w.toFixed(2))+' mm';
    b.onclick=()=>{select.value=c.id;document.getElementById('cabinetEditor').open=true;showCabinet();};run.appendChild(b);
  }
  if(selected) document.getElementById('cabinetEditor').open=true;
  const width=cabinets.filter(c=>c.id.startsWith('B')).reduce((sum,c)=>sum+c.w,48);
  document.querySelector('header h1').textContent='Board kitchen / '+Number(width.toFixed(2))+' mm';
  document.querySelector('header p').textContent='Select a cabinet to edit. Dimensions, drilling, labels and nested sheets update together.';
  showCabinet();
}
function clearEditPreview(){document.getElementById('applyEdit').disabled=true;document.getElementById('editPreview').textContent='';}
function showCabinet(){
  clearEditPreview();const c=cabinetList.find(c=>c.id===document.getElementById('cabinetId').value);if(!c)return;
  const o=(currentConfig.cabinet_overrides||{})[c.id]||{};
  for(const key of ['w','h','d']){
    const field=document.getElementById('cab'+key.toUpperCase());field.step='any';field.value=c[key];
  }
  for(const [key,id] of [['joinery','cabJoinery'],['hinge','cabHinge'],['edge','cabEdge'],['front_edge','cabFrontEdge']])document.getElementById(id).value=o[key]===undefined?'inherit':o[key];
  document.getElementById('cabLocked').value=String(c.width_locked);
  document.getElementById('cabHint').textContent=c.width_anchor ? 'Width follows '+c.width_anchor+'. Changing it also resizes that base unit; preview lists every affected cabinet. Height and depth affect this upper only.' : 'Appliance widths have limits. Base B03-B06 share one worktop height; changing one base height changes all four. Preview lists affected units.';
}
function showEditPreview(text){document.getElementById('editPreview').textContent=text;document.getElementById('applyEdit').disabled=false;}
document.getElementById('cabinetForm').addEventListener('input',clearEditPreview);
document.getElementById('cabinetForm').onsubmit=e=>{
  e.preventDefault();clearEditPreview();
  const changes={w:+document.getElementById('cabW').value,h:+document.getElementById('cabH').value,d:+document.getElementById('cabD').value,locked:document.getElementById('cabLocked').value==='true'};
  for(const [key,id] of [['joinery','cabJoinery'],['hinge','cabHinge'],['edge','cabEdge'],['front_edge','cabFrontEdge']])changes[key]=document.getElementById(id).value;
  sketchup.previewEdit(JSON.stringify({id:document.getElementById('cabinetId').value,changes,fill:document.getElementById('fillMode').value}));
};
function renestCurrent(){const values={};for(const k of ['sheet_w','sheet_h','kerf','margin'])values[k]=document.querySelector(`[name="${k}"]`).value;sketchup.renest(JSON.stringify(values));}
