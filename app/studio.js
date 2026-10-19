'use strict';

// HtmlDialog is a native editor. Ruby alone owns HTTP and SketchUp model calls.
(() => {
  const state={project:null,latest:null,projects:[],catalog:{cabinets:[],connectors:[],hinges:[]},bom:null,quote:null,server:'',busy:false,dirty:false,remote_revision:null,visibility:{},tab:'projects',wallId:null,formDirty:false,message:'',error:null,pending:null,baseModelSerial:0,latestModelSerial:0};
  const $=(selector,root=document)=>root.querySelector(selector);
  const escape=value=>String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const copy=value=>value==null?value:JSON.parse(JSON.stringify(value));
  const number=value=>Number.isFinite(Number(value))?Number(value):0;
  const mm=value=>number(value).toLocaleString(undefined,{maximumFractionDigits:1});
  const money=value=>number(value).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2});
  const title=value=>String(value||'').replaceAll('_',' ').replace(/\b\w/g,c=>c.toUpperCase());
  const locked=()=>state.busy||Boolean(state.pending);
  const wall=()=>state.project?.room.walls.find(w=>w.id===state.wallId)||state.project?.room.walls[0];
  const uuid=()=>{
    if(window.crypto?.randomUUID)return window.crypto.randomUUID();
    const bytes=new Uint8Array(16);
    if(window.crypto?.getRandomValues)window.crypto.getRandomValues(bytes);else for(let i=0;i<16;i++)bytes[i]=Math.floor(Math.random()*256);
    bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
    const hex=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
    return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
  };
  const connector=value=>({minifix:'Minifix',minifix_dowel:'Minifix + dowel',rafix:'Rafix',screw:'Screw',dowel:'Dowel',ovvo_od830:'OVVO OD830'})[value]||title(value);
  const categories=['Room walls','Room measurements','Cabinet measurements','Carcass','Backs','Stretchers','Doors','Drawer faces','Drawer boxes','Connectors','Hinges','Runners','Gola','Finger pulls','Upper covers','Edgebands','Machining','Part numbers','Nesting','Appliances','Plinth','Worktop'];
  const rates=[['board_per_m2','Carcass board / m²'],['front_per_m2','Front board / m²'],['back_per_m2','Back panel / m²'],['worktop_per_m2','Worktops / m²'],['profile_per_m','Gola profiles / m'],['band_per_m','Edge band / m'],['hardware_each','Hardware / item']];

  function normalize(project){
    if(!project)return null;
    const p=copy(project);p.room ||= {walls:[]};p.room.walls ||= [];
    p.design ||= {style:'modern_gola',settings:{},cabinets:[]};p.design.settings ||= {};p.design.cabinets ||= [];p.design.accessories ||= {worktops:false,end_scribe_mm:0};
    p.quote ||= {currency:'LKR',rates:{},labour:0,markup_pct:0,tax_pct:0};p.quote.rates ||= {};
    return p;
  }

  function accept(project){state.project=normalize(project);state.baseModelSerial=state.latestModelSerial;state.formDirty=false;if(!state.project?.room.walls.some(w=>w.id===state.wallId))state.wallId=state.project?.room.walls[0]?.id||null;}

  function notify(message,error=false){state.message=message;state.error=error?message:null;status();}

  function status(){
    const p=state.project;
    $('#revision').textContent=p?`Web R${p.revision}${state.remote_revision>p.revision?` · newer R${state.remote_revision}`:''}`:'No project';
    $('#revision').className=`badge${p&&state.remote_revision>p.revision?' warning':''}`;
    $('#draft-status').textContent=locked()?'Working…':state.formDirty?'Unbuilt form edits':state.dirty?'Local model · not saved':'In sync';
    $('#draft-status').className=`badge${state.formDirty||state.dirty?' warning':''}`;
    const box=$('#message');box.hidden=!state.message&&!state.error;box.textContent=state.error||state.message||'';box.className=`message${state.error?' error':''}`;
    $('#server').textContent=state.server||'Local project service';
    $('#footer-state').textContent=state.formDirty?'Form edits stay here until Build model or Save to web.':'Dimensions in mm · photos optional';
    for(const control of document.querySelectorAll('button,input,select,textarea')){
      if(control.closest('#modal')&&control.hasAttribute('data-dismiss'))continue;
      if(locked()&&!control.disabled){control.dataset.busyDisabled='true';control.disabled=true;}
      else if(!locked()&&control.dataset.busyDisabled){delete control.dataset.busyDisabled;control.disabled=false;}
    }
    for(const button of document.querySelectorAll('[data-action="apply"],[data-action="save"],[data-action="pull"],[data-action="capture"]')){
      if(!locked())button.disabled=!p;
    }
  }

  function dirty(){state.formDirty=true;state.error=null;status();const total=$('#estimate-total');if(total)total.textContent='Recalculate local estimate';}

  function dispatch(action,payload={},after){
    if(locked())return false;
    if(!window.sketchup?.luxktc_action){notify('Open this studio from the LuxKTC SketchUp extension to connect to Ruby.',true);return false;}
    if(['apply','save','report'].includes(action))payload={...payload,base_model_serial:state.baseModelSerial};
    state.error=null;state.pending={action,after};status();
    try{window.sketchup.luxktc_action(JSON.stringify({action,payload}));return true;}
    catch(error){state.pending=null;notify(error.message||'SketchUp could not receive this action.',true);status();return false;}
  }

  function receive(snapshot){
    if(!snapshot||typeof snapshot!=='object')return;
    const pending=state.pending;
    if(Object.prototype.hasOwnProperty.call(snapshot,'model_serial'))state.latestModelSerial=snapshot.model_serial;
    for(const key of ['projects','catalog','bom','quote','server','dirty','remote_revision','visibility'])if(Object.prototype.hasOwnProperty.call(snapshot,key))state[key]=snapshot[key];
    state.projects ||= [];state.catalog ||= {cabinets:[],connectors:[],hinges:[]};state.visibility ||= {};
    if(Object.prototype.hasOwnProperty.call(snapshot,'project'))state.latest=normalize(snapshot.project);
    state.busy=Boolean(snapshot.busy);
    if(state.busy){status();return;}
    state.pending=null;
    const failed=Boolean(snapshot.error);
    const accepted=snapshot.accept_draft===true;
    // An editor dialog has uncommitted field values as well as the main draft.
    if(!failed&&(accepted||(!state.formDirty&&!$('#modal').open)))accept(state.latest);
    state.message=snapshot.message||'';state.error=failed?String(snapshot.error):null;
    render();
    if(pending?.after&&!failed&&accepted)pending.after();
  }
  window.LuxKTCStudio={receive};

  function field(text,name,value,{type='text',min,max,unit='',required=false,full=false,step='any'}={}){
    const input=`<input name="${escape(name)}" id="f-${escape(name)}" type="${type}" value="${escape(value??'')}" ${min!==undefined?`min="${min}"`:''} ${max!==undefined?`max="${max}"`:''} ${type==='number'?`step="${step}"`:''} ${required?'required':''}>`;
    return `<div class="field ${full?'full':''}"><label for="f-${escape(name)}">${escape(text)}</label>${unit?`<div class="input-unit">${input}<span>${escape(unit)}</span></div>`:input}</div>`;
  }
  const metric=(text,name,value,opts={})=>field(text,name,value,{type:'number',min:0,max:100000,unit:'mm',...opts});
  function select(text,name,value,options,full=false){return `<div class="field ${full?'full':''}"><label for="f-${escape(name)}">${escape(text)}</label><select name="${escape(name)}" id="f-${escape(name)}">${options.map(item=>{const [id,name]=Array.isArray(item)?item:[item,title(item)];return `<option value="${escape(id)}" ${String(id)===String(value)?'selected':''}>${escape(name)}</option>`;}).join('')}</select></div>`;}

  function modal(heading,description,body,submit,buttons){
    const dialog=$('#modal'),form=$('#modal-form');dialog.returnValue='cancel';
    form.innerHTML=`<div class="modal-heading"><h2>${escape(heading)}</h2><p>${escape(description)}</p></div><div class="modal-body">${body}<div id="modal-error" class="modal-error" role="alert"></div></div><div class="modal-footer">${buttons||'<button class="button secondary" type="button" data-dismiss>Cancel</button><button class="button" type="submit">Apply form edit</button>'}</div>`;
    form.onsubmit=event=>{event.preventDefault();if(locked())return;try{if(submit(new FormData(form))!==false)dialog.close('ok');}catch(error){$('#modal-error').textContent=error.message;}};
    for(const close of form.querySelectorAll('[data-dismiss]'))close.onclick=()=>dialog.close('cancel');
    dialog.showModal();return dialog;
  }

  function guard(continuation){
    if(!state.formDirty){continuation();return;}
    const dialog=modal('Keep your form edits?','These edits have not been built in SketchUp or saved to the shared project.','<p class="help">Save to web before continuing, discard only these form edits, or stay here. SketchUp also checks for unsaved model changes before replacing a project.</p>',()=>{dialog.close('save');dispatch('save',{project:copy(state.project)},continuation);return false;},'<button class="button secondary" type="button" data-dismiss>Stay here</button><button class="button secondary" type="button" id="discard-form">Discard form edits</button><button class="button" type="submit">Save to web & continue</button>');
    $('#discard-form').onclick=()=>{accept(state.latest);dialog.close('discard');continuation();};
  }

  function render(){
    const p=state.project;
    $('#projects').innerHTML=state.projects.length?state.projects.map(project=>`<button class="project-row ${project.id===p?.id?'active':''}" data-action="open" data-id="${escape(project.id)}"><strong>${escape(project.name)}</strong><small>${escape(project.client||'Kitchen project')} · R${escape(project.revision)}</small></button>`).join(''):'<p class="sidebar-empty">Create a project or refresh the list to see your web projects here.</p>';
    $('#project-title').textContent=p?.name||'Your kitchen in SketchUp.';
    $('#project-subtitle').textContent=p?(p.client||'Native project editor · shared with the web'):'A native workspace connected to the same web project.';
    for(const tab of document.querySelectorAll('.tab'))tab.classList.toggle('active',tab.dataset.tab===state.tab);
    $('#content').innerHTML=!p?empty():state.tab==='room'?roomView():state.tab==='cabinets'?cabinetView():state.tab==='bom'?bomView():projectView();
    status();
  }

  function empty(){return `<section class="card empty"><div class="eyebrow">START WITH REAL DIMENSIONS</div><div class="empty-symbol">⌑</div><h2>A room is enough to begin.</h2><p>Create an empty project and enter wall dimensions directly in SketchUp. Photos and openings are optional. Or start from the existing 10-foot Gola kitchen.</p><button class="button" data-action="new">+ New project</button></section>`;}

  function projectView(){const p=state.project;return `<div class="grid"><section class="card"><div class="card-head"><h3>Project details</h3><small>One project · two interfaces</small></div><div class="pad"><div class="fields">${field('Project name','project-name',p.name,{required:true,full:true})}${field('Client / reference','project-client',p.client,{full:true})}</div><hr class="separator"><div class="mini-heading">SHARED PROJECT ID</div><div class="project-id">${escape(p.id)}</div><div class="form-footer"><span class="help">Modern Gola · ${p.room.walls.length} walls · ${p.design.cabinets.length} cabinets</span><button class="text-button danger" data-action="delete_project">Delete shared project</button></div></div></section><div class="stack"><div class="notice"><strong>Work here or on the web.</strong><br>Build model applies your form edits locally. Save to web builds and pushes the project. Pull web changes receives the latest shared revision.<br><br><strong>Photo optional—dimensions are enough.</strong> Add walls and openings here; wall photos can be added later through the web interface.</div><section class="card"><div class="card-head"><h3>Project state</h3><button class="text-button" data-action="poll">Check web</button></div><div class="pad"><div class="quote-line"><span>Loaded web revision</span><strong>R${escape(p.revision)}</strong></div><div class="quote-line"><span>Form changes</span><strong>${state.formDirty?'Unbuilt edits':'Applied / unchanged'}</strong></div><div class="quote-line"><span>Model changes</span><strong>${state.dirty?'Not saved to web':'In sync'}</strong></div><p class="help" style="margin:13px 0 0">Revisions protect edits from being silently overwritten by the other interface.</p></div></section></div></div>${visibilityView()}`;}

  function roomView(){const p=state.project,w=wall();return `<div class="section-heading"><div><h2>Measured walls.</h2><p>Photo optional—dimensions are enough. Enter dimensions in millimetres.</p></div><button class="button secondary small" data-action="add-wall">+ Add wall</button></div>${!w?'<section class="card empty"><h2>Add your first wall.</h2><p>No image is required. Start with width, height and wall placement.</p><button class="button" data-action="add-wall">+ Add wall</button></section>':`<div class="wall-chips">${p.room.walls.map(item=>`<button class="wall-chip ${item.id===w.id?'active':''}" data-action="wall" data-id="${escape(item.id)}">${escape(item.name)} · ${mm(item.width_mm)}</button>`).join('')}</div><div class="grid"><section class="card"><div class="card-head"><h3>Wall dimensions & placement</h3><button class="text-button danger" data-action="remove-wall">Remove</button></div><div class="pad"><div class="fields">${field('Wall name','wall-name',w.name,{full:true,required:true})}${metric('Width','wall-width_mm',w.width_mm,{min:100,required:true})}${metric('Height','wall-height_mm',w.height_mm,{min:100,max:20000,required:true})}${metric('Thickness','wall-thickness_mm',w.thickness_mm,{min:1,max:2000})}${field('Rotation','wall-rotation_deg',w.rotation_deg||0,{type:'number',min:-3600,max:3600,unit:'°'})}</div><hr class="separator"><div class="mini-heading">ROOM ORIGIN</div><div class="fields three">${[0,1,2].map(index=>metric(['X','Y','Z'][index],`wall-origin_${index}`,w.origin_mm?.[index]||0,{min:-1000000,max:1000000})).join('')}</div><label class="checkline" style="margin-top:18px"><input id="wall-confirmed" type="checkbox" ${w.measurements_confirmed?'checked':''}><span>I checked these width and height measurements on site.</span></label><p class="help" style="margin:12px 0 0">Wall local X runs left to right. Z runs up from the floor. Rotation and origin place it in the room.</p></div>${wallDiagram(w)}</section><div class="stack"><section class="card"><div class="card-head"><h3>Openings & services · ${w.openings?.length||0}</h3><button class="text-button" data-action="add-opening">+ Add</button></div><div class="pad" style="padding-top:5px;padding-bottom:8px">${w.openings?.length?w.openings.map(opening=>`<div class="opening-row"><div><strong>${escape(title(opening.type))} ${opening.confirmed?'':'<span class="badge warning">Unconfirmed</span>'}</strong><small>${mm(opening.width_mm)} × ${mm(opening.height_mm)} · X ${mm(opening.x_mm)} / Z ${mm(opening.z_mm)}</small></div><div class="actions"><button class="text-button" data-action="edit-opening" data-id="${escape(opening.id)}">Edit</button><button class="text-button danger" data-action="remove-opening" data-id="${escape(opening.id)}" aria-label="Remove opening">×</button></div></div>`).join(''):'<p class="help" style="margin-top:12px">Optional: add doors, windows, sockets, plumbing or obstructions when needed. An empty list means a plain wall.</p>'}</div></section><div class="notice">${w.photo_asset_id?'<strong>This wall has a shared photo.</strong><br>The existing original and corrected texture stay with the project. Edit the image through the web interface.':'<strong>Plain measured wall.</strong><br>You can build this wall immediately without uploading a photo.'}</div></div></div>`}${visibilityView()}`;}

  function wallDiagram(w){const width=Math.max(100,number(w.width_mm)),height=Math.max(100,number(w.height_mm)),font=Math.max(width/45,40),pad=Math.max(width*.11,220);return `<svg class="room-outline" viewBox="${-pad} ${-pad} ${width+pad*2} ${height+pad*2}" role="img" aria-label="${escape(w.name)} front outline"><rect width="${width}" height="${height}" fill="#e8edde" stroke="#94a37f" stroke-width="${font/18}"/>${(w.openings||[]).map(o=>`<rect x="${number(o.x_mm)}" y="${height-number(o.z_mm)-number(o.height_mm)}" width="${number(o.width_mm)}" height="${number(o.height_mm)}" fill="#d9c6a6" stroke="#aa8a59" stroke-width="${font/25}"/><text x="${number(o.x_mm)+number(o.width_mm)/2}" y="${height-number(o.z_mm)-number(o.height_mm)/2}" text-anchor="middle" font-size="${font*.55}" fill="#816c48">${escape(title(o.type))}</text>`).join('')}<text x="${width/2}" y="${-pad*.35}" text-anchor="middle" fill="#6a7b57" font-size="${font}">${mm(width)} mm</text><text x="${width/2}" y="${height+pad*.65}" text-anchor="middle" fill="#788769" font-size="${font*.7}">Height ${mm(height)} mm · Thickness ${mm(w.thickness_mm)} mm</text></svg>`;}

  function cabinetView(){const p=state.project,s=p.design.settings,a=p.design.accessories;return `<div class="section-heading"><div><h2>Cabinets & construction.</h2><p>Qualified straight units · open shelving is upper only.</p></div><button class="button secondary small" data-action="add-cabinet" ${!p.room.walls.length?'disabled':''}>+ Add cabinet</button></div>${!p.room.walls.length?'<div class="notice warning" style="margin-bottom:16px">Add a measured wall before placing cabinets. No photo is required.</div>':''}<section class="card"><div class="card-head"><h3>Cabinet schedule · ${p.design.cabinets.length}</h3><small>W × H × D · mm</small></div><div class="table-wrap"><table><thead><tr><th>Cabinet</th><th>Wall</th><th>Box dimensions</th><th>Placement X / Y / Z</th><th>Connector</th><th></th></tr></thead><tbody>${p.design.cabinets.length?p.design.cabinets.map(c=>`<tr><td><strong>${escape(c.local_id)}</strong> ${escape(c.name)}<br><small>${escape(title(c.type))}</small></td><td>${escape(p.room.walls.find(w=>w.id===c.wall_id)?.name||'Unassigned')}</td><td>${mm(c.width_mm)} × ${mm(c.height_mm)} × ${mm(c.depth_mm)}</td><td>${mm(c.x_mm)} / ${mm(c.y_mm)} / ${mm(c.z_mm)}<br><small>Rotation ${mm(c.rotation_deg||0)}°</small></td><td>${escape(connector(c.options?.joinery||s.joinery))}</td><td><div class="actions"><button class="text-button" data-action="edit-cabinet" data-id="${escape(c.id)}">Edit</button><button class="text-button danger" data-action="remove-cabinet" data-id="${escape(c.id)}" aria-label="Delete ${escape(c.local_id)}">×</button></div></td></tr>`).join(''):'<tr><td colspan="6" class="help">Add cabinets from the qualified catalogue to start your layout.</td></tr>'}</tbody></table></div><div class="footnote">Base and tall units sit on the existing 100 mm plinth; upper Z is the direct bottom height. Box dimensions exclude the plinth. Use the model dimension toggles below.</div></section><section class="card" style="margin-top:17px"><div class="card-head"><h3>Project construction defaults</h3><small>Modern Gola</small></div><div class="pad"><div class="fields three">${select('Connector','setting-joinery',s.joinery||'minifix',(state.catalog.connectors||[]).map(value=>[value,connector(value)]))}${select('Hinge','setting-hinge',s.hinge||'cup35_screw',state.catalog.hinges||[])}${metric('Carcass edge band','setting-edge',s.edge??1,{max:2})}${metric('Front edge band','setting-front_edge',s.front_edge??1,{max:2})}${metric('End scribe width','accessory-end_scribe_mm',a.end_scribe_mm||0,{max:100})}</div><label class="checkline" style="margin-top:16px"><input id="accessory-worktops" type="checkbox" ${a.worktops?'checked':''}><span>Generate straight-run worktops</span></label><p class="help" style="margin:13px 0 0">0 mm disables end scribes. Per-cabinet settings override these defaults. Grooved backs and stretchers stay in the board engine; edge band thickness changes cut sizes.</p></div></section>${visibilityView()}`;}

  function visibilityView(){return `<details class="visibility"><summary>Model visibility · dimensions, fronts, hardware & machining</summary><div class="toggle-grid">${categories.map(category=>{const known=Object.prototype.hasOwnProperty.call(state.visibility,category);return `<button class="toggle-button ${known?(state.visibility[category]?'on':'off'):''}" data-action="toggle" data-category="${escape(category)}">${known?(state.visibility[category]?'●':'○'):'Toggle'} ${escape(category)}</button>`;}).join('')}</div></details>`;}

  function bomView(){const p=state.project,b=state.bom,q=state.quote,totals=b?.totals||{},parts=b?.parts||[],preview=Boolean(b?.preview||q?.preview),local=state.formDirty||state.dirty||preview,status=b?.status||p.manufacturing?.status||'needs_regeneration',unpriced=!q||q.status==='unpriced'||q.missing_rates?.length;return `<div class="section-heading"><div><h2>Parts & project estimate.</h2><p>Ruby manufacturing data, with your material and hardware rates.</p></div><div class="actions"><button class="button secondary small" data-action="report">Recalculate local preview</button><button class="text-button" data-action="open_web">Web exports ↗</button></div></div><div class="notice ${local||status!=='current'?'warning':''}" style="margin-bottom:16px">${local?'Local draft / model changes exist. Preview values are indicative until you save the shared project. ':''}${preview?'Local preview only; the shared project has not been saved. ':status==='current'?'Generated manufacturing snapshot.':'Manufacturing data needs generation. '}${state.formDirty?'Recalculate the preview after editing dimensions or rates.':''}</div><div class="stats"><div class="stat"><small>Cabinets</small><strong>${p.design.cabinets.length}</strong></div><div class="stat"><small>Generated parts</small><strong>${b?parts.length:'—'}</strong></div><div class="stat"><small>Edge band</small><strong>${b?mm(totals.band_length_m):'—'} <span style="font-size:11px">m</span></strong></div></div><div class="grid wide"><div class="stack"><section class="card"><div class="card-head"><h3>Bill of materials</h3><small>${preview?'Local preview':escape(status)} · source R${escape(b?.source_revision??'—')}</small></div><div class="table-wrap"><table><thead><tr><th>Part / name</th><th>Cabinet</th><th>Cut size · mm</th><th>Material</th><th>Bands</th><th>Machining</th></tr></thead><tbody>${parts.length?parts.map(part=>`<tr><td><strong>${escape(part.number||part.id)}</strong><br><small>${escape(part.name)}</small></td><td>${escape(part.cabinet_id)}</td><td>${mm(part.w)} × ${mm(part.h)} × ${mm(part.t)}<br><small>Finished ${mm(part.finished_w??part.w)} × ${mm(part.finished_h??part.h)}</small></td><td>${escape(part.material)}</td><td>${escape(edges(part.edges))}</td><td>${escape(operations(part.operations))}</td></tr>`).join(''):'<tr><td colspan="6" class="help">No preview parts loaded. Recalculate to generate a local estimate from the current draft.</td></tr>'}</tbody></table></div><div class="footnote">BOMs use real Ruby parts. CUT, DRILL, POCKET and GROOVE operations remain separate in manufacturing exports.</div></section>${b?.hardware?.length?`<section class="card"><div class="card-head"><h3>Hardware</h3></div><div class="table-wrap"><table><thead><tr><th>Item</th><th>Quantity</th></tr></thead><tbody>${b.hardware.map(item=>`<tr><td>${escape(item.name)}</td><td>${mm(item.quantity??item.qty??item.count)}</td></tr>`).join('')}</tbody></table></div></section>`:''}</div><section class="card quote-card"><div class="quote-total"><small>INDICATIVE ESTIMATE · ${escape(p.quote.currency)}</small><strong id="estimate-total">${state.formDirty?'Recalculate local estimate':unpriced?'Not fully priced':`${escape(q.currency||p.quote.currency)} ${money(q.total)}`}</strong><p>${local?'Local preview · not a saved final quote':unpriced?'Enter the missing rates below':'Saved rates and manufacturing quantities'}</p></div><div class="pad">${q?.lines?.length?`<div style="margin-bottom:16px">${q.lines.map(line=>`<div class="quote-line"><span>${escape(line.description)}</span><strong>${money(line.amount)}</strong></div>`).join('')}<div class="quote-line"><span>Labour / markup / tax</span><strong>${money(number(q.labour)+number(q.markup)+number(q.tax))}</strong></div></div>`:''}<div class="fields" style="margin-bottom:16px">${field('Currency (3 letters)','quote-currency',p.quote.currency,{full:true})}</div><div class="mini-heading">YOUR RATES</div>${rates.map(([key,text])=>`<div class="rate-row"><label for="rate-${key}">${escape(text)}</label><input id="rate-${key}" type="number" min="0" max="1000000000000" step="any" data-rate="${key}" value="${escape(p.quote.rates[key]||0)}"></div>`).join('')}<hr class="separator">${[['labour','Labour'],['markup_pct','Markup %'],['tax_pct','Tax %']].map(([key,text])=>`<div class="rate-row"><label for="quote-${key}">${text}</label><input id="quote-${key}" data-quote="${key}" type="number" min="0" max="${key==='labour'?1000000000000:1000}" step="any" value="${escape(p.quote[key]||0)}"></div>`).join('')}<p class="help" style="margin:13px 0">${q?.missing_rates?.length?`Missing rates: ${q.missing_rates.map(key=>escape(title(key))).join(', ')}.`:'Zero rates are unpriced when the BOM needs that material.'}</p><button class="button full" data-action="report">Recalculate local preview</button><p class="help" style="margin:12px 0 0">${(q?.notices||['Net cut-part areas exclude sheet waste and delivery. Hardware uses an aggregate allowance.']).map(escape).join(' ')}</p></div></section></div>`;}

  function edges(value){return Object.entries(value||{}).filter(([,t])=>number(t)>0).map(([side,t])=>`${side} ${mm(t)} mm`).join(' · ')||'—';}
  function operations(items){const counts={};for(const item of items||[]){const key=item.kind||item.type||item.operation||'Operation';counts[key]=(counts[key]||0)+1;}return Object.entries(counts).map(([key,n])=>`${title(key)} ${n}`).join(' · ')||'—';}

  function newProject(){modal('Create a shared project','An empty project needs no photo. Add its walls directly in this panel.',`<div class="fields">${field('Project name','name','Kitchen project',{required:true,full:true})}${field('Client / reference','client','',{full:true})}${select('Starting point','template','empty',[['empty','Empty measured project'],['10ft','Existing 10-foot Gola kitchen']],true)}</div>`,data=>{const payload={name:data.get('name').trim(),client:data.get('client').trim(),template:data.get('template')};$('#modal').close('create');guard(()=>dispatch('create',payload));return false;},'<button type="button" class="button secondary" data-dismiss>Cancel</button><button class="button" type="submit">Create project</button>');}

  function addWall(){modal('Add a wall','Enter dimensions directly. A wall photo is optional.',`<div class="fields">${field('Wall name','name',`Wall ${String.fromCharCode(65+state.project.room.walls.length)}`,{required:true,full:true})}${metric('Width','width_mm',3000,{min:100,required:true})}${metric('Height','height_mm',2600,{min:100,max:20000,required:true})}${metric('Thickness','thickness_mm',150,{min:1,max:2000,required:true})}</div><label class="checkline" style="margin-top:16px"><input type="checkbox" name="confirmed"><span>Width and height checked on site.</span></label>`,data=>{const w={id:uuid(),name:data.get('name').trim(),width_mm:number(data.get('width_mm')),height_mm:number(data.get('height_mm')),thickness_mm:number(data.get('thickness_mm')),origin_mm:[0,0,0],rotation_deg:0,measurements_confirmed:data.has('confirmed'),photo_asset_id:null,rectified_asset_id:null,photo_quad:null,openings:[]};state.project.room.walls.push(w);state.wallId=w.id;dirty();render();});}

  function openingEditor(id){const w=wall(),existing=w.openings?.find(o=>o.id===id),o=existing||{type:'window',x_mm:0,z_mm:0,width_mm:'',height_mm:'',confirmed:false};modal(existing?'Edit opening':'Add opening / service','Measure X from the wall’s left edge and Z from the floor.',`<div class="fields">${select('Type','type',o.type,['door','window','socket','switch','plumbing','obstruction'],true)}${metric('Left X','x_mm',o.x_mm,{required:true})}${metric('Bottom / sill Z','z_mm',o.z_mm,{required:true})}${metric('Width','width_mm',o.width_mm,{min:1,required:true})}${metric('Height','height_mm',o.height_mm,{min:1,required:true})}</div><label class="checkline" style="margin-top:17px"><input name="confirmed" type="checkbox" ${o.confirmed?'checked':''}><span>Position and dimensions checked on site.</span></label>`,data=>{const updated={id:existing?.id||uuid(),type:data.get('type'),x_mm:number(data.get('x_mm')),z_mm:number(data.get('z_mm')),width_mm:number(data.get('width_mm')),height_mm:number(data.get('height_mm')),confirmed:data.has('confirmed')};if(updated.x_mm+updated.width_mm>w.width_mm||updated.z_mm+updated.height_mm>w.height_mm)throw new Error('The opening must fit inside this measured wall.');w.openings ||= [];if(existing)Object.assign(existing,updated);else w.openings.push(updated);dirty();render();});}

  function cabinetEditor(id){
    const p=state.project,existing=p.design.cabinets.find(c=>c.id===id),catalog=(state.catalog.cabinets||[]).filter(c=>c.type!=='base_open');
    if(!p.room.walls.length)return notify('Add a measured wall first. No photo is required.',true);
    if(!catalog.length)return notify('The qualified cabinet catalogue is unavailable. Refresh the project list.',true);
    const recipe=catalog.find(c=>c.type==='base_single')||catalog[0];
    const nextNumber=type=>{const prefix=type.startsWith('wall_')?'W':'B';let n=1;while(p.design.cabinets.some(c=>c.id!==existing?.id&&c.local_id===`${prefix}${String(n).padStart(2,'0')}`))n++;return `${prefix}${String(n).padStart(2,'0')}`;};
    const c=existing||{id:uuid(),local_id:nextNumber(recipe.type),name:recipe.name,type:recipe.type,wall_id:wall()?.id||p.room.walls[0].id,width_mm:recipe.width_mm,height_mm:recipe.height_mm,depth_mm:recipe.depth_mm,x_mm:0,y_mm:0,z_mm:recipe.type.startsWith('wall_')?1400:0,rotation_deg:0,options:{}};
    const o=c.options||{},s=p.design.settings;
    const dialog=modal(existing?`Edit ${c.local_id}`:'Add cabinet','Qualified dimensions and placement feed the same board engine used by the web.',`<div class="fields">${field('Cabinet number','local_id',c.local_id,{required:true})}${field('Name','name',c.name,{required:true})}${select('Type','type',c.type,catalog.map(item=>[item.type,item.name]),true)}${select('Wall','wall_id',c.wall_id,p.room.walls.map(w=>[w.id,w.name]),true)}${metric('Width','width_mm',c.width_mm,{min:250,max:1200,required:true})}${metric('Height','height_mm',c.height_mm,{min:300,max:2600,required:true})}${metric('Depth','depth_mm',c.depth_mm,{min:250,max:900,required:true})}${metric('Left X','x_mm',c.x_mm,{min:-100000})}${metric('Depth offset Y','y_mm',c.y_mm,{min:-100000})}${metric('Bottom Z input','z_mm',c.z_mm,{min:-100000})}${field('Rotation','rotation_deg',c.rotation_deg,{type:'number',min:-3600,max:3600,unit:'°'})}${select('Worktop role','role',o.role||'standard',[['standard','Standard cabinet'],['hob','Hob / cooktop position']])}${select('Connector','joinery',o.joinery||'',[['',`Project default (${connector(s.joinery)})`],...(state.catalog.connectors||[]).map(value=>[value,connector(value)])])}${select('Hinge','hinge',o.hinge||'',[['','Project default'],...(state.catalog.hinges||[]).map(value=>[value,title(value)])])}${metric('Carcass edge override','edge',o.edge??'',{max:2})}${metric('Front edge override','front_edge',o.front_edge??'',{max:2})}</div><p class="help" style="margin:15px 0 0">Blank edge fields use project defaults. Base and tall units add the existing 100 mm plinth to Z; upper Z is its direct bottom height. Use B01/B001 for base or tall, W01/W001 for upper units.</p>`,data=>{
      const local=data.get('local_id').trim(),type=data.get('type');if(!/^[BW][0-9]{2,4}$/.test(local))throw new Error('Use B01/B001 or W01/W001 cabinet numbering.');if(!local.startsWith(type.startsWith('wall_')?'W':'B'))throw new Error('Use W for upper units and B for base or tall units.');if(p.design.cabinets.some(item=>item.id!==existing?.id&&item.local_id===local))throw new Error('This cabinet number is already used.');
      const updated={...c,local_id:local,type,name:data.get('name').trim(),wall_id:data.get('wall_id'),options:{...o}};for(const key of ['width_mm','height_mm','depth_mm','x_mm','y_mm','z_mm','rotation_deg'])updated[key]=number(data.get(key));for(const key of ['joinery','hinge','edge','front_edge','role']){const value=data.get(key);if(value==='')delete updated.options[key];else updated.options[key]=['edge','front_edge'].includes(key)?number(value):value;}
      if(existing)Object.assign(existing,updated);else p.design.cabinets.push(updated);state.wallId=updated.wall_id;dirty();render();
    });
    $('#f-type',dialog).onchange=event=>{const selected=catalog.find(item=>item.type===event.target.value);if(!selected)return;$('#f-local_id',dialog).value=nextNumber(selected.type);if(!existing){for(const key of ['width_mm','height_mm','depth_mm'])$(`#f-${key}`,dialog).value=selected[key];$('#f-name',dialog).value=selected.name;$('#f-z_mm',dialog).value=selected.type.startsWith('wall_')?1400:0;}};
  }

  function validDraft(){
    const p=state.project;if(!p)return false;
    if(!p.name.trim())return notify('Enter a project name.',true),false;
    if(!/^[A-Z]{3}$/.test(p.quote.currency))return notify('Currency must be a three-letter uppercase code, such as LKR.',true),false;
    for(const input of document.querySelectorAll('#content input'))if(!input.checkValidity()){input.reportValidity();return false;}
    return true;
  }

  function action(name,element){
    if(locked())return;
    if(name==='tab'){state.tab=element.dataset.tab;render();return;}
    if(name==='new')return newProject();
    if(['ready','list','poll','open_web'].includes(name))return dispatch(name);
    if(name==='open')return guard(()=>dispatch('open',{id:element.dataset.id}));
    if(!state.project)return;
    if(['apply','save','report'].includes(name)){if(validDraft())dispatch(name,{project:copy(state.project)});return;}
    if(name==='pull'||name==='capture')return guard(()=>dispatch(name));
    if(name==='delete_project')return guard(()=>{modal('Delete this shared project?',`“${state.project.name}” will be removed from the shared project list.`, '<p class="help">This affects the web project too. The current SketchUp geometry is managed separately by the extension.</p>',()=>{dispatch('delete_project');return true;},'<button class="button secondary" type="button" data-dismiss>Cancel</button><button class="button danger" type="submit">Delete shared project</button>');});
    if(name==='wall'){state.wallId=element.dataset.id;render();return;}
    if(name==='add-wall')return addWall();
    if(name==='remove-wall'){const w=wall(),count=state.project.design.cabinets.filter(c=>c.wall_id===w.id).length;modal('Remove this wall?',`Remove “${w.name}”${count?` and ${count} assigned cabinets`:''} from your draft?`,'<p class="help">This is a local form edit until you build or save the project.</p>',()=>{state.project.room.walls=state.project.room.walls.filter(item=>item.id!==w.id);state.project.design.cabinets=state.project.design.cabinets.filter(c=>c.wall_id!==w.id);state.wallId=state.project.room.walls[0]?.id||null;dirty();render();},'<button class="button secondary" type="button" data-dismiss>Cancel</button><button class="button danger" type="submit">Remove wall</button>');return;}
    if(name==='add-opening')return openingEditor();
    if(name==='edit-opening')return openingEditor(element.dataset.id);
    if(name==='remove-opening'){wall().openings=wall().openings.filter(o=>o.id!==element.dataset.id);dirty();render();return;}
    if(name==='add-cabinet')return cabinetEditor();
    if(name==='edit-cabinet')return cabinetEditor(element.dataset.id);
    if(name==='remove-cabinet'){state.project.design.cabinets=state.project.design.cabinets.filter(c=>c.id!==element.dataset.id);dirty();render();return;}
    if(name==='toggle')return dispatch('toggle',{category:element.dataset.category});
  }

  document.addEventListener('click',event=>{if(locked()||event.target.closest('#modal'))return;const element=event.target.closest('[data-action]');if(element)action(element.dataset.action,element);});
  document.addEventListener('input',event=>{
    if(locked()||!state.project||event.target.closest('#modal'))return;const target=event.target,name=target.name||'',p=state.project;
    if(name==='project-name'){p.name=target.value;$('#project-title').textContent=p.name;dirty();return;}
    if(name==='project-client'){p.client=target.value;dirty();return;}
    if(name.startsWith('wall-')){const w=wall();if(!w)return;const key=name.slice(5);if(key.startsWith('origin_')){w.origin_mm ||= [0,0,0];w.origin_mm[number(key.slice(7))]=number(target.value);}else w[key]=key==='name'?target.value:number(target.value);if(['width_mm','height_mm'].includes(key)){w.measurements_confirmed=false;const confirmed=$('#wall-confirmed');if(confirmed)confirmed.checked=false;}dirty();return;}
    if(name.startsWith('setting-')){const key=name.slice(8);p.design.settings[key]=['edge','front_edge'].includes(key)?number(target.value):target.value;dirty();return;}
    if(name==='accessory-end_scribe_mm'){p.design.accessories.end_scribe_mm=number(target.value);dirty();return;}
    if(name==='quote-currency'){p.quote.currency=target.value.toUpperCase().slice(0,3);dirty();return;}
    if(target.dataset.rate){p.quote.rates[target.dataset.rate]=number(target.value);dirty();return;}
    if(target.dataset.quote){p.quote[target.dataset.quote]=number(target.value);dirty();}
  });
  document.addEventListener('change',event=>{
    if(locked()||!state.project||event.target.closest('#modal'))return;const target=event.target;
    if(target.id==='wall-confirmed'){wall().measurements_confirmed=target.checked;dirty();}
    if(target.id==='accessory-worktops'){state.project.design.accessories.worktops=target.checked;dirty();}
  });
  window.addEventListener('beforeunload',event=>{if(state.formDirty){event.preventDefault();event.returnValue='';}});
  render();dispatch('ready');
})();
