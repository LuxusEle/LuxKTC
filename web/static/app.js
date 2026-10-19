'use strict';

/* One working copy, one server revision. Manufacturing always comes from Ruby. */
const state = {
  projects: [], project: null, catalog: {cabinets: [], connectors: [], hinges: []},
  health: null, tab: 'room', wallId: null, dirty: false, busy: false,
  dimensions: true, showPhoto: true, photoMode: 'original', analysis: null,
  bom: null, quote: null, conflict: null, remoteRevision: null, filter: '', error: null
};
const $ = (selector, root = document) => root.querySelector(selector);
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const uid = () => crypto.randomUUID();
const number = value => Number.isFinite(Number(value)) ? Number(value) : 0;
const mm = value => number(value).toLocaleString(undefined, {maximumFractionDigits: 1});
const money = value => number(value).toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2});
const label = value => String(value || '').replaceAll('_', ' ').replace(/\b\w/g, c => c.toUpperCase());
const wall = () => state.project?.room.walls.find(item => item.id === state.wallId) || state.project?.room.walls[0];
const projectPath = suffix => `/api/projects/${encodeURIComponent(state.project.id)}${suffix || ''}`;
const assetURL = id => `/api/assets/${encodeURIComponent(id)}`;
let toastTimer;

function toast(message, error = false) {
  const element = $('#toast');
  element.textContent = message;
  element.className = `toast${error ? ' error' : ''}`;
  element.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { element.hidden = true; }, error ? 10000 : 4500);
}

async function api(path, options = {}) {
  const headers = options.body ? {'Content-Type':'application/json'} : {};
  const response = await fetch(path, {...options, headers: {...headers, ...(options.headers || {})}, cache:'no-store'});
  let data = null;
  if (response.status !== 204) {
    const contentType = response.headers.get('content-type') || '';
    data = contentType.includes('application/json') ? await response.json() : {detail: await response.text()};
  }
  if (!response.ok) {
    const error = new Error(typeof data?.detail === 'string' ? data.detail : JSON.stringify(data?.detail || `Request failed (${response.status})`));
    error.status = response.status;
    error.data = data;
    throw error;
  }
  return data;
}

function handleError(error) {
  if (error.status === 409 && state.project) {
    state.conflict = error.data;
    render();
    toast('Another client saved a newer revision. Your local edits have been kept.', true);
  } else {
    toast(error.message || 'The studio service could not be reached.', true);
  }
}

async function task(action) {
  if (state.busy) return;
  state.busy = true;
  updateStatus();
  try { return await action(); }
  catch (error) { handleError(error); return false; }
  finally { state.busy = false; updateStatus(); }
}

function acceptProject(project, preserveWall = true) {
  state.project = project;
  project.room ||= {walls: []};
  project.room.walls ||= [];
  project.design ||= {style:'modern_gola',settings:{},cabinets:[]};
  project.design.settings ||= {};
  project.design.cabinets ||= [];
  project.design.accessories ||= {worktops:false,end_scribe_mm:0};
  project.quote ||= {currency:'LKR',rates:{},labour:0,markup_pct:0,tax_pct:0};
  project.quote.rates ||= {};
  if (!preserveWall || !project.room.walls.some(item => item.id === state.wallId)) state.wallId = project.room.walls[0]?.id || null;
  state.analysis = wall()?.analysis || wall()?.ai_analysis || null;
  state.dirty = false;
  state.conflict = null;
  state.remoteRevision = null;
  state.bom = null;
  state.quote = null;
  if (typeof history !== 'undefined') history.replaceState(null,'',`?project=${encodeURIComponent(project.id)}`);
}

function markDirty() {
  state.dirty = true;
  state.bom = null;
  state.quote = null;
  const quoteTotal = $('.quote-total strong');
  if (quoteTotal) {
    quoteTotal.textContent = 'Recalculation needed';
    $('.quote-total p').textContent = 'Save your edits to refresh the estimate.';
  }
  updateStatus();
}

function updateStatus() {
  const saveState = $('#save-status');
  if (saveState) {
    saveState.textContent = state.busy ? 'Working…' : state.dirty ? `Unsaved changes${state.remoteRevision ? ` · server R${state.remoteRevision}` : ''}` : `Saved · revision ${state.project?.revision || '—'}`;
    saveState.classList.toggle('dirty', state.dirty);
  }
  // Keep the complete draft stable while a response can replace it. The dialog
  // remains usable for the save/discard guard before the request is sent.
  for (const button of document.querySelectorAll('#main button, #main input, #main select, #main textarea, .sidebar button')) {
    if (state.busy && !button.disabled) { button.dataset.busyDisabled = 'true'; button.disabled = true; }
    else if (!state.busy && button.dataset.busyDisabled) { delete button.dataset.busyDisabled; button.disabled = false; }
  }
  const save = $('#save-project');
  if (save) save.disabled = state.busy || !state.dirty;
}

async function refreshProjects() {
  const result = await api('/api/projects');
  state.projects = Array.isArray(result) ? result : result.projects || [];
  renderProjects();
}

function renderProjects() {
  $('#project-list').innerHTML = state.projects.length ? state.projects.map(project => `<button class="project-link ${state.project?.id === project.id ? 'active' : ''}" data-action="open-project" data-id="${esc(project.id)}"><span class="project-icon" aria-hidden="true">▱</span><span><strong>${esc(project.name)}</strong><small>${esc(project.client || 'Kitchen project')} · R${esc(project.revision)}</small></span></button>`).join('') : '<p class="muted" style="font-size:11px;padding:12px">Your next kitchen starts here. Create a project to begin.</p>';
}

async function saveProject() {
  if (!state.project || !state.dirty) return true;
  if (state.conflict) {
    toast('Resolve the revision conflict before saving. Your local changes are still here.', true);
    return false;
  }
  try {
    const project = await api(projectPath(), {method:'PUT', body:JSON.stringify({base_revision:state.project.revision,project:state.project})});
    acceptProject(project);
    await refreshProjects();
    render();
    return true;
  } catch (error) { handleError(error); return false; }
}

function modal(title, subtitle, body, footer, onSubmit) {
  const dialog = $('#modal');
  const form = $('#modal-form');
  dialog.returnValue = 'cancel';
  form.innerHTML = `<div class="modal-heading"><h2>${esc(title)}</h2>${subtitle ? `<p>${esc(subtitle)}</p>` : ''}</div><div class="modal-body">${body}<div class="modal-error" id="modal-error" role="alert"></div></div><div class="modal-footer">${footer || '<button class="button secondary" type="button" data-close>Cancel</button><button class="button" type="submit">Apply changes</button>'}</div>`;
  form.onsubmit = async event => {
    event.preventDefault();
    try { if (await onSubmit?.(new FormData(form)) !== false) dialog.close('ok'); }
    catch (error) { $('#modal-error').textContent = error.message; }
  };
  for (const button of form.querySelectorAll('[data-close]')) button.onclick = () => dialog.close('cancel');
  dialog.showModal();
  return dialog;
}

async function unsavedGuard() {
  if (!state.dirty) return true;
  const choice = await new Promise(resolve => {
    const dialog = modal('Save your changes?', 'This project has changes that SketchUp and the web service have not received yet.', '<p class="help">Save before continuing, discard the local edits, or stay on this project.</p>', '<button type="button" class="button secondary" data-close>Stay here</button><button type="button" class="button secondary" id="discard-changes">Discard edits</button><button class="button" type="submit">Save & continue</button>', () => true);
    $('#discard-changes').onclick = () => dialog.close('discard');
    dialog.addEventListener('close', () => resolve(dialog.returnValue), {once:true});
  });
  if (choice === 'ok') return await saveProject();
  if (choice === 'discard') {
    acceptProject(await api(projectPath()));
    render();
    return true;
  }
  return false;
}

async function openProject(id) {
  if (state.project?.id === id) return;
  await task(async () => {
    if (!await unsavedGuard()) return;
    acceptProject(await api(`/api/projects/${encodeURIComponent(id)}`), false);
    state.tab = 'room';
    state.photoMode = 'original';
    renderProjects();
    render();
  });
}

function newProject() {
  if (state.busy) return;
  modal('A new kitchen', 'Start with an empty measured room or the existing 10-foot Gola kitchen.', `${field('Project name','name','Kitchen project',{required:true})}<div style="height:15px"></div>${field('Client / reference','client','')}<div style="height:15px"></div>${selectField('Starting point','template','empty',[['empty','Empty measured project'],['10ft','10-foot Gola kitchen']])}`, null, async data => {
    const draft = Object.fromEntries(data);
    $('#modal').close('ok');
    await task(async () => {
      if (!await unsavedGuard()) return;
      acceptProject(await api('/api/projects',{method:'POST',body:JSON.stringify(draft)}),false);
      state.tab = 'room';
      await refreshProjects();
      render();
      toast('Project created. Add your measured walls to begin.');
    });
  });
}

