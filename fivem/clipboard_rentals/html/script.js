const app       = document.getElementById('app');
const tabsEl     = document.getElementById('tabs');
const listEl     = document.getElementById('vehicleList');
const confirmEl  = document.getElementById('confirm');
const papersEl   = document.getElementById('papers');
const toastsEl   = document.getElementById('toasts');

let vehicles = [];
let currency = '$';
let refundPct = 75;
let activeCat = 'All';
let selected = null;
let contractCfg = { enabled: false, requireAgree: false, requireSignature: false, company: '', terms: [], duration: 60 };
let countdownTimer = null;
let signer = { name: '', required: false };   // real name the renter must sign with

const post = (name, data = {}) =>
  fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  }).catch(() => {});

post('pageLoaded');

/* ============ MESSAGES FROM CLIENT ============ */
window.addEventListener('message', ({ data }) => {
  switch (data.action) {
    case 'open':
      vehicles = data.vehicles || [];
      currency = data.currency || '$';
      refundPct = (data.refundPct != null ? data.refundPct : 75);
      contractCfg = data.contract || contractCfg;
      const pct = document.getElementById('refundPct');
      if (pct) pct.textContent = refundPct;
      activeCat = 'All';
      buildTabs();
      renderList();
      confirmEl.classList.add('hidden');
      app.classList.remove('hidden');
      post('uiReady');
      break;

    case 'forceClose':
      app.classList.add('hidden');
      confirmEl.classList.add('hidden');
      selected = null;
      break;

    case 'openPapers':
      renderPapers(data.contract, data.registration);
      papersEl.classList.remove('hidden');
      break;

    case 'forceClosePapers':
      papersEl.classList.add('hidden');
      stopCountdown();
      break;

    case 'prompt': {
      const p = document.getElementById('prompt');
      if (data.show) {
        document.getElementById('promptText').textContent = data.text || 'Browse rentals';
        p.classList.remove('hidden');
      } else {
        p.classList.add('hidden');
      }
      break;
    }

    case 'notify':
      toast(data.message, data.type);
      break;

    case 'signerName':
      signer = { name: data.name || '', required: !!data.required };
      if (!confirmEl.classList.contains('hidden')) { showSignHint(); updateConfirmState(); }
      break;
  }
});

/* ============ BROWSER ============ */
function buildTabs() {
  const cats = ['All', ...new Set(vehicles.map(v => v.category))];
  tabsEl.innerHTML = '';
  cats.forEach(cat => {
    const n = cat === 'All' ? vehicles.length : vehicles.filter(v => v.category === cat).length;
    const b = document.createElement('button');
    b.className = 'tab' + (cat === activeCat ? ' active' : '');
    b.innerHTML = `${cat}<span class="count">${n}</span>`;
    b.onclick = () => { activeCat = cat; buildTabs(); renderList(); };
    tabsEl.appendChild(b);
  });
}

function vehImage(v) {
  return v.image || `https://docs.fivem.net/vehicles/${v.model}.webp`;
}

function renderList() {
  listEl.innerHTML = '';
  vehicles
    .filter(v => activeCat === 'All' || v.category === activeCat)
    .forEach(v => {
      const el = document.createElement('div');
      el.className = 'card';
      el.innerHTML = `
        <div class="pic"><img src="${vehImage(v)}" alt="" loading="lazy"
             onerror="this.parentElement.classList.add('noimg')"></div>
        <div class="top">
          <span class="name">${esc(v.label)}</span>
          <span class="cat">${esc(v.category)}</span>
        </div>
        <div class="desc">${esc(v.desc || '')}</div>
        <div class="money">
          <span class="fee">${currency}${v.price}</span>
          <span class="dep">+ ${currency}${v.deposit} deposit</span>
        </div>`;
      el.onclick = () => openConfirm(v);
      listEl.appendChild(el);
    });
}

/* ============ CONTRACT / CONFIRM ============ */
function fillTokens(str) {
  return String(str)
    .replace(/{company}/g, contractCfg.company || 'the company')
    .replace(/{duration}/g, contractCfg.duration || 0);
}

