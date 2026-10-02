/* Haulaway Moving Co. - clipboard paperwork */

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nrp-movingjob';
const $ = (id) => document.getElementById(id);

const app = $('app');
const pages = { orders: $('pgOrders'), contract: $('pgContract'), active: $('pgActive'), crew: $('pgCrew') };
const cornerPrev = $('cornerPrev');
const cornerNext = $('cornerNext');

let state = null;        // last payload from the client
let selected = null;     // contract picked on the orders page
let current = 'orders';
let crewPicked = new Set();   // server ids ticked on the contract

const post = (name, data = {}) =>
  fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).then((r) => r.json()).catch(() => null);

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const money = (n) => `$${Math.round(Number(n) || 0).toLocaleString('en-US')}`;

function normName(s) {
  return String(s || '').toLowerCase().replace(/[^a-z\s'-]/g, '').replace(/\s+/g, ' ').trim();
}

/* ------------------------------------------------------------------ pages */
function show(name, dir = 0) {
  current = name;
  Object.entries(pages).forEach(([k, el]) => el.classList.toggle('hidden', k !== name));
  const el = pages[name];
  if (dir) {
    el.classList.remove('turn-next', 'turn-prev');
    void el.offsetWidth;
    el.classList.add(dir > 0 ? 'turn-next' : 'turn-prev');
  }
  updateCorners();
}

function setCorner(btn, label) {
  btn.classList.toggle('hidden', !label);
  if (label) btn.querySelector('span').textContent = label;
}

function updateCorners() {
  let prev = null, next = null;
  if (state && state.mode === 'board') {
    if (current === 'orders' && selected) next = 'Contract';
  } else if (state && state.mode === 'active') {
    if (current === 'active' && state.canHire) next = 'Crew';
    if (current === 'crew') prev = 'Work order';
  }
  setCorner(cornerPrev, prev);
  setCorner(cornerNext, next);
}

cornerNext.onclick = () => {
  if (current === 'orders' && selected) show('contract', 1);
  else if (current === 'active') { show('crew', 1); loadCrew(); }
};
cornerPrev.onclick = () => {
  if (current === 'contract') show('orders', -1);
  else if (current === 'crew') show('active', -1);
};

/* ------------------------------------------------------------ work orders */
function boxesFor(n) {
  return '▣'.repeat(Math.min(n, 10));
}

function renderOrders() {
  const list = $('orderList');
  const orders = state.contracts || [];
  $('ordersEmpty').classList.toggle('hidden', orders.length > 0);

  list.innerHTML = orders.map((c, i) => `
    <li class="order" data-i="${i}">
      <span class="box ${selected && selected.id === c.id ? 'ticked' : ''}"></span>
      <div>
        <div class="where">${esc(c.address)}</div>
        <div class="who">Client: <b>${esc(c.customer)}</b></div>
      </div>
      <div class="pay"><b>${money(c.itemCount * c.payPerItem + c.bonus)}</b><span>est. with bonus</span></div>
      <div class="meta">
        <span class="boxes">${boxesFor(c.itemCount)} ${c.itemCount} items</span>
        <span>about ${Number(c.miles).toFixed(1)} mi</span>
        <span>${money(c.payPerItem)} / item</span>
      </div>
    </li>`).join('');
}

$('orderList').addEventListener('click', (e) => {
  const li = e.target.closest('.order');
  if (!li) return;
  selected = state.contracts[Number(li.dataset.i)];
  renderOrders();
  fillContract();
  show('contract', 1);
});

/* --------------------------------------------------------------- contract */
function fillContract() {
  const c = selected;
  const d = new Date();
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'];

  $('kDate').textContent = `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
  $('kCoAddr').textContent = state.company.address;
  $('kCoPhone').textContent = state.company.phone;
  $('kRep').textContent = state.signer.name || '';
  $('kClient').textContent = c.customer;
  $('kClientRep').textContent = c.customer;
  $('kAddr').textContent = c.address;
  $('kClientPhone').textContent = c.phone;
  $('kItems').textContent = c.itemCount;
  $('kFrom').textContent = state.company.yard;
  $('kTo').textContent = c.address;
  $('kMiles').textContent = Number(c.miles).toFixed(1);
  $('kPer').textContent = money(c.payPerItem);
  $('kBonus').textContent = money(c.bonus);
  $('kTotal').textContent = money(c.itemCount * c.payPerItem + c.bonus);
  $('kPenalty').textContent = Math.round((state.penalty || 0) * 100);
  document.querySelectorAll('.co-name').forEach((el) => { el.textContent = state.company.name; });

  $('sigInput').value = '';
  $('stamp').classList.remove('on');
  crewPicked = new Set();
  loadCrewPick();
  const hint = $('signHint');
  hint.classList.toggle('hidden', !(state.signer.required && state.signer.name));
  $('signName').textContent = state.signer.name || '';
  hint.classList.remove('bad', 'good');
  updateAccept();
}

function signatureOk() {
  const sig = $('sigInput').value.trim();
  if (!sig) return false;
  if (state.signer.required && state.signer.name) return normName(sig) === normName(state.signer.name);
  return true;
}

function updateAccept() {
  const sig = $('sigInput').value.trim();
  const ok = signatureOk();
  $('acceptBtn').disabled = !ok;
  const hint = $('signHint');
  hint.classList.toggle('bad', sig.length > 0 && !ok);
  hint.classList.toggle('good', ok && state.signer.required);
}

$('sigInput').addEventListener('input', updateAccept);
$('backBtn').onclick = () => show('orders', -1);

$('acceptBtn').onclick = () => {
  if (!selected || !signatureOk()) return;
  $('stamp').classList.add('on');
  $('acceptBtn').disabled = true;
  const payload = { id: selected.id, signature: $('sigInput').value.trim(), crew: [...crewPicked] };
  setTimeout(() => post('accept', payload), 650);   // let the stamp land
};

/* ------------------------------------------------- crew picked up front */
async function loadCrewPick() {
  const box = $('crewPick');
  const crew = state.crew || {};
  box.classList.toggle('hidden', !crew.enabled || !crew.max);
  if (!crew.enabled || !crew.max) return;

  $('crewPickText').textContent = `Bring up to ${crew.max} more ${crew.max === 1 ? 'hand' : 'hands'}`
    + ` (optional, invited when you sign${crew.splitPay ? ', pay is split' : ''}):`;

  const chips = $('crewChips');
  chips.innerHTML = '<span class="crew-none">looking around...</span>';
  const players = (await post('nearby')) || [];

  // forget anyone who walked off
  const here = new Set(players.map((p) => Number(p.id)));
  crewPicked.forEach((id) => { if (!here.has(id)) crewPicked.delete(id); });

  chips.innerHTML = players.length
    ? players.map((p) => `
        <label class="crew-chip ${crewPicked.has(Number(p.id)) ? 'on' : ''}" data-id="${Number(p.id)}">
          <span class="box"></span>${esc(p.name)}
        </label>`).join('')
    : '<span class="crew-none">nobody standing nearby</span>';
  markFull();
}

function markFull() {
  const max = (state.crew && state.crew.max) || 0;
  const full = crewPicked.size >= max;
  document.querySelectorAll('.crew-chip').forEach((c) => c.classList.toggle('full', full));
}

$('crewChips').addEventListener('click', (e) => {
  const chip = e.target.closest('.crew-chip');
  if (!chip) return;
  e.preventDefault();
  const id = Number(chip.dataset.id);
  if (crewPicked.has(id)) crewPicked.delete(id);
  else if (crewPicked.size < ((state.crew && state.crew.max) || 0)) crewPicked.add(id);
  chip.classList.toggle('on', crewPicked.has(id));
  markFull();
});
$('crewPickRefresh').onclick = loadCrewPick;

/* ------------------------------------------------------------- active job */
const STEPS = [
  { key: 'loading',   label: 'Load the van at the yard' },
  { key: 'transit',   label: 'Drive to the address' },
  { key: 'unloading', label: 'Stack it on the doorstep' },
  { key: 'returning', label: 'Bring the van back' },
];

function renderActive() {
  const j = state.job;
  $('aPlate').textContent = j.plate ? `#${j.plate}` : '';
  $('aClient').textContent = j.customer;
  $('aAddr').textContent = j.address;

  const at = STEPS.findIndex((s) => s.key === j.stage);
  $('aSteps').innerHTML = STEPS.map((s, i) => {
    const cls = i < at ? 'done' : (i === at ? 'now' : '');
    return `<li class="${cls}"><span class="box ${i < at ? 'ticked' : ''}"></span>${s.label}</li>`;
  }).join('');

  const total = j.items.length;
  $('aCount').textContent = `${j.delivered}/${total} delivered`;
  $('aItems').innerHTML = j.items.map((it, i) => `
    <li class="${i < j.delivered ? 'done' : ''}">
      <span class="box ${i < j.delivered ? 'ticked' : ''}"></span>${esc(it.label)}
      <span class="tag ${it.fragile ? 'fragile' : ''}">${it.fragile ? 'fragile' : esc(it.weight || '')}</span>
    </li>`).join('');

  $('aPay').textContent = money(j.delivered * j.payPerItem + (j.stage === 'returning' ? j.bonus : 0));

  const finish = $('finishBtn');
  finish.disabled = j.stage !== 'returning' || !state.isLeader;
  finish.textContent = !state.isLeader ? 'Your crew boss hands it in'
    : (j.stage === 'returning' ? 'Hand in the contract' : 'Finish the job first');
  $('abandonBtn').classList.toggle('hidden', !state.isLeader);
}

$('finishBtn').onclick = () => post('finish');
$('abandonBtn').onclick = () => $('abandonConfirm').classList.remove('hidden');
$('abandonNo').onclick = () => $('abandonConfirm').classList.add('hidden');
$('abandonYes').onclick = () => post('abandon');

/* ------------------------------------------------------------------- crew */
async function loadCrew() {
  const list = $('crewList');
  list.innerHTML = '';
  $('crewEmpty').classList.add('hidden');
  const players = (await post('nearby')) || [];
  $('crewEmpty').classList.toggle('hidden', players.length > 0);
  $('crewLead').textContent = state.splitPay
    ? 'People standing near you right now. Pay is split across the crew.'
    : 'People standing near you right now.';
  list.innerHTML = players.map((p) => `
    <li>
      <span class="box"></span>
      <span class="who">${esc(p.name)}</span>
      <span class="id">ID ${Number(p.id)}</span>
      <button class="btn primary" data-id="${Number(p.id)}">Invite</button>
    </li>`).join('');
}

$('crewList').addEventListener('click', (e) => {
  const btn = e.target.closest('button[data-id]');
  if (!btn || btn.classList.contains('sent')) return;
  post('invite', { id: Number(btn.dataset.id) });
  btn.classList.add('sent');
  btn.textContent = 'Invited ✓';
  btn.closest('li').querySelector('.box').classList.add('ticked');
});
$('crewRefresh').onclick = loadCrew;

/* --------------------------------------------------------------- messages */
window.addEventListener('message', ({ data }) => {
  if (!data || !data.action) return;

  if (data.action === 'open') {
    state = data;
    selected = null;
    document.querySelectorAll('.co-name').forEach((el) => { el.textContent = state.company.name; });
    if (state.mode === 'board') {
      renderOrders();
      show('orders');
    } else {
      $('abandonConfirm').classList.add('hidden');
      renderActive();
      show('active');
    }
    app.classList.remove('hidden');
    post('opened');
  }

  if (data.action === 'update' && state && state.mode === 'active' && data.job) {
    state.job = data.job;
    renderActive();
  }

  if (data.action === 'close') {
    app.classList.add('hidden');
  }
});

/* --------------------------------------------------------------- keyboard */
$('closeBtn').onclick = () => post('close');
document.addEventListener('keydown', (e) => {
  if (app.classList.contains('hidden')) return;
  if (e.key === 'Escape') post('close');
  if (document.activeElement && document.activeElement.tagName === 'INPUT') return;
  if (e.key === 'ArrowRight' && !cornerNext.classList.contains('hidden')) cornerNext.click();
  if (e.key === 'ArrowLeft' && !cornerPrev.classList.contains('hidden')) cornerPrev.click();
});

/* tell the game the page loaded; retry in case the game was not listening yet */
(function hello(tries) {
  post('nuiReady').then((r) => {
    if (!(r && r.ok) && tries < 15) setTimeout(() => hello(tries + 1), 2000);
  });
})(0);