function field(title, name, value, options = {}) {
  const {type='text',unit='',min='',max='',step='any',required=false,full=false} = options;
  const input = `<input id="f-${esc(name)}" name="${esc(name)}" type="${esc(type)}" value="${esc(value ?? '')}" ${min !== '' ? `min="${min}"` : ''} ${max !== '' ? `max="${max}"` : ''} ${type === 'number' ? `step="${step}"` : ''} ${required ? 'required' : ''}>`;
  return `<div class="field ${full ? 'full' : ''}"><label for="f-${esc(name)}">${esc(title)}</label>${unit ? `<div class="input-unit">${input}<span>${esc(unit)}</span></div>` : input}</div>`;
}

function selectField(title, name, value, options, full = false) {
  return `<div class="field ${full ? 'full' : ''}"><label for="f-${esc(name)}">${esc(title)}</label><select id="f-${esc(name)}" name="${esc(name)}">${options.map(option => { const [id,text] = Array.isArray(option) ? option : [option,label(option)]; return `<option value="${esc(id)}" ${String(value) === String(id) ? 'selected' : ''}>${esc(text)}</option>`; }).join('')}</select></div>`;
}

const metricField = (title, name, value, extra = {}) => field(title,name,value,{type:'number',unit:'mm',min:0,max:50000,...extra});

function render() {
  const main = $('#main');
  if (!state.project) {
    main.innerHTML = `<div class="topbar"><span class="breadcrumb">WORKSPACE / <b>Kitchen studio</b></span><span class="pill">WEB + SKETCHUP</span></div><div class="welcome card"><div class="empty"><div class="eyebrow">MEASURE. DESIGN. MAKE.</div><div class="empty-icon" aria-hidden="true">⌑</div><h2>Every kitchen starts with a room.</h2><p>Bring wall photos and real measurements together. Design your kitchen here, refine it in SketchUp, and keep parts and pricing in one project.</p><button class="button" data-action="new-project">+ Create a project</button></div></div>${state.error ? `<div class="banner error">${esc(state.error)}</div>` : ''}`;
    return;
  }
  const p = state.project;
  const status = p.manufacturing?.status || 'needs_regeneration';
  main.innerHTML = `<div class="topbar"><span class="breadcrumb">WORKSPACE / <b>${esc(p.name)}</b></span><div class="top-actions"><span id="save-status" class="save-status"></span><button class="button secondary" data-action="sketchup">↗ Open in SketchUp</button><button class="button" id="save-project" data-action="save" data-network>Save project</button></div></div>
    <div class="page-title"><div><div class="eyebrow" style="margin-bottom:9px">YOUR KITCHEN, CONSIDERED</div><h1>${esc(p.name)}</h1><p>${esc(p.client || 'Measured room · Modern kitchen design')}</p></div><div class="actions"><button class="button secondary small" data-action="edit-project">Project details</button><button class="text-button danger" data-action="delete-project" title="Delete project" data-network>Delete</button></div></div>
    <div class="project-meta"><span class="pill">Modern Gola</span><span class="pill ${status === 'current' ? '' : 'warning'}">${status === 'current' ? 'Parts up to date' : status === 'stale' ? 'Parts need regeneration' : 'Parts not generated'}</span><span class="desktop-note">All dimensions in millimetres</span></div>
    ${state.conflict ? `<div class="banner error"><span><strong>Revision conflict.</strong> The server is at revision ${esc(state.conflict.current_revision)}. Your unsaved edits remain in this browser. Export them before loading the server copy, or keep editing until you can reconcile them.</span><div class="actions"><button class="button secondary small" data-action="export-draft">Download my edits</button><button class="button danger small" data-action="reload-server">Load server copy</button></div></div>` : ''}
    <nav class="tabs" aria-label="Project workflow">${[['room','01','Room & measurements'],['design','02','Kitchen design'],['bom','03','BOM & quote']].map(([id,index,title]) => `<button class="tab ${state.tab === id ? 'active' : ''}" data-action="tab" data-tab="${id}"><span class="tab-number">${index}</span>${title}</button>`).join('')}</nav>
    <div id="tab-content">${state.tab === 'room' ? roomView() : state.tab === 'design' ? designView() : bomView()}</div>`;
  updateStatus();
}

function roomView() {
  const walls = state.project.room.walls;
  const w = wall();
  return `<div class="content-heading"><div><h2>Your room, accurately measured.</h2><p>Add each wall, its openings and a clear photo. Confirm the measurements before correcting perspective.</p></div><button class="button secondary small" data-action="add-wall">+ Add wall</button></div>
    ${!w ? `<div class="card empty"><div class="empty-icon">⌑</div><h2>Let’s measure the first wall.</h2><p>Give it a name, width and height. You can add photos and openings next.</p><button class="button" data-action="add-wall">+ Add your first wall</button></div>` : `<div class="wall-strip">${walls.map(item => `<button class="wall-chip ${w.id === item.id ? 'active' : ''}" data-action="select-wall" data-id="${esc(item.id)}">${esc(item.name)} <span class="muted">· ${mm(item.width_mm)}</span></button>`).join('')}</div><div class="grid-room"><div class="stack"><section class="card"><div class="card-header"><h3>Wall measurements</h3><button class="text-button danger" data-action="remove-wall">Remove wall</button></div><div class="card-pad"><div class="fields" id="wall-fields">${field('Wall name','wall-name',w.name,{full:true})}${metricField('Width','wall-width_mm',w.width_mm,{min:100,required:true})}${metricField('Height','wall-height_mm',w.height_mm,{min:100,required:true})}${metricField('Wall thickness','wall-thickness_mm',w.thickness_mm || 150)}${field('Wall rotation','wall-rotation_deg',w.rotation_deg || 0,{type:'number',unit:'°',min:-360,max:360})}</div><details style="margin-top:15px"><summary class="help" style="cursor:pointer">Room placement / origin</summary><div class="fields three" style="margin-top:12px">${[0,1,2].map((index) => metricField(['Origin X','Origin Y','Origin Z'][index],`wall-origin_${index}`,w.origin_mm?.[index] || 0,{min:-50000})).join('')}</div></details><hr class="separator"><label class="checkline"><input type="checkbox" id="wall-confirmed" ${w.measurements_confirmed ? 'checked' : ''}><span>I have checked the width and height on site.<br><span class="help">Photos and AI suggestions are a guide; these measurements control the model.</span></span></label></div></section>
    <section class="card"><div class="card-header"><h3>Openings & services <span class="muted">(${w.openings?.length || 0})</span></h3><button class="text-button" data-action="add-opening">+ Add</button></div><div class="card-pad" style="padding-top:5px;padding-bottom:8px">${(w.openings || []).length ? w.openings.map(opening => `<div class="opening-row"><div><strong>${esc(label(opening.type))} ${!opening.confirmed ? '<span class="pill warning">Unconfirmed</span>' : ''}</strong><small>${mm(opening.width_mm)} × ${mm(opening.height_mm)} mm · X ${mm(opening.x_mm)}, sill Z ${mm(opening.z_mm)}</small></div><div class="actions"><button class="text-button" data-action="edit-opening" data-id="${esc(opening.id)}">Edit</button><button class="text-button danger" data-action="remove-opening" data-id="${esc(opening.id)}" aria-label="Remove ${esc(opening.type)}">×</button></div></div>`).join('') : '<p class="help" style="margin-top:12px">Add doors, windows, sockets and plumbing with measured positions from the left edge and floor.</p>'}</div></section></div>
    <div class="stack"><section class="card"><div class="card-header"><div><h3>Wall photo</h3><span class="muted">Original image preserved · rectangular texture for SketchUp</span></div><label class="button secondary small" style="cursor:pointer">${w.photo_asset_id ? 'Replace photo' : '+ Upload photo'}<input type="file" id="photo-upload" accept="image/jpeg,image/png,image/webp" hidden></label></div>${photoView(w)}${analysisView(w)}</section><div class="inline-note">A wall photo describes appearance. Its corrected width and height come from your confirmed measurements. The original image, corrected texture and dimensions stay with the shared project.</div></div></div>`}`;
}