function openConfirm(v) {
  selected = v;
  const refund = Math.floor(v.deposit * refundPct / 100);

  const pic = document.getElementById('cPic');
  pic.classList.remove('noimg');
  pic.querySelector('img').src = vehImage(v);

  document.getElementById('cName').textContent    = v.label;
  document.getElementById('cPrice').textContent   = currency + v.price;
  document.getElementById('cDeposit').textContent = currency + v.deposit;
  document.getElementById('cTotal').textContent   = currency + (v.price + v.deposit);
  document.getElementById('cRefund').textContent  = currency + refund;

  const pane = document.getElementById('contractPane');
  const confirmBtn = document.getElementById('confirmBtn');
  const sig = document.getElementById('sigInput');
  const chk = document.getElementById('agreeChk');
  const agreeWrap = document.getElementById('agreeWrap');

  if (contractCfg.enabled) {
    pane.classList.remove('hidden');
    document.getElementById('ctCompany').textContent = contractCfg.company || 'Clipboard Rentals LLC';

    const list = document.getElementById('ctTerms');
    list.innerHTML = '';
    (contractCfg.terms || []).forEach(t => {
      const li = document.createElement('li');
      li.textContent = fillTokens(t);
      list.appendChild(li);
    });

    sig.value = '';
    chk.checked = false;
    const sigLabel = pane.querySelector('.sign-label');
    sig.style.display = contractCfg.requireSignature ? '' : 'none';
    if (sigLabel) sigLabel.style.display = contractCfg.requireSignature ? '' : 'none';
    agreeWrap.style.display = contractCfg.requireAgree ? 'flex' : 'none';
    confirmBtn.textContent = 'Sign & drive';
    sig.oninput = updateConfirmState;
    chk.onchange = updateConfirmState;
    showSignHint();
    updateConfirmState();
  } else {
    pane.classList.add('hidden');
    confirmBtn.textContent = 'Rent it';
    confirmBtn.disabled = false;
  }

  confirmEl.classList.remove('hidden');
}

function updateConfirmState() {
  const confirmBtn = document.getElementById('confirmBtn');
  const sig = document.getElementById('sigInput').value.trim();
  const agreed = document.getElementById('agreeChk').checked;
  let ok = true;
  if (contractCfg.requireSignature && sig.length === 0) ok = false;
  if (contractCfg.requireSignature && signer.required && signer.name) {
    const match = normName(sig) === normName(signer.name);
    if (!match) ok = false;
    const hint = document.getElementById('signHint');
    if (hint) hint.classList.toggle('bad', sig.length > 0 && !match);
    if (hint) hint.classList.toggle('good', match);
  }
  if (contractCfg.requireAgree && !agreed) ok = false;
  confirmBtn.disabled = !ok;
}

