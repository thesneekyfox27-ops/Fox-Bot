const panel  = document.getElementById('panel');
const grid   = document.getElementById('floorGrid');
const nameEl = document.getElementById('elevName');

const resource = (typeof GetParentResourceName === 'function')
  ? GetParentResourceName()
  : 'nrp-elevators';

function post(cb, data) {
  fetch(`https://${resource}/${cb}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data || {}),
  }).catch(() => {});
}

function hexToRgb(hex) {
  const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || '');
  if (!m) return { r: 71, g: 199, b: 212 };
  return { r: parseInt(m[1], 16), g: parseInt(m[2], 16), b: parseInt(m[3], 16) };
}

function applyTheme(color) {
  const c = hexToRgb(color);
  const s = document.documentElement.style;
  s.setProperty('--accent', color || '#47c7d4');
  [12, 15, 35, 40, 50, 60, 80].forEach(a => {
    s.setProperty('--accent-' + a, `rgba(${c.r},${c.g},${c.b},.${a})`);
  });
}

function applyPosition(pos) {
  panel.classList.remove('pos-left', 'pos-center', 'pos-right');
  panel.classList.add('pos-' + (pos || 'right'));
}

function openPanel(d) {
  applyTheme(d.color);
  applyPosition(d.position);
  document.body.classList.toggle('no-here-tag', d.showHereTag === false);

  const logo = document.getElementById('panelLogo');
  if (d.logo) {
    logo.src = d.logo;
    logo.classList.remove('hidden');
  } else {
    logo.classList.add('hidden');
  }

  nameEl.textContent = (d.name || 'ELEVATOR').toUpperCase();
  grid.innerHTML = '';

  let floors = d.floors || [];
  if (d.topFloorFirst !== false) floors = [...floors].reverse();

  floors.forEach(f => {
    const btn = document.createElement('button');
    btn.className = 'floor-btn';
    if (f.current) btn.classList.add('current');
    if (f.locked)  btn.classList.add('locked');

    const led = document.createElement('div');
    led.className = 'led';
    led.textContent = f.locked ? '\u2715' : f.index;

    const lbl = document.createElement('div');
    lbl.className = 'lbl';
    lbl.textContent = f.label;

    btn.appendChild(led);
    btn.appendChild(lbl);

    if (!f.current && !f.locked) {
      btn.addEventListener('click', () => post('selectFloor', { index: f.index }));
    }

    grid.appendChild(btn);
  });

  panel.classList.remove('hidden');
}

function closePanel() {
  panel.classList.add('hidden');
}

/* ---------- travel HUD ---------- */
const travel      = document.getElementById('travel');
const travelName  = document.getElementById('travelName');
const travelDest  = document.getElementById('travelDest');
const travelArrow = document.getElementById('travelArrow');
const travelNum   = document.getElementById('travelFloorNum');
const travelLbl   = document.getElementById('travelFloorLbl');
const travelDots  = document.getElementById('travelDots');

let travelLabels = [];
let travelTo = 1;

function travelStart(d) {
  applyTheme(d.color);
  travelLabels = d.labels || [];
  travelTo = d.to;

  travelName.textContent = (d.name || 'ELEVATOR').toUpperCase();
  travelDest.textContent = '→ ' + (travelLabels[d.to - 1] || ('Floor ' + d.to)).toUpperCase();

  const goingUp = d.to > d.from;
  travelArrow.classList.toggle('down', !goingUp);

  travelDots.innerHTML = '';
  for (let i = 1; i <= travelLabels.length; i++) {
    const dot = document.createElement('div');
    dot.className = 'dot';
    dot.dataset.floor = i;
    if (i === d.from) dot.classList.add('active');
    if (i === d.to)   dot.classList.add('dest');
    travelDots.appendChild(dot);
  }

  setTravelFloor(d.from);
  travel.classList.remove('hidden');
}

function setTravelFloor(floor) {
  travelNum.textContent = floor;
  travelLbl.textContent = travelLabels[floor - 1] || ('Floor ' + floor);

  travelNum.classList.remove('tick');
  void travelNum.offsetWidth; // restart animation
  travelNum.classList.add('tick');

  travelDots.querySelectorAll('.dot').forEach(dot => {
    dot.classList.toggle('active', Number(dot.dataset.floor) === floor);
  });
}

function travelEnd() {
  travel.classList.add('hidden');
}

/* ---------- audio ---------- */
const activeSounds = {};

function playSoundFile(d) {
  if (!d.file) return;
  if (d.id && activeSounds[d.id]) {
    activeSounds[d.id].pause();
    delete activeSounds[d.id];
  }
  const a = new Audio('sounds/' + d.file);
  a.volume = Math.max(0, Math.min(1, d.volume ?? 1));
  a.loop = !!d.loop;
  a.play().catch(() => {});
  if (d.id) {
    activeSounds[d.id] = a;
  }
}

function stopSoundFile(id) {
  const a = activeSounds[id];
  if (a) {
    a.pause();
    delete activeSounds[id];
  }
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open')        openPanel(d);
  if (d.action === 'close')       closePanel();
  if (d.action === 'travelStart') travelStart(d);
  if (d.action === 'travelStep')  setTravelFloor(d.floor);
  if (d.action === 'travelEnd')   travelEnd();
  if (d.action === 'playSound')   playSoundFile(d);
  if (d.action === 'stopSound')   stopSoundFile(d.id);
  if (d.action === 'adminOpen')   adminOpenView(d);
  if (d.action === 'adminData')   adminSetData(d.elevators);
});

document.getElementById('closeBtn').addEventListener('click', () => post('close'));

window.addEventListener('keydown', (e) => {
  const typing = ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName);
  if (e.key === 'Escape') {
    if (typeof A !== 'undefined' && A.open) closeAdmin();
    else post('close');
  } else if (e.key === 'Backspace' && !typing) {
    if (typeof A !== 'undefined' && A.open) closeAdmin();
    else post('close');
  }
});

/* ============================================================
   ADMIN PANEL
   ============================================================ */
const admin      = document.getElementById('admin');
const adminBody  = document.getElementById('adminBody');
const adminTitle = document.getElementById('adminTitle');
const adminSub   = document.getElementById('adminSub');
const adminBack  = document.getElementById('adminBack');
const adminCloseBtn = document.getElementById('adminClose');

let A = { open: false, elevators: [], view: 'list', current: null, interactionDefault: 'target', editingFloor: null };

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

async function act(payload) {
  return fetch(`https://${resource}/adminAction`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  }).then(r => r.json()).catch(() => ({}));
}

function jobsStr(jobs) { return (jobs && jobs.length) ? jobs.join(', ') : ''; }

/* two-click confirm for destructive buttons */
function armConfirm(btn, fn) {
  if (btn.dataset.armed) {
    delete btn.dataset.armed;
    btn.classList.remove('confirming');
    fn();
  } else {
    btn.dataset.armed = '1';
    btn.classList.add('confirming');
    const prev = btn.textContent;
    btn.textContent = 'SURE?';
    setTimeout(() => {
      delete btn.dataset.armed;
      btn.classList.remove('confirming');
      btn.textContent = prev;
    }, 2500);
  }
}

function adminOpenView(d) {
  applyTheme(d.color);
  A.open = true;
  A.elevators = d.elevators || [];
  A.interactionDefault = d.interactionDefault || 'target';
  A.view = 'list';
  A.current = null;

  const logo = document.getElementById('adminLogo');
  if (d.logo) { logo.src = d.logo; logo.classList.remove('hidden'); }
  else logo.classList.add('hidden');

  renderAdmin();
  admin.classList.remove('hidden');
}

function adminSetData(elevators) {
  A.elevators = elevators || [];
  if (A.current !== null && !A.elevators.find(e => e.mergedIndex === A.current)) {
    A.view = 'list';
    A.current = null;
  }
  renderAdmin();
}

function closeAdmin() {
  A.open = false;
  admin.classList.add('hidden');
  post('adminClose');
}

function renderAdmin() {
  if (!A.open) return;
  adminBody.innerHTML = '';
  if (A.view === 'list') renderList();
  else renderDetail();
}

/* ---------- LIST VIEW ---------- */
function renderList() {
  adminTitle.textContent = 'ELEVATOR MANAGER';
  adminSub.textContent = 'SELECT OR CREATE';
  adminBack.classList.add('hidden');

  const row = document.createElement('div');
  row.className = 'create-row';
  row.innerHTML = `<input class="a-input" id="newElevName" placeholder="New elevator name..." maxlength="40">
                   <button class="a-btn green" id="createElev">+ CREATE</button>`;
  adminBody.appendChild(row);

  row.querySelector('#createElev').addEventListener('click', async () => {
    const inp = row.querySelector('#newElevName');
    const name = inp.value.trim();
    if (!name) { inp.focus(); return; }
    await act({ action: 'create', name });
    inp.value = '';
  });
  row.querySelector('#newElevName').addEventListener('keydown', e => {
    if (e.key === 'Enter') row.querySelector('#createElev').click();
  });

  if (!A.elevators.length) {
    const n = document.createElement('div');
    n.className = 'empty-note';
    n.textContent = 'No elevators yet — create one above.';
    adminBody.appendChild(n);
    return;
  }

  A.elevators.forEach(e => {
    const card = document.createElement('div');
    card.className = 'elev-card';
    const meta = [`${e.floors.length} floor${e.floors.length === 1 ? '' : 's'}`];
    if (e.jobs && e.jobs.length) meta.push('\u{1F512} ' + jobsStr(e.jobs));
    if (e.source === 'config') meta.push('config.lua');
    card.innerHTML = `<div class="led">\u2195</div>
      <div class="info"><div class="nm">${esc(e.name)}</div><div class="meta">${esc(meta.join('  \u2022  '))}</div></div>
      <div class="chev">\u203A</div>`;
    card.addEventListener('click', () => {
      A.view = 'detail';
      A.current = e.mergedIndex;
      A.editingFloor = null;
      renderAdmin();
    });
    adminBody.appendChild(card);
  });
}

/* ---------- DETAIL VIEW ---------- */
function renderDetail() {
  const e = A.elevators.find(x => x.mergedIndex === A.current);
  if (!e) { A.view = 'list'; return renderList(); }
  const di = e.dynIndex;
  const readOnly = !di;

  adminTitle.textContent = e.name.toUpperCase();
  adminSub.textContent = readOnly ? 'CONFIG.LUA — READ ONLY' : 'EDIT ELEVATOR';
  adminBack.classList.remove('hidden');

  if (readOnly) {
    const n = document.createElement('div');
    n.className = 'empty-note';
    n.textContent = 'This elevator lives in config.lua — edit it there.';
    adminBody.appendChild(n);
    return;
  }

  /* name + jobs */
  let sec = document.createElement('div');
  sec.className = 'a-section';
  sec.textContent = 'ELEVATOR';
  adminBody.appendChild(sec);

  const nameRow = document.createElement('div');
  nameRow.className = 'create-row';
  nameRow.innerHTML = `<input class="a-input" id="elevNm" value="${esc(e.name)}" maxlength="40">
                       <button class="a-btn" id="saveNm">SAVE</button>`;
  adminBody.appendChild(nameRow);
  nameRow.querySelector('#saveNm').addEventListener('click', async () => {
    const name = nameRow.querySelector('#elevNm').value.trim();
    if (name) await act({ action: 'rename', dynIndex: di, name });
  });

  const jobsRow = document.createElement('div');
  jobsRow.className = 'create-row';
  jobsRow.innerHTML = `<input class="a-input" id="elevJobs" value="${esc(jobsStr(e.jobs))}" placeholder="Job lock (comma separated, blank = everyone)">
                       <button class="a-btn" id="saveJobs">SAVE</button>`;
  adminBody.appendChild(jobsRow);
  jobsRow.querySelector('#saveJobs').addEventListener('click', async () => {
    await act({ action: 'jobs', dynIndex: di, jobs: jobsRow.querySelector('#elevJobs').value });
  });

  /* interaction — one-click segmented buttons */
  sec = document.createElement('div');
  sec.className = 'a-section';
  sec.textContent = 'INTERACTION';
  adminBody.appendChild(sec);

  const segRow = document.createElement('div');
  segRow.className = 'seg-row';
  const modes = [
    { v: 'default', l: `DEFAULT (${A.interactionDefault.toUpperCase()})` },
    { v: 'target',  l: 'TARGET EYE' },
    { v: 'marker',  l: 'MARKER + E' },
    { v: 'textui',  l: 'TEXTUI + E' },
  ];
  const cur = e.interaction || 'default';
  modes.forEach(m => {
    const b = document.createElement('button');
    b.className = 'seg' + (cur === m.v ? ' active' : '');
    b.textContent = m.l;
    b.addEventListener('click', () => act({ action: 'interaction', dynIndex: di, mode: m.v }));
    segRow.appendChild(b);
  });
  adminBody.appendChild(segRow);

  /* panel color — per elevator */
  sec = document.createElement('div');
  sec.className = 'a-section';
  sec.textContent = 'PANEL COLOR';
  adminBody.appendChild(sec);

  const presets = ['#47c7d4', '#ffb300', '#ff3b3b', '#ff5bcf', '#9b5dff', '#47abe9', '#39ff88', '#f2f2f2'];
  const swRow = document.createElement('div');
  swRow.className = 'swatch-row';

  presets.forEach(hex => {
    const b = document.createElement('button');
    b.className = 'swatch' + (e.color === hex ? ' active' : '');
    b.style.background = hex;
    b.title = hex;
    b.addEventListener('click', () => act({ action: 'color', dynIndex: di, color: hex }));
    swRow.appendChild(b);
  });

  const defBtn = document.createElement('button');
  defBtn.className = 'a-btn tiny' + (!e.color ? ' green' : '');
  defBtn.textContent = 'DEFAULT';
  defBtn.title = 'Use the global theme from config.lua';
  defBtn.addEventListener('click', () => act({ action: 'color', dynIndex: di, color: '' }));
  swRow.appendChild(defBtn);

  const hexInp = document.createElement('input');
  hexInp.className = 'a-input sm';
  hexInp.placeholder = '#hex';
  hexInp.maxLength = 7;
  hexInp.value = (e.color && !presets.includes(e.color)) ? e.color : '';
  swRow.appendChild(hexInp);

  const hexBtn = document.createElement('button');
  hexBtn.className = 'a-btn tiny';
  hexBtn.textContent = 'SET';
  hexBtn.addEventListener('click', () => {
    let v = hexInp.value.trim();
    if (v && !v.startsWith('#')) v = '#' + v;
    if (/^#[0-9a-fA-F]{6}$/.test(v)) act({ action: 'color', dynIndex: di, color: v });
  });
  swRow.appendChild(hexBtn);

  adminBody.appendChild(swRow);

  /* floors */
  sec = document.createElement('div');
  sec.className = 'a-section';
  sec.textContent = 'FLOORS';
  adminBody.appendChild(sec);

  const addRow = document.createElement('div');
  addRow.className = 'create-row';
  addRow.innerHTML = `<input class="a-input" id="newFloorLbl" placeholder="Floor ${e.floors.length + 1}" maxlength="30">
                      <button class="a-btn green" id="addFloor">+ ADD HERE</button>`;
  adminBody.appendChild(addRow);
  addRow.querySelector('#addFloor').addEventListener('click', async () => {
    await act({ action: 'addFloorHere', dynIndex: di, label: addRow.querySelector('#newFloorLbl').value.trim() });
    addRow.querySelector('#newFloorLbl').value = '';
  });

  e.floors.forEach((f, idx) => {
    const fi = idx + 1;
    const card = document.createElement('div');
    card.className = 'floor-card';
    const c = f.coords;
    const jobsTxt = (f.jobs && f.jobs.length) ? `<span class="fjobs">\u{1F512} ${esc(jobsStr(f.jobs))}</span> \u2022 ` : '';
    card.innerHTML = `
      <div class="frow">
        <div class="led">${fi}</div>
        <div class="fl">
          <div class="fname">${esc(f.label)}</div>
          <div class="fcoords">${jobsTxt}${c.x.toFixed(1)}, ${c.y.toFixed(1)}, ${c.z.toFixed(1)}  h${(c.w ?? 0).toFixed(0)}</div>
        </div>
        <div class="arrows">
          <button class="arrow-btn" data-a="up" ${fi >= e.floors.length ? 'disabled' : ''}>\u25B2</button>
          <button class="arrow-btn" data-a="down" ${fi <= 1 ? 'disabled' : ''}>\u25BC</button>
        </div>
      </div>
      <div class="factions">
        <button class="a-btn tiny" data-a="movehere">MOVE HERE</button>
        <button class="a-btn tiny" data-a="tp">TELEPORT</button>
        <button class="a-btn tiny" data-a="edit">EDIT</button>
        <button class="a-btn tiny red" data-a="del">DELETE</button>
      </div>
      <div class="fedit hidden" data-edit></div>`;

    card.querySelector('[data-a="up"]').addEventListener('click', () => act({ action: 'floorReorder', dynIndex: di, floorIndex: fi, dir: 1 }));
    card.querySelector('[data-a="down"]').addEventListener('click', () => act({ action: 'floorReorder', dynIndex: di, floorIndex: fi, dir: -1 }));
    card.querySelector('[data-a="movehere"]').addEventListener('click', () => act({ action: 'floorMoveHere', dynIndex: di, floorIndex: fi }));
    card.querySelector('[data-a="tp"]').addEventListener('click', () => act({ action: 'floorTeleport', coords: f.coords }));
    card.querySelector('[data-a="del"]').addEventListener('click', ev => {
      armConfirm(ev.target, () => act({ action: 'floorDelete', dynIndex: di, floorIndex: fi }));
    });
    card.querySelector('[data-a="edit"]').addEventListener('click', () => {
      const box = card.querySelector('[data-edit]');
      if (!box.classList.contains('hidden')) { box.classList.add('hidden'); box.innerHTML = ''; return; }
      box.classList.remove('hidden');
      box.innerHTML = `
        <input class="a-input" data-f="label" value="${esc(f.label)}" placeholder="Label" maxlength="30" style="flex:1 1 100%;">
        <input class="a-input sm" data-f="x" value="${c.x.toFixed(2)}">
        <input class="a-input sm" data-f="y" value="${c.y.toFixed(2)}">
        <input class="a-input sm" data-f="z" value="${c.z.toFixed(2)}">
        <input class="a-input sm" data-f="w" value="${(c.w ?? 0).toFixed(1)}" title="Heading">
        <input class="a-input" data-f="jobs" value="${esc(jobsStr(f.jobs))}" placeholder="Job lock (blank = everyone)" style="flex:1 1 100%;">
        <button class="a-btn" data-f="save" style="flex:1 1 100%;">SAVE CHANGES</button>`;
      box.querySelector('[data-f="save"]').addEventListener('click', async () => {
        const v = k => box.querySelector(`[data-f="${k}"]`).value;
        await act({ action: 'floorRename', dynIndex: di, floorIndex: fi, label: v('label').trim() || f.label });
        await act({ action: 'floorCoords', dynIndex: di, floorIndex: fi, x: v('x'), y: v('y'), z: v('z'), w: v('w') });
        await act({ action: 'floorJobs', dynIndex: di, floorIndex: fi, jobs: v('jobs') });
      });
    });

    adminBody.appendChild(card);
  });

  /* danger zone */
  sec = document.createElement('div');
  sec.className = 'a-section';
  sec.textContent = 'DANGER ZONE';
  adminBody.appendChild(sec);

  const delBtn = document.createElement('button');
  delBtn.className = 'a-btn red';
  delBtn.textContent = 'DELETE ELEVATOR';
  delBtn.addEventListener('click', ev => {
    armConfirm(ev.target, async () => {
      await act({ action: 'delete', dynIndex: di });
      A.view = 'list'; A.current = null;
    });
  });
  adminBody.appendChild(delBtn);
}

adminBack.addEventListener('click', () => { A.view = 'list'; A.current = null; renderAdmin(); });
adminCloseBtn.addEventListener('click', closeAdmin);