function photoView(w) {
  if (!w.photo_asset_id) return '<div class="photo-empty"><div class="empty-icon">▧</div><h3>A clearer starting point.</h3><p>Upload a JPG, PNG or WebP photo, up to 12 MB. Include all four wall corners where possible.</p></div>';
  const corrected = state.photoMode !== 'original' && w.rectified_asset_id;
  const annotated = state.photoMode === 'measured' && w.annotated_asset_id;
  const points = w.photo_quad || [];
  return `<div class="photo-tools"><div class="photo-mode"><button class="${!corrected ? 'active' : ''}" data-action="photo-mode" data-mode="original">Original / corners</button><button class="${corrected && !annotated ? 'active' : ''}" data-action="photo-mode" data-mode="rectified" ${!w.rectified_asset_id ? 'disabled' : ''}>Corrected wall</button>${w.annotated_asset_id ? `<button class="${annotated?'active':''}" data-action="photo-mode" data-mode="measured">Measured photo</button>` : ''}</div><small>${corrected ? `${mm(w.width_mm)} × ${mm(w.height_mm)} mm` : `${points.length}/4 corners selected`}</small></div><div class="photo-stage ${corrected ? '' : 'picking'}" id="photo-stage"><img id="wall-photo" src="${assetURL(annotated ? w.annotated_asset_id : corrected ? w.rectified_asset_id : w.photo_asset_id)}" alt="${esc(w.name)} ${corrected ? 'corrected rectangular wall' : 'original photo; click corners in top-left, top-right, bottom-right, bottom-left order'}"><svg id="photo-overlay" aria-hidden="true"></svg></div>
    ${!corrected ? `<div class="photo-note">Click the wall corners in order: <strong>1 top left → 2 top right → 3 bottom right → 4 bottom left</strong>. Undo a point to correct it. Keep all points inside the photographed wall.</div><div class="actions" style="padding:0 18px 18px"><button class="button secondary small" data-action="undo-quad" ${!points.length ? 'disabled' : ''}>Undo point</button><button class="text-button" data-action="reset-quad" ${!points.length ? 'disabled' : ''}>Reset corners</button><button class="button small" data-action="rectify" data-network ${points.length !== 4 ? 'disabled' : ''}>Correct perspective</button><button class="button subtle small" data-action="analyze" data-network>${state.health?.ai?.configured ? '✦ Analyze wall with AI' : '✦ Check AI setup'}</button></div>` : '<div class="photo-note">This rectangular texture is shared with SketchUp. Switch to the original to adjust the corner selection.</div>'}`;
}

function analysisView(w) {
  const analysis = state.analysis;
  if (!analysis) return '';
  const questions = analysis.questions || [];
  const detections = analysis.detections || [];
  return `<div class="ai-box"><h3>✦ Room photo review</h3><p>These are suggestions. Check the photo and enter real measurements before confirming any opening.</p>${questions.length ? `<div>${questions.map(question => `<div class="ai-question"><strong>${esc(typeof question === 'string' ? question : question.question || JSON.stringify(question))}</strong><span class="ai-answer">Answer by updating the wall or adding a measured opening.</span></div>`).join('')}</div>` : ''}${analysis.wall_quad?.length === 4 ? '<button class="button subtle small" data-action="apply-ai-quad" style="margin-top:13px">Use proposed wall corners</button>' : ''}${detections.length ? `<div style="margin-top:15px"><div class="mini-heading">Possible openings & services</div>${detections.map((detection,index) => `<div class="opening-row"><div><strong>${esc(detection.label || label(detection.type))}</strong><small>${esc(label(detection.type))} · needs on-site measurement${Number.isFinite(detection.confidence) ? ` · ${Math.round(detection.confidence * 100)}% confidence` : ''}</small></div><button class="text-button" data-action="measure-detection" data-index="${index}">Measure & add</button></div>`).join('')}</div>` : ''}${analysis.notes?.length ? `<p style="margin:13px 0 0">${analysis.notes.map(esc).join(' ')}</p>` : ''}</div>`;
}

function addWall() {
  const count = state.project.room.walls.length;
  modal('Add a measured wall','Enter dimensions in millimetres. You can refine placement and add the original photo next.',`<div class="fields">${field('Wall name','name',`Wall ${String.fromCharCode(65+count)}`,{full:true,required:true})}${metricField('Width','width_mm',3048,{min:100,required:true})}${metricField('Height','height_mm',2700,{min:100,required:true})}</div><label class="checkline" style="margin-top:20px"><input type="checkbox" name="confirmed"><span>These dimensions have been measured on site.</span></label>`,null, data => {
    const item = {id:uid(),name:data.get('name').trim(),width_mm:number(data.get('width_mm')),height_mm:number(data.get('height_mm')),thickness_mm:150,origin_mm:[0,0,0],rotation_deg:0,measurements_confirmed:data.has('confirmed'),photo_asset_id:null,rectified_asset_id:null,photo_quad:null,openings:[]};
    state.project.room.walls.push(item);
    state.wallId = item.id;
    state.analysis = null;
    markDirty();
    render();
  });
}

function editOpening(id, proposedType) {
  const w = wall();
  const existing = w.openings?.find(item => item.id === id);
  const opening = existing || {type:proposedType || 'window',x_mm:0,z_mm:0,width_mm:'',height_mm:'',confirmed:false};
  const types = ['door','window','socket','switch','plumbing','obstruction'];
  modal(existing ? 'Edit opening / service' : 'Add opening / service','Measure from the left edge of this wall (X) and from the floor (Z).',`<div class="fields">${selectField('Type','type',opening.type,types,true)}${metricField('Left position X','x_mm',opening.x_mm,{required:true})}${metricField('Bottom / sill Z','z_mm',opening.z_mm,{required:true})}${metricField('Width','width_mm',opening.width_mm,{min:1,required:true})}${metricField('Height','height_mm',opening.height_mm,{min:1,required:true})}</div><label class="checkline" style="margin-top:20px"><input type="checkbox" name="confirmed" ${opening.confirmed ? 'checked' : ''}><span>I have checked this position and size on site.</span></label>`,null,data => {
    const updated = {id:existing?.id || uid(),type:data.get('type'),x_mm:number(data.get('x_mm')),z_mm:number(data.get('z_mm')),width_mm:number(data.get('width_mm')),height_mm:number(data.get('height_mm')),confirmed:data.has('confirmed')};
    if (updated.x_mm + updated.width_mm > w.width_mm || updated.z_mm + updated.height_mm > w.height_mm) throw new Error('This opening extends beyond the measured wall. Check its position and size.');
    w.openings ||= [];
    if (existing) Object.assign(existing,updated); else w.openings.push(updated);
    markDirty(); render();
  });
}