function normName(s) {
  return String(s || '').toLowerCase().replace(/[^a-z\s'-]/g, '').replace(/\s+/g, ' ').trim();
}

function showSignHint() {
  const hint = document.getElementById('signHint');
  if (!hint) return;
  const show = contractCfg.requireSignature && signer.required && signer.name;
  hint.classList.toggle('hidden', !show);
  if (show) document.getElementById('signHintName').textContent = signer.name;
}

function closeConfirm() {
  confirmEl.classList.add('hidden');
  selected = null;
}

document.getElementById('cancelBtn').onclick = closeConfirm;
document.getElementById('cancelX').onclick   = closeConfirm;

document.getElementById('confirmBtn').onclick = () => {
  if (!selected) return;
  const signature = document.getElementById('sigInput').value.trim();
  confirmEl.classList.add('hidden');
  app.classList.add('hidden');
  post('rent', { model: selected.model, signature });
  selected = null;
};

function closeAll() {
  confirmEl.classList.add('hidden');
  app.classList.add('hidden');
  selected = null;
  post('close');
}

document.getElementById('closeBtn').onclick = closeAll;

/* ============ PAPERS ============ */
function pad(n) { return String(n).padStart(2, '0'); }

function fmtDateTime(epochSec) {
  if (!epochSec) return '—';
  const d = new Date(epochSec * 1000);
  const mon = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.getMonth()];
  return `${mon} ${d.getDate()}, ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function renderPapers(contract, registration) {
  stopCountdown();
  if (!contract) return;

  // Contract document
  document.getElementById('dcCompany').textContent = contract.company || 'Clipboard Rentals LLC';
  document.getElementById('dcId').textContent       = contract.id || '—';
  document.getElementById('dcHolder').textContent   = contract.holder || '—';
  document.getElementById('dcVehicle').textContent  = contract.vehicle || '—';
  document.getElementById('dcPlate').textContent    = contract.plate || '—';
  document.getElementById('dcIssued').textContent   = fmtDateTime(contract.issuedAt);
  document.getElementById('dcPrice').textContent    = (contract.currency || currency) + (contract.price ?? '—');
  document.getElementById('dcDeposit').textContent  = (contract.currency || currency) + (contract.deposit ?? '—');
  document.getElementById('dcSignature').textContent = contract.signature || contract.holder || '—';

  const dct = document.getElementById('dcTerms');
  dct.innerHTML = '';
  (contract.terms || []).forEach(t => {
    const li = document.createElement('li');
    li.textContent = t;
    dct.appendChild(li);
  });

  // Temp registration
  const regDoc = document.getElementById('docReg');
  if (registration) {
    regDoc.classList.remove('hidden');
    document.getElementById('drAuthority').textContent = registration.authority || 'Los Santos DMV';
    document.getElementById('drNumber').textContent    = registration.regNumber || 'TMP-000000';
    document.getElementById('drHolder').textContent    = registration.holder || '—';
    document.getElementById('drVehicle').textContent   = registration.vehicle || '—';
    document.getElementById('drPlate').textContent     = registration.plate || '—';
    document.getElementById('drIssued').textContent    = fmtDateTime(registration.issuedAt);
    document.getElementById('drExpires').textContent   = fmtDateTime(registration.expiresAt);
    startCountdown(registration);
  } else {
    regDoc.classList.add('hidden');
  }
}

function startCountdown(reg) {
  const total = Math.max(1, (reg.expiresAt || 0) - (reg.issuedAt || 0));
  const cdEl  = document.getElementById('drCountdown');
  const barEl = document.getElementById('drBar');

  const tick = () => {
    const now = Date.now() / 1000;
    let remaining = Math.floor((reg.expiresAt || 0) - now);

    if (remaining <= 0) {
      cdEl.textContent = 'EXPIRED';
      cdEl.classList.add('expired');
      cdEl.classList.remove('low');
      barEl.style.width = '0%';
      barEl.classList.add('low');
      stopCountdown();
      return;
    }

    const h = Math.floor(remaining / 3600);
    const m = Math.floor((remaining % 3600) / 60);
    const s = remaining % 60;
    cdEl.textContent = h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;

    const low = remaining <= 300; // last 5 minutes
    cdEl.classList.toggle('low', low);
    barEl.classList.toggle('low', low);
    barEl.style.width = Math.max(0, Math.min(100, (remaining / total) * 100)) + '%';
  };

  tick();
  countdownTimer = setInterval(tick, 1000);
}

function stopCountdown() {
  if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
}

function closePapers() {
  papersEl.classList.add('hidden');
  stopCountdown();
  post('closePapers');
}

document.getElementById('papersClose').onclick = closePapers;

/* ============ KEYBOARD ============ */
document.addEventListener('keydown', e => {
  if (e.key !== 'Escape') return;
  if (!papersEl.classList.contains('hidden')) {
    closePapers();
  } else if (!confirmEl.classList.contains('hidden')) {
    closeConfirm();
  } else if (!app.classList.contains('hidden')) {
    closeAll();
  }
});

/* ============ UTIL ============ */
function esc(str) {
  return String(str).replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

function toast(msg, type = 'info') {
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.textContent = msg;
  toastsEl.appendChild(t);
  setTimeout(() => {
    t.classList.add('out');
    setTimeout(() => t.remove(), 300);
  }, 4500);
}