function designView() {
  const p = state.project;
  const w = wall();
  const cabinets = p.design.cabinets;
  const settings = p.design.settings;
  return `<div class="content-heading"><div><h2>A place for everything.</h2><p>Place cabinets against measured walls. The same dimensions and construction options travel to SketchUp.</p></div><button class="button secondary small" data-action="add-cabinet" ${!w ? 'disabled' : ''}>+ Add cabinet</button></div>
    ${!w ? '<div class="banner">Add a measured wall in Room & measurements before placing cabinets.</div>' : ''}
    <div class="design-layout"><div><section class="card elevation-card"><div class="elevation-toolbar"><select id="design-wall" aria-label="Elevation wall">${p.room.walls.map(item => `<option value="${esc(item.id)}" ${item.id === w?.id ? 'selected' : ''}>${esc(item.name)} · front elevation</option>`).join('')}</select><div class="actions"><label class="toggle"><input type="checkbox" id="toggle-photo" ${state.showPhoto ? 'checked' : ''}>Wall photo</label><label class="toggle"><input type="checkbox" id="toggle-dimensions" ${state.dimensions ? 'checked' : ''}>Dimensions</label></div></div><div id="elevation">${elevation(w)}</div><div class="elevation-footer"><div class="elevation-legend"><span><i class="legend-dot"></i>Cabinet</span><span><i class="legend-dot opening"></i>Opening / service</span></div><span>Measured elevation · click a cabinet to edit</span></div></section>
    <section class="card cabinet-table-card"><div class="card-header"><h3>Cabinet schedule <span class="muted">(${cabinets.length})</span></h3><span class="muted">W × H × D · mm</span></div><div class="table-wrap"><table><thead><tr><th>Part / cabinet</th><th>Wall</th><th>Dimensions</th><th>Connector</th><th></th></tr></thead><tbody>${cabinets.length ? cabinets.map(cabinet => `<tr><td><strong>${esc(cabinet.local_id)}</strong> ${esc(cabinet.name || label(cabinet.type))}<br><small>${esc(label(cabinet.type))} · X ${mm(cabinet.x_mm)} / Z ${mm(cabinet.z_mm)}</small></td><td>${esc(p.room.walls.find(item => item.id === cabinet.wall_id)?.name || 'Unassigned')}</td><td>${mm(cabinet.width_mm)} × ${mm(cabinet.height_mm)} × ${mm(cabinet.depth_mm)}</td><td>${esc(connectorName(cabinet.options?.joinery || settings.joinery))}</td><td><div class="table-actions"><button class="text-button" data-action="edit-cabinet" data-id="${esc(cabinet.id)}">Edit</button><button class="text-button danger" data-action="remove-cabinet" data-id="${esc(cabinet.id)}" aria-label="Remove ${esc(cabinet.local_id)}">×</button></div></td></tr>`).join('') : '<tr><td colspan="5" class="muted">Choose a cabinet from the catalogue to start your layout.</td></tr>'}</tbody></table></div></section>${layoutWarnings(w)}<div class="toolbar-bottom"><p>Front dimensions are finished sizes. Edge band allowances and machining are calculated by the Ruby engine.</p><button class="button" data-action="generate" data-network ${!cabinets.length ? 'disabled' : ''}>Generate parts & BOM →</button></div></div>
    <div class="stack"><section class="card"><div class="card-header"><h3>Construction defaults</h3></div><div class="design-settings"><div class="fields">${selectField('Connector','setting-joinery',settings.joinery || 'minifix',state.catalog.connectors.map(item => [item,connectorName(item)]))}${selectField('Hinge','setting-hinge',settings.hinge || 'cup35_screw',state.catalog.hinges.map(item => [item,label(item)]))}${metricField('Carcass edge','setting-edge',settings.edge ?? 1,{max:2})}${metricField('Front edge','setting-front_edge',settings.front_edge ?? 1,{max:2})}${metricField('End scribe width','accessory-end_scribe_mm',p.design.accessories?.end_scribe_mm || 0,{max:100})}</div><label class="checkline" style="margin-top:15px"><input type="checkbox" id="accessory-worktops" ${p.design.accessories?.worktops?'checked':''}><span>Generate straight-run worktops</span></label><p class="help" style="margin:14px 0 0">Cabinets can override these defaults. Grooved backs and stretchers follow the existing construction rules. End scribe width 0 disables scribes.</p></div></section><section class="card"><div class="card-header"><h3>Cabinet collection</h3><span class="muted">Modern Gola</span></div><div class="catalog-search"><input type="search" id="catalog-search" placeholder="Search tall, oven, spice, open…" aria-label="Search cabinet collection" value="${esc(state.filter)}"></div><div class="catalog-scroll" id="catalog-list">${catalogRows()}</div></section></div></div>`;
}

function connectorName(id) {
  return ({minifix:'Minifix',minifix_dowel:'Minifix + dowel',rafix:'Rafix',screw:'Screw',dowel:'Dowel',ovvo_od830:'OVVO OD830'})[id] || label(id);
}

function catalogRows() {
  const query = state.filter.toLowerCase();
  const matches = state.catalog.cabinets.filter(c => c.type !== 'base_open' && `${c.name} ${c.type} ${c.type === 'base_pullout' ? 'spice bottle' : ''}`.toLowerCase().includes(query));
  return matches.length ? matches.map(c => `<button class="catalog-row" data-action="catalog-add" data-type="${esc(c.type)}" ${!wall() ? 'disabled' : ''}><span class="catalog-thumb" aria-hidden="true">${c.type.startsWith('tall') ? '▥' : c.type.includes('open') ? '☰' : '▤'}</span><span><strong>${esc(c.name || label(c.type))}</strong><small>${mm(c.width_mm)} × ${mm(c.height_mm)} × ${mm(c.depth_mm)} mm</small></span><span class="catalog-add">+</span></button>`).join('') : '<p class="help" style="padding:0 16px 14px">No matching supported cabinets.</p>';
}

function elevation(w) {
  if (!w) return '<div class="empty"><p>Add a wall to see its measured elevation.</p></div>';
  const width = Math.max(number(w.width_mm),100);
  const height = Math.max(number(w.height_mm),100);
  const padX = Math.max(width*.08,220);
  const padY = Math.max(height*.1,220);
  const font = Math.max(width/85,28);
  const stroke = Math.max(width/1000,2.5);
  const baseZ = cabinet => number(cabinet.z_mm) + (/^(wall_|top_)/.test(cabinet.type) ? 0 : 100);
  const cabinets = state.project.design.cabinets.filter(item => item.wall_id === w.id);
  const lines = state.dimensions;
  let svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${-padX} ${-padY} ${width+padX*2} ${height+padY*2}" class="elevation-svg" role="img" aria-label="${esc(w.name)} measured front elevation">`;
  svg += `<defs><pattern id="room-grid" width="100" height="100" patternUnits="userSpaceOnUse"><path d="M 100 0 L 0 0 0 100" fill="none" stroke="#dedfd3" stroke-width="1"/></pattern></defs><rect x="0" y="0" width="${width}" height="${height}" fill="#f7f5ed" stroke="#9da98e" stroke-width="${stroke}"/><rect width="${width}" height="${height}" fill="url(#room-grid)"/>`;
  if (state.showPhoto && w.rectified_asset_id) svg += `<image href="${assetURL(w.rectified_asset_id)}" x="0" y="0" width="${width}" height="${height}" preserveAspectRatio="none" opacity=".7"/>`;
  for (const opening of w.openings || []) {
    const x = number(opening.x_mm), y = height-number(opening.z_mm)-number(opening.height_mm), ow = number(opening.width_mm), oh = number(opening.height_mm);
    svg += `<rect x="${x}" y="${y}" width="${ow}" height="${oh}" fill="#dbc19c" fill-opacity=".35" stroke="#af8855" stroke-width="${stroke*1.4}" ${opening.confirmed ? '' : `stroke-dasharray="${stroke*4} ${stroke*3}"`}/><path d="M${x} ${y}L${x+ow} ${y+oh}M${x+ow} ${y}L${x} ${y+oh}" stroke="#bf9b6a" stroke-width="${stroke*.6}"/><text x="${x+ow/2}" y="${y+oh/2}" text-anchor="middle" font-size="${font*.8}" fill="#8d6b3d">${esc(label(opening.type))}</text>`;
  }
  for (const c of cabinets) {
    const x=number(c.x_mm), h=number(c.height_mm), cw=number(c.width_mm), y=height-baseZ(c)-h;
    const wallUnit = /^(wall_|top_)/.test(c.type);
    const tall = c.type.startsWith('tall');
    svg += `<g data-action="edit-cabinet" data-id="${esc(c.id)}" role="button" tabindex="0" aria-label="Edit ${esc(c.local_id)} ${esc(c.name)}" style="cursor:pointer"><title>${esc(c.local_id)} · ${esc(c.name)} · ${mm(cw)} × ${mm(h)} × ${mm(c.depth_mm)} mm</title><rect x="${x}" y="${y}" width="${cw}" height="${h}" fill="${wallUnit ? '#d8dfcb' : '#eee9da'}" fill-opacity=".94" stroke="#8f9f7e" stroke-width="${stroke*1.3}"/>`;
    const inset = Math.min(9,cw*.02);
    if (c.type.includes('oven') || c.type.includes('micro')) {
      const ovenY = y+h*(tall?.43:.2), ovenH = Math.min(h*.4,590);
      svg += `<rect x="${x+cw*.08}" y="${ovenY}" width="${cw*.84}" height="${ovenH}" rx="6" fill="#4d564e"/><rect x="${x+cw*.13}" y="${ovenY+ovenH*.2}" width="${cw*.74}" height="${ovenH*.65}" fill="#687269"/><line x1="${x+cw*.2}" y1="${ovenY+ovenH*.12}" x2="${x+cw*.8}" y2="${ovenY+ovenH*.12}" stroke="#d5d8cc" stroke-width="${stroke*2}"/>`;
      if (c.type.includes('micro')) svg += `<rect x="${x+cw*.08}" y="${y+h*.2}" width="${cw*.84}" height="${h*.16}" fill="#586058"/><rect x="${x+cw*.14}" y="${y+h*.225}" width="${cw*.64}" height="${h*.1}" fill="#707a6e"/>`;
    } else if (c.type.includes('drawers') || c.type.includes('gola')) {
      const count = number(c.type.match(/drawers_(\d)/)?.[1]) || 3;
      for (let index=1;index<count;index++) svg += `<line x1="${x+inset}" y1="${y+h*index/count}" x2="${x+cw-inset}" y2="${y+h*index/count}" stroke="#839175" stroke-width="${stroke*2}"/>`;
    } else if (c.type.includes('open') || c.type.includes('wine') || c.type.includes('plate')) {
      svg += `<rect x="${x+18}" y="${y+18}" width="${Math.max(cw-36,1)}" height="${Math.max(h-36,1)}" fill="#b6c1a7"/>`;
      for (let index=1;index<3;index++) svg += `<line x1="${x+15}" y1="${y+h*index/3}" x2="${x+cw-15}" y2="${y+h*index/3}" stroke="#e9eddf" stroke-width="18"/>`;
    } else if (c.type.includes('double') || c.type.includes('split')) {
      svg += `<line x1="${x+cw/2}" y1="${y+inset}" x2="${x+cw/2}" y2="${y+h-inset}" stroke="#a2ad92" stroke-width="${stroke}"/>`;
    } else if (c.type.includes('hood')) {
      svg += `<path d="M${x+cw*.2} ${y+h*.65} L${x+cw*.8} ${y+h*.65} L${x+cw*.62} ${y+h*.45} L${x+cw*.62} ${y+h*.2} L${x+cw*.38} ${y+h*.2} L${x+cw*.38} ${y+h*.45} Z" fill="#98a58c"/>`;
    }
    if (!wallUnit && !tall) svg += `<rect x="${x}" y="${y-18}" width="${cw}" height="18" fill="#a3aa91"/>`;
    if (wallUnit && !/hood|open|wine|plate/.test(c.type)) svg += `<line x1="${x}" y1="${y+h-18}" x2="${x+cw}" y2="${y+h-18}" stroke="#687c5d" stroke-width="${stroke*2}"/>`;
    if (tall) svg += `<line x1="${x+inset}" y1="${y+h*.7}" x2="${x+cw-inset}" y2="${y+h*.7}" stroke="#a3ad92" stroke-width="${stroke}"/>`;
    if (c.type.includes('sink')) svg += `<ellipse cx="${x+cw*.5}" cy="${y-11}" rx="${cw*.22}" ry="17" fill="#7d8c7e"/><path d="M${x+cw*.58} ${y-15} v-85 q-30 -45 -55 0 v20" fill="none" stroke="#7a8b7d" stroke-width="${stroke*2}"/>`;
    const textY = /oven|micro/.test(c.type) ? y+h*.92 : y+h*.52;
    svg += `<text x="${x+cw/2}" y="${textY}" text-anchor="middle" font-size="${font*.9}" font-weight="600" fill="#46603e">${esc(c.local_id)}</text>`;
    if (lines) svg += `<text x="${x+cw/2}" y="${textY+font*2.25}" text-anchor="middle" font-size="${font*.53}" fill="#748469">${mm(cw)} × ${mm(h)} × ${mm(c.depth_mm)}</text>`;
    if (cw > 380) svg += `<text x="${x+cw/2}" y="${textY+font*1.2}" text-anchor="middle" font-size="${font*.6}" fill="#6f7f63">${esc((c.name || label(c.type)).slice(0,26))}</text>`;
    svg += '</g>';
    if (lines) {
      const dimensionY = wallUnit ? y-55 : height+65;
      svg += `<path d="M${x} ${dimensionY-15}v30M${x+cw} ${dimensionY-15}v30M${x} ${dimensionY}H${x+cw}" fill="none" stroke="#a3ac97" stroke-width="${stroke*.6}"/><text x="${x+cw/2}" y="${dimensionY-9}" text-anchor="middle" font-size="${font*.7}" fill="#7c8b6e">${mm(cw)}</text>`;
    }
  }
  svg += `<line x1="${-padX*.25}" y1="${height}" x2="${width+padX*.25}" y2="${height}" stroke="#9caa90" stroke-width="${stroke*2}"/>`;
  if (lines) {
    const dy = -padY*.55, dx=-padX*.48;
    svg += `<path d="M0 ${dy-15}v30M${width} ${dy-15}v30M0 ${dy}H${width}M${dx-15} 0h30M${dx-15} ${height}h30M${dx} 0V${height}" fill="none" stroke="#8b9b7b" stroke-width="${stroke}"/><text x="${width/2}" y="${dy-18}" text-anchor="middle" font-size="${font}" fill="#5b7050">${mm(width)} mm</text><text x="${dx-15}" y="${height/2}" text-anchor="middle" transform="rotate(-90 ${dx-15} ${height/2})" font-size="${font}" fill="#5b7050">${mm(height)} mm</text>`;
  }
  return svg+'</svg>';
}

function layoutWarnings(w) {
  if (!w) return '';
  const warnings = [];
  const cabinets = state.project.design.cabinets.filter(c => c.wall_id === w.id);
  if (!w.measurements_confirmed) warnings.push('Wall dimensions are unconfirmed. Check them on site before manufacturing.');
  for (const cabinet of cabinets) {
    const z=number(cabinet.z_mm)+(/^(wall_|top_)/.test(cabinet.type)?0:100);
    if (number(cabinet.x_mm)<0 || number(cabinet.x_mm)+number(cabinet.width_mm)>number(w.width_mm) || z+number(cabinet.height_mm)>number(w.height_mm)) warnings.push(`${cabinet.local_id} extends beyond this measured wall.`);
  }
  return warnings.length ? `<div class="banner" style="margin-top:15px">${warnings.map(esc).join('<br>')}</div>` : '';
}

function editCabinet(id, requestedType) {
  if (!wall()) return toast('Add a measured wall first.',true);
  const p = state.project;
  const existing = p.design.cabinets.find(c => c.id === id);
  const types = state.catalog.cabinets.filter(c => c.type !== 'base_open');
  if (!types.length) return toast('The supported cabinet catalogue is unavailable.',true);
  const recipe = types.find(c => c.type === requestedType) || types[0];
  const isWall = /^(wall_|top_)/.test(recipe.type);
  const x = Math.max(0,...p.design.cabinets.filter(c=>c.wall_id===state.wallId && /^(wall_|top_)/.test(c.type)===isWall).map(c=>number(c.x_mm)+number(c.width_mm)));
  const prefix=isWall?'W':'B';
  let next=1; while(p.design.cabinets.some(c=>c.local_id === `${prefix}${String(next).padStart(2,'0')}`)) next++;
  const cabinet = existing || {local_id:`${prefix}${String(next).padStart(2,'0')}`,name:recipe.name,type:recipe.type,wall_id:state.wallId,width_mm:recipe.width_mm,height_mm:recipe.height_mm,depth_mm:recipe.depth_mm,x_mm:x,y_mm:0,z_mm:isWall?1400:0,rotation_deg:0,options:{}};
  const options = cabinet.options || {};
  const settings = p.design.settings;
  const dialog = modal(existing ? `Edit ${cabinet.local_id}` : 'Add a cabinet','Dimensions are in millimetres. Per-cabinet construction options override project defaults.',`<div class="fields">${field('Cabinet number','local_id',cabinet.local_id,{required:true})}${field('Name','name',cabinet.name,{required:true})}${selectField('Cabinet type','type',cabinet.type,types.map(c=>[c.type,c.name]),true)}${selectField('Wall','wall_id',cabinet.wall_id,p.room.walls.map(w=>[w.id,w.name]),true)}${metricField('Width','width_mm',cabinet.width_mm,{min:250,max:1200,required:true})}${metricField('Height','height_mm',cabinet.height_mm,{min:300,max:2600,required:true})}${metricField('Depth','depth_mm',cabinet.depth_mm,{min:250,max:900,required:true})}${metricField('Left X','x_mm',cabinet.x_mm,{min:0,required:true})}${metricField('Depth offset Y','y_mm',cabinet.y_mm || 0,{min:-10000})}${metricField('Bottom Z / wall input','z_mm',cabinet.z_mm || 0,{min:0})}${selectField('Connector','joinery',options.joinery || '',[['',`Project default (${connectorName(settings.joinery)})`],...state.catalog.connectors.map(item=>[item,connectorName(item)])])}${selectField('Hinge','hinge',options.hinge || '',[['','Project default'],...state.catalog.hinges.map(item=>[item,label(item)])])}${selectField('Worktop role','role',options.role || 'standard',[['standard','Standard cabinet'],['hob','Hob / cooktop position']],true)}${metricField('Carcass edge band','edge',options.edge ?? '',{max:2})}${metricField('Front edge band','front_edge',options.front_edge ?? '',{max:2})}</div><p class="help" style="margin:15px 0 0">Leave edge band fields empty to use project defaults. Base and tall units sit on the engine’s 100 mm plinth; upper Z is the direct engine placement. Tall and hood units do not get an upper finger-pull profile.</p>`,null,data => {
    const local_id=data.get('local_id').trim();
    if (!local_id || !/^[BW][0-9]{2,4}$/.test(local_id)) throw new Error('Use B01/B001 for base or tall units, and W01/W001 for upper units.');
    if(p.design.cabinets.some(c=>c.id!==existing?.id && c.local_id===local_id)) throw new Error('Cabinet numbers must be unique in this project.');
    if (!local_id.startsWith(data.get('type').startsWith('wall_')?'W':'B')) throw new Error('Use W numbering for upper cabinets and B numbering for base or tall cabinets.');
    const updated = {...existing,id:existing?.id || uid(),local_id,name:data.get('name').trim(),type:data.get('type'),wall_id:data.get('wall_id'),rotation_deg:existing?.rotation_deg || 0,options:{...options}};
    for(const key of ['width_mm','height_mm','depth_mm','x_mm','y_mm','z_mm']) updated[key]=number(data.get(key));
    for(const key of ['joinery','hinge','edge','front_edge','role']) {
      const value=data.get(key);
      if(value==='') delete updated.options[key]; else updated.options[key]=['edge','front_edge'].includes(key)?number(value):value;
    }
    if(existing) Object.assign(existing,updated); else p.design.cabinets.push(updated);
    state.wallId=updated.wall_id;
    markDirty(); render();
  });
  if(!existing) $('#f-type',dialog).addEventListener('change',event=>{
    const selected=types.find(c=>c.type===event.target.value);
    if(!selected) return;
    for(const key of ['width_mm','height_mm','depth_mm']) $(`#f-${key}`,dialog).value=selected[key];
    $('#f-name',dialog).value=selected.name;
    $('#f-z_mm',dialog).value=/^(wall_|top_)/.test(selected.type)?1400:0;
  });
}

function bomView() {
  const b=state.bom, q=state.quote, p=state.project;
  const current=(b?.status || p.manufacturing?.status)==='current' && !state.dirty;
  const parts=b?.parts || [];
  const totals=b?.totals || {};
  const rates=p.quote.rates;
  const qty=parts.length;
  const boardArea=totals.panel_area_m2 ?? totals.board_m2 ?? totals.board_area_m2 ?? parts.filter(part=>!String(part.material).toLowerCase().includes('back')).reduce((total,part)=>total+number(part.w)*number(part.h)/1e6,0);
  const band=totals.band_length_m ?? totals.band_m ?? totals.edgeband_m ?? totals.edgeband_length_m ?? null;
  const amount=q?.total ?? q?.grand_total ?? q?.totals?.total ?? q?.totals?.grand_total ?? null;
  const missing=q?.missing_rates || [];
  const unpriced=!q || q.status==='unpriced' || missing.length>0 || amount===null;
  return `<div class="content-heading"><div><h2>From design to workshop.</h2><p>Parts, machining and edge bands use the saved Ruby manufacturing model. Your rates turn that BOM into a quote.</p></div><button class="button secondary small" data-action="generate" data-network ${!p.design.cabinets.length?'disabled':''}>↻ Generate parts</button></div>
    ${state.dirty?'<div class="banner">Save this project to refresh the BOM and quote for the current dimensions.</div>':!current?'<div class="banner">The manufacturing result is missing or stale. Generate parts before using this BOM or quote for production.</div>':''}
    <div class="stat-grid"><div class="stat"><div class="stat-label">Cabinets</div><div class="stat-value">${p.design.cabinets.length}</div><div class="stat-foot">In your shared project</div></div><div class="stat"><div class="stat-label">Board parts</div><div class="stat-value">${b?qty:'—'}</div><div class="stat-foot">${current?'Current manufacturing model':'Needs a current generated BOM'}</div></div><div class="stat"><div class="stat-label">Panel area</div><div class="stat-value">${b?number(boardArea).toFixed(2):'—'} <span style="font-size:12px">m²</span></div><div class="stat-foot">${current?'From generated part dimensions':'Saved result, if available'}</div></div><div class="stat"><div class="stat-label">Edge band</div><div class="stat-value">${band===null?'—':number(band).toFixed(2)} <span style="font-size:12px">m</span></div><div class="stat-foot">Applicable sides and thickness</div></div></div>
    <div class="bom-layout"><div><section class="card"><div class="card-header"><h3>Bill of materials</h3><div class="actions"><button class="text-button" data-action="download" data-file="bom.csv" data-network>↓ CSV</button><button class="text-button" data-action="download" data-file="print" data-network>Print / PDF</button></div></div><div class="table-wrap"><table><thead><tr><th>Part / name</th><th>Cabinet</th><th>Cut size · mm</th><th>Material</th><th>Edge band</th><th>Machining</th></tr></thead><tbody>${parts.length?parts.map(part=>`<tr><td><strong>${esc(part.number || part.id)}</strong><br><small>${esc(part.name)}</small></td><td>${esc(part.cabinet_id)}</td><td>${mm(part.w)} × ${mm(part.h)} × ${mm(part.t)}<br><small>Finished ${mm(part.finished_w ?? part.w)} × ${mm(part.finished_h ?? part.h)}</small></td><td>${esc(typeof part.material==='object'?part.material.name || JSON.stringify(part.material):part.material)}</td><td>${esc(edgeSummary(part.edges))}</td><td>${esc(operationSummary(part.operations))}</td></tr>`).join(''):`<tr><td colspan="6"><div class="empty"><p>${state.dirty?'Save your changes, then load the current BOM.':b?'No production parts yet. Generate parts from your cabinets.':'Loading saved bill of materials…'}</p>${state.dirty?'<button class="button small" data-action="refresh-bom" data-network>Save & refresh BOM</button>':''}</div></td></tr>`}</tbody></table></div><div class="inline-note">${current?'Current generated data':'Saved / ungenerated data'} · Source revision ${esc(b?.source_revision ?? '—')}. CUT, DRILL, POCKET and GROOVE machining stays in separate export layers in the SketchUp manufacturing workflow.</div></section>
    ${b?.hardware?.length?`<section class="card" style="margin-top:18px"><div class="card-header"><h3>Hardware</h3></div><div class="table-wrap"><table><thead><tr><th>Item</th><th>Quantity</th></tr></thead><tbody>${b.hardware.map(item=>`<tr><td>${esc(item.name || item.item || item.type || item.id)}</td><td>${mm(item.qty ?? item.quantity ?? item.count)}</td></tr>`).join('')}</tbody></table></div></section>`:''}</div>
    <aside class="card quote-card"><div class="quote-total"><small>PROJECT ESTIMATE · ${esc(p.quote.currency || 'LKR')}</small><strong>${unpriced?'Not fully priced':`${esc(p.quote.currency)} ${money(amount)}`}</strong><p>${!current?'Requires current manufacturing data':unpriced?'Add your material and hardware rates below':'Based on your saved rates and generated BOM'}</p></div><div class="card-pad">${q?.lines?.length && !state.dirty ? `<div style="margin-bottom:20px">${q.lines.map(line=>`<div class="quote-line"><span>${esc(line.description)}</span><strong>${money(line.amount)}</strong></div>`).join('')}<div class="quote-line"><span>Labour</span><span>${money(q.labour)}</span></div><div class="quote-line"><span>Markup</span><span>${money(q.markup)}</span></div><div class="quote-line"><span>Tax</span><span>${money(q.tax)}</span></div><div class="quote-line total"><span>Total ${esc(q.currency)}</span><span>${money(q.total)}</span></div></div>` : ''}<div class="fields" style="margin-bottom:18px">${field('Currency','quote-currency',p.quote.currency || 'LKR',{full:true})}</div><div class="mini-heading">YOUR RATES</div>${[['board_per_m2','Carcass board / m²'],['front_per_m2','Front board / m²'],['back_per_m2','Back panel / m²'],['worktop_per_m2','Worktop / m²'],['profile_per_m','Gola profile / m'],['band_per_m','Edge band / m'],['hardware_each','Hardware / item']].map(([key,name])=>`<div class="rate-row"><label for="rate-${key}">${esc(name)}</label><input id="rate-${key}" type="number" min="0" step="any" data-rate="${key}" value="${esc(rates[key] ?? 0)}"></div>`).join('')}<hr class="separator">${[['labour','Labour'],['markup_pct','Markup %'],['tax_pct','Tax %']].map(([key,name])=>`<div class="rate-row"><label for="quote-${key}">${name}</label><input id="quote-${key}" type="number" min="0" step="any" data-quote="${key}" value="${esc(p.quote[key] ?? 0)}"></div>`).join('')}<p class="quote-label">${missing.length?`Missing rates: ${missing.map(item=>esc(label(item))).join(', ')}.`:'Zero rates are treated as missing when the BOM needs that material.'} Save rates to recalculate the estimate.</p><div class="actions" style="margin-top:18px"><button class="button small" data-action="refresh-bom" data-network>Save & recalculate</button><button class="button secondary small" data-action="download" data-file="quote.csv" data-network>↓ Quote CSV</button></div></div></aside></div>`;
}

function edgeSummary(edges) {
  if(!edges) return '—';
  if(Array.isArray(edges)) return edges.map(value=>typeof value==='string'?value:JSON.stringify(value)).join(', ') || '—';
  return Object.entries(edges).filter(([,value])=>value && number(value)!==0).map(([side,value])=>`${side} ${typeof value==='number'?value+' mm':typeof value==='string'?value:JSON.stringify(value)}`).join(' · ') || '—';
}

function operationSummary(operations) {
  if(!Array.isArray(operations)||!operations.length) return '—';
  const counts={};
  for(const operation of operations){const type=operation.kind || operation.type || operation.operation || 'operation'; counts[type]=(counts[type] || 0)+1;}
  return Object.entries(counts).map(([type,count])=>`${label(type)} ${count}`).join(' · ');
}

async function loadBom() {
  if(state.dirty) return;
  const id=state.project.id;
  const results=await Promise.allSettled([api(projectPath('/bom')),api(projectPath('/quote'))]);
  if(state.project?.id!==id) return;
  if(results[0].status==='fulfilled') state.bom=results[0].value; else handleError(results[0].reason);
  if(results[1].status==='fulfilled') state.quote=results[1].value; else handleError(results[1].reason);
  if(state.tab==='bom') render();
}

async function fileBase64(file) {
  return await new Promise((resolve,reject)=>{
    const reader=new FileReader();
    reader.onload=()=>resolve(String(reader.result).split(',')[1]);
    reader.onerror=()=>reject(new Error('This image could not be read.'));
    reader.readAsDataURL(file);
  });
}

async function uploadPhoto(file) {
  if(!file) return;
  if(file.size>12*1024*1024) return toast('Choose an image no larger than 12 MB.',true);
  if(!['image/jpeg','image/png','image/webp'].includes(file.type)) return toast('Choose a JPG, PNG or WebP image.',true);
  const wallId=wall().id;
  await task(async()=>{
    if(!await unsavedGuard()) return;
    const result=await api(projectPath('/photos'),{method:'POST',body:JSON.stringify({base_revision:state.project.revision,wall_id:wallId,filename:file.name,data_base64:await fileBase64(file)})});
    acceptProject(result.project);
    state.photoMode='original';
    render();
    await refreshProjects();
    toast('Original wall photo saved. Select its four wall corners.');
  });
}

function drawPhotoPoints() {
  const img=$('#wall-photo'), overlay=$('#photo-overlay');
  if(!img || !overlay || !img.naturalWidth || state.photoMode!=='original') return;
  const points=wall()?.photo_quad || [];
  const radius=Math.max(img.naturalWidth/65,12);
  overlay.setAttribute('viewBox',`0 0 ${img.naturalWidth} ${img.naturalHeight}`);
  overlay.innerHTML=`${points.length>1?`<${points.length===4?'polygon':'polyline'} points="${points.map(point=>`${number(point[0])},${number(point[1])}`).join(' ')}" fill="${points.length===4?'#173d3222':'none'}" stroke="#e3b66f" stroke-width="${radius*.18}"/>`:''}${points.map((point,index)=>`<circle cx="${number(point[0])}" cy="${number(point[1])}" r="${radius}" fill="#173d32" stroke="#fff8e9" stroke-width="${radius*.13}"/><text x="${number(point[0])}" y="${number(point[1])+radius*.33}" fill="#fff8e9" font-size="${radius}" text-anchor="middle" font-weight="600">${index+1}</text>`).join('')}`;
}

document.addEventListener('load',event=>{if(event.target.id==='wall-photo') drawPhotoPoints();},true);

function sketchupInstructions() {
  const p=state.project;
  const body=`<div class="step-row"><span class="step-number">1</span><p>Start this web service, then load the LuxKTC app in SketchUp’s Ruby Console. Replace the path below with your installed LuxKTC folder.</p></div><pre class="code-box">load 'C:/path/to/LuxKTC/app/aj_board_kitchen.rb'</pre><div class="step-row"><span class="step-number">2</span><p>Use <strong>Extensions → LuxKTC shared project → Configure local server</strong>, then <strong>Pull shared project</strong>. Choose this project to build its walls, photo textures and kitchen.</p></div><pre class="code-box">Server: ${esc(location.origin)}\nProject ID: ${esc(p.id)}</pre><div class="step-row"><span class="step-number">3</span><p>Edit dimensions or construction options in SketchUp, then push the changes. Refresh this project to see its new revision and BOM.</p></div><p class="help">Save the browser project before pulling it into SketchUp. Conflicts ask you to reconcile revisions; they never silently overwrite another client’s work.</p>`;
  modal('The same project in SketchUp','The web interface and SketchUp share one API and project revision.',body,'<button class="button secondary" type="button" data-close>Close</button><button class="button" type="submit">Copy project ID</button>',async()=>{
    try {await navigator.clipboard.writeText(p.id);toast('Project ID copied.');} catch {toast(`Project ID: ${p.id}`);}
    return false;
  });
}

async function action(name,button) {
  if (state.busy) return;
  if(name==='new-project') return newProject();
  if(name==='open-project') return await openProject(button.dataset.id);
  if(!state.project) return;
  const w=wall();
  if(name==='save') return await task(async()=>{if(await saveProject()) {toast('Project saved.');if(state.tab==='bom') await loadBom();}});
  if(name==='tab') {state.tab=button.dataset.tab;render();if(state.tab==='bom'&&!state.dirty&&!state.bom) await task(loadBom);return;}
  if(name==='select-wall') {state.wallId=button.dataset.id;state.analysis=wall()?.analysis || wall()?.ai_analysis || null;state.photoMode='original';render();return;}
  if(name==='edit-project') return modal('Project details','Names and quote settings use the same shared project.',`<div class="fields">${field('Project name','name',state.project.name,{full:true,required:true})}${field('Client / reference','client',state.project.client,{full:true})}</div>`,null,data=>{state.project.name=data.get('name').trim();state.project.client=data.get('client').trim();markDirty();render();});
  if(name==='delete-project') return await task(async()=>{if(!await unsavedGuard())return;if(!confirm(`Delete “${state.project.name}”? This removes the shared project from both clients.`))return;await api(projectPath(`?base_revision=${state.project.revision}`),{method:'DELETE'});state.project=null;state.dirty=false;await refreshProjects();render();toast('Project deleted.');});
  if(name==='reload-server') return await task(async()=>{if(state.dirty&&!confirm('Discard your local edits and load the server copy? Download your edits first if you need them.'))return;acceptProject(await api(projectPath()));await refreshProjects();render();if(state.tab==='bom')await loadBom();});
  if(name==='export-draft') {const blob=new Blob([JSON.stringify(state.project,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=`LuxKTC-local-edits-${state.project.id}.json`;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);return;}
  if(name==='add-wall') return addWall();
  if(name==='remove-wall') {if(!w)return;const count=state.project.design.cabinets.filter(c=>c.wall_id===w.id).length;if(!confirm(`Remove “${w.name}”${count?` and its ${count} assigned cabinet(s)`:''}?`))return;state.project.room.walls=state.project.room.walls.filter(item=>item.id!==w.id);state.project.design.cabinets=state.project.design.cabinets.filter(c=>c.wall_id!==w.id);state.wallId=state.project.room.walls[0]?.id || null;state.analysis=null;markDirty();render();return;}
  if(name==='add-opening') return editOpening();
  if(name==='edit-opening') return editOpening(button.dataset.id);
  if(name==='remove-opening') {w.openings=w.openings.filter(item=>item.id!==button.dataset.id);markDirty();render();return;}
  if(name==='photo-mode') {state.photoMode=button.dataset.mode;render();return;}
  if(name==='undo-quad') {w.photo_quad=(w.photo_quad || []).slice(0,-1);markDirty();render();return;}
  if(name==='reset-quad') {w.photo_quad=[];markDirty();render();return;}
  if(name==='apply-ai-quad') {const img=$('#wall-photo');const iw=w.photo_width_px || (state.photoMode==='original'?img?.naturalWidth:0),ih=w.photo_height_px || (state.photoMode==='original'?img?.naturalHeight:0);if(!iw||!ih)return toast('Switch to the original image and wait for it to load.',true);w.photo_quad=state.analysis.wall_quad.map(point=>[Math.round(number(point[0])*iw),Math.round(number(point[1])*ih)]);state.photoMode='original';markDirty();render();toast('Proposed corners applied. Check all four points before correcting perspective.');return;}
  if(name==='measure-detection') {const detection=state.analysis?.detections?.[number(button.dataset.index)];return editOpening(null,['door','window','socket','switch','plumbing','obstruction'].includes(detection?.type)?detection.type:'obstruction');}
  if(name==='rectify') return await task(async()=>{const wallId=w.id;if(!w.measurements_confirmed)return toast('Confirm this wall’s on-site width and height first.',true);if(w.photo_quad?.length!==4)return toast('Select all four wall corners first.',true);if(!await unsavedGuard())return;const measured=wall();if(measured.id!==wallId)return;acceptProject(await api(projectPath('/rectify'),{method:'POST',body:JSON.stringify({base_revision:state.project.revision,wall_id:measured.id,quad:measured.photo_quad,width_mm:measured.width_mm,height_mm:measured.height_mm})}));state.photoMode='rectified';await refreshProjects();render();toast('Perspective corrected. The original image is preserved.');});
  if(name==='analyze') return await task(async()=>{if(!state.health?.ai?.configured)return toast('The service has no configured OpenAI key. Keep the key in the server .env file and restart the service.',true);const wallId=w.id;if(!await unsavedGuard())return;toast('Reviewing this photo. Real measurements still need your confirmation.');const result=await api(projectPath('/analyze'),{method:'POST',body:JSON.stringify({base_revision:state.project.revision,wall_id:wallId})});acceptProject(result.project);state.analysis=result.analysis;await refreshProjects();render();toast('Photo review ready. Check the questions and proposed corners.');});
  if(name==='add-cabinet') return editCabinet();
  if(name==='catalog-add') return editCabinet(null,button.dataset.type);
  if(name==='edit-cabinet') return editCabinet(button.dataset.id);
  if(name==='remove-cabinet') {state.project.design.cabinets=state.project.design.cabinets.filter(c=>c.id!==button.dataset.id);markDirty();render();return;}
  if(name==='generate') return await task(async()=>{if(!await unsavedGuard())return;toast('Generating parts with the existing Ruby engine…');acceptProject(await api(projectPath('/generate'),{method:'POST',body:JSON.stringify({base_revision:state.project.revision})}));await refreshProjects();state.tab='bom';render();await loadBom();toast('Parts and BOM generated from the saved kitchen.');});
  if(name==='refresh-bom') return await task(async()=>{if(!await saveProject())return;await loadBom();toast('Saved rates and manufacturing data refreshed.');});
  if(name==='download') return await task(async()=>{if(!await unsavedGuard())return;const url=projectPath('/'+button.dataset.file);if(button.dataset.file==='print'){window.open(url,'_blank','noopener');return;}const link=document.createElement('a');link.href=url;link.download='';document.body.append(link);link.click();link.remove();});
  if(name==='sketchup') return sketchupInstructions();
}

document.addEventListener('click',event=>{
  if (state.busy) return;
  const button=event.target.closest('[data-action]');
  if(button){void action(button.dataset.action,button);return;}
  const img=event.target.closest('#wall-photo');
  if(img&&state.photoMode==='original'&&img.naturalWidth){const w=wall();if(!w)return;w.photo_quad ||= [];if(w.photo_quad.length>=4)return toast('All four corners are selected. Use Undo or Reset to change them.');const rect=img.getBoundingClientRect();w.photo_quad.push([Math.round((event.clientX-rect.left)*img.naturalWidth/rect.width),Math.round((event.clientY-rect.top)*img.naturalHeight/rect.height)]);markDirty();render();}
});

document.addEventListener('keydown',event=>{if(['Enter',' '].includes(event.key)&&event.target.matches('svg [data-action]')){event.preventDefault();void action(event.target.dataset.action,event.target);}});

document.addEventListener('input',event=>{
  if (state.busy) return;
  const target=event.target;
  if(target.id==='catalog-search'){state.filter=target.value;$('#catalog-list').innerHTML=catalogRows();return;}
  if(!state.project)return;
  if(target.name?.startsWith('wall-')){
    const w=wall();if(!w)return;
    const key=target.name.slice(5);
    if(key.startsWith('origin_')){w.origin_mm ||= [0,0,0];w.origin_mm[number(key.slice(7))]=number(target.value);}
    else w[key]=key==='name'?target.value:number(target.value);
    if(['width_mm','height_mm'].includes(key)){w.measurements_confirmed=false;const confirmed=$('#wall-confirmed');if(confirmed)confirmed.checked=false;}
    markDirty();return;
  }
  if(target.name?.startsWith('setting-')){const key=target.name.slice(8);state.project.design.settings[key]=['edge','front_edge'].includes(key)?number(target.value):target.value;markDirty();return;}
  if(target.name==='accessory-end_scribe_mm'){state.project.design.accessories ||= {worktops:false,end_scribe_mm:0};state.project.design.accessories.end_scribe_mm=number(target.value);markDirty();return;}
  if(target.dataset.rate){state.project.quote.rates[target.dataset.rate]=number(target.value);markDirty();return;}
  if(target.dataset.quote){state.project.quote[target.dataset.quote]=number(target.value);markDirty();return;}
  if(target.name==='quote-currency'){state.project.quote.currency=target.value.toUpperCase().slice(0,3);markDirty();}
});

document.addEventListener('change',event=>{
  if (state.busy) return;
  const target=event.target;
  if(target.id==='photo-upload'){void uploadPhoto(target.files?.[0]);return;}
  if(target.id==='accessory-worktops'){state.project.design.accessories ||= {worktops:false,end_scribe_mm:0};state.project.design.accessories.worktops=target.checked;markDirty();return;}
  if(target.id==='wall-confirmed'){wall().measurements_confirmed=target.checked;markDirty();return;}
  if(target.id==='design-wall'){state.wallId=target.value;state.analysis=wall()?.analysis || null;render();return;}
  if(target.id==='toggle-dimensions'){state.dimensions=target.checked;$('#elevation').innerHTML=elevation(wall());return;}
  if(target.id==='toggle-photo'){state.showPhoto=target.checked;$('#elevation').innerHTML=elevation(wall());}
});

window.addEventListener('beforeunload',event=>{if(state.dirty){event.preventDefault();event.returnValue='';}});
$('#new-project').onclick=newProject;
$('#refresh-projects').onclick=()=>void task(async()=>{if(!await unsavedGuard())return;await refreshProjects();if(state.project)acceptProject(await api(projectPath()));render();if(state.tab==='bom')await loadBom();});

// Watch only revisions; unchanged projects do not download their part snapshots.
// New SketchUp edits refresh automatically when this browser has no local edits.
async function checkRemoteRevision() {
  if (state.busy || document.visibilityState === 'hidden' || $('#modal')?.open) return;
  const selectedId=state.project?.id;
  try {
    const result=await api('/api/projects');
    if (state.busy || state.project?.id!==selectedId) return;
    state.projects=Array.isArray(result)?result:result.projects || [];
    renderProjects();
    const remote=state.projects.find(item=>item.id===selectedId);
    if (!remote || remote.revision<=state.project.revision) return;
    if (state.dirty) {
      if (state.remoteRevision!==remote.revision) toast(`SketchUp or another browser saved revision ${remote.revision}. Your local changes are kept; saving will check for conflicts.`,true);
      state.remoteRevision=remote.revision;
      updateStatus();
      return;
    }
    await task(async()=>{
      acceptProject(await api(projectPath()));
      render();
      if(state.tab==='bom') await loadBom();
      toast('Updated from the shared project.');
    });
  } catch { /* A temporary offline service must not erase or interrupt a draft. */ }
}

async function init() {
  render();
  const results=await Promise.allSettled([api('/api/health'),api('/api/catalog'),api('/api/projects')]);
  if(results[0].status==='fulfilled'){
    state.health=results[0].value;
    $('#service-dot').classList.add('online');
    $('#service-status').textContent='Shared studio online';
  }else{
    state.error='The LuxKTC service is unavailable. Start the local web service, then refresh this page.';
    $('#service-dot').classList.add('offline');$('#service-status').textContent='Service unavailable';
  }
  if(results[1].status==='fulfilled'){
    const c=results[1].value;
    state.catalog={...c,cabinets:c.cabinets || c.cabinet_types || [],connectors:c.connectors || [],hinges:c.hinges || []};
  }else state.error=results[1].reason.message;
  if(results[2].status==='fulfilled'){
    state.projects=Array.isArray(results[2].value)?results[2].value:results[2].value.projects || [];
  }
  renderProjects();render();
  const requested=new URLSearchParams(location.search).get('project');
  if(requested)await openProject(requested);
  setInterval(()=>void checkRemoteRevision(),15000);
}
void init();
