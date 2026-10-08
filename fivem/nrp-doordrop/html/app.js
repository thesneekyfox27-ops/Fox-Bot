// EMBEDDED = running as an app inside 17mov_Phone (html/phone.html) instead of our own overlay phone.
const EMBEDDED = document.body.classList.contains('embedded');
const RES = (EMBEDDED && window.name) || (typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nrp-doordrop');
const post = (name, data = {}) =>
  fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).then((r) => r.json()).catch(() => null);

const $ = (s) => document.querySelector(s);
const phone = $('#phone');
const view = $('#view');
const tabs = $('#tabs');

const S = {
  mode: 'closed',
  role: null,            // 'driver' | 'customer' (follows the bottom tab)
  nav: null,             // bottom tab: 'order' | 'orders' | 'drive'
  tab: 'dash',
  showClosed: false,
  cfg: { app: 'DoorDrop', key: 'F6', imagePath: '', ordering: true },
  snap: null,
  // driver
  offer: null, offerEnd: 0, offerTotal: 30,
  order: null, orderDeadline: 0,
  result: null, photos: {}, armed: false, toast: null,
  // customer
  cview: 'list', menu: null, menuLoading: false, shop: null, cart: {},
  tip: null, tipCustom: '', handoff: 'hand', placing: false, cust: null, custArmed: false, custToast: null,
  rateFor: null, rateStars: 0, rateText: '', custDone: null,
  pos: null, mapSize: 2048,
  mapView: {}, // per map: { manual, sc, cx, cy } - manual once you zoom or drag
  zones: [], zoneStatus: null, peak: false, condition: 100,
  driverRoute: null, custNext: null, // road paths for your own delivery / the courier's next leg
};

/* ---------- helpers ---------- */
const money = (n) => '$' + Math.round(n || 0).toLocaleString('en-US');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const mmss = (sec) => {
  const neg = sec < 0; sec = Math.abs(Math.floor(sec));
  return (neg ? '-' : '') + Math.floor(sec / 60) + ':' + String(sec % 60).padStart(2, '0');
};
const starRow = (n) => {
  const full = Math.round(n);
  let out = '';
  for (let i = 1; i <= 5; i++) out += i <= full ? '★' : '<span class="off">★</span>';
  return out;
};
const itemsText = (items) => (items || []).filter((i) => i.qty > 0).map((i) => `${i.qty}× ${esc(i.name || i.label)}`).join(', ');
const timeOf = (t) => new Date(t * 1000).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
const ago = (t) => {
  const s = Math.max(0, Date.now() / 1000 - t);
  if (s < 3600) return `${Math.max(1, Math.round(s / 60))}m ago`;
  if (s < 86400) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
};
const imgFor = (file) => (S.cfg.imagePath && file ? S.cfg.imagePath.replace('%s', encodeURIComponent(file)) : '');
const back = (act, extra = '') => `<button class="back" data-act="${act}" ${extra} aria-label="Back">‹</button>`;

function thumb(dataUrl) {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      const w = 320, h = Math.round(img.height * (w / img.width));
      const c = document.createElement('canvas');
      c.width = w; c.height = h;
      c.getContext('2d').drawImage(img, 0, 0, w, h);
      resolve(c.toDataURL('image/jpeg', 0.7));
    };
    img.onerror = () => resolve(null);
    img.src = dataUrl;
  });
}

function flash() {
  const f = $('#flash');
  f.classList.remove('go');
  void f.offsetWidth;
  f.classList.add('go');
}

function setMode(mode) {
  if (EMBEDDED) mode = 'open';
  S.mode = mode;
  phone.className = mode;
  phone.setAttribute('aria-hidden', mode === 'closed');
  if (mode === 'open' && S.offer) { S.nav = 'drive'; S.tab = 'dash'; S.page = null; }
  render();
}

/* ---------- mini map ---------- */
// World coords -> pixels on the phone's Map.png (same bounds its Maps app uses).
function toMapPx(p) {
  const b = S.cfg.map.bounds, n = S.mapSize;
  return {
    x: ((p.x - b.xMin) / (b.xMax - b.xMin)) * n,
    y: (1 - (p.y - b.yMin) / (b.yMax - b.yMin)) * n,
  };
}

const hasXY = (p) => p && typeof p.x === 'number' && typeof p.y === 'number';

// What each map shows. Route = the order the points are driven in.
function mapSpec(kind) {
  const pts = [];
  const add = (k, p, extra = {}) => { if (hasXY(p)) pts.push({ k, x: p.x, y: p.y, ...extra }); };
  if (kind === 'home') {
    add('me', S.pos);
    // you, plus the closest busy area if it's reasonably near
    const me = S.pos || { x: 0, y: 0 };
    const near = [...S.zones].map((z) => ({ z, d: Math.hypot(z.x - me.x, z.y - me.y) - z.radius })).sort((a, b) => a.d - b.d)[0];
    if (S.pos && near && near.d < 2500) {
      const { x, y, radius: r } = near.z;
      [[x - r, y], [x + r, y], [x, y - r], [x, y + r]].forEach(([px, py]) => pts.push({ k: 'zonefit', x: px, y: py }));
    }
  } else if (kind === 'zones') {
    add('me', S.pos);
    // fit you + the nearest couple of hot zones
    const near = [...S.zones].sort((a, b) => Math.hypot(a.x - (S.pos?.x || 0), a.y - (S.pos?.y || 0)) - Math.hypot(b.x - (S.pos?.x || 0), b.y - (S.pos?.y || 0))).slice(0, 2);
    near.forEach((z) => pts.push({ k: 'zonefit', x: z.x, y: z.y }));
  } else if (kind === 'offer' && S.offer) {
    const o = S.offer;
    add('me', S.pos); add('shop', o.restaurant, { label: o.restaurant.label }); add('home', o.dropoff);
  } else if (kind === 'order' && S.order) {
    const o = S.order;
    add('me', S.pos);
    if (o.stage === 'pickup') add('shop', o.restaurant, { label: o.restaurant.label });
    add('home', o.dropoff, { faded: o.stage === 'pickup' });
  } else if (kind === 'track' && S.cust) {
    const c = S.cust;
    const moving = c.status === 'accepted' || c.status === 'pickedup' || c.status === 'arriving';
    if (moving) add('courier', c.courierPos, { npc: c.npc });
    if (c.status === 'searching' || c.status === 'accepted') add('shop', c.pickup, { label: c.restaurant });
    add('home', c.dest);
    if (c.handoff !== 'door') add('me', S.pos);
  }
  return pts;
}

function mapLayout(el) {
  const pts = mapSpec(el.dataset.map);
  if (!pts.length) return null;
  const W = el.clientWidth || 286, H = el.clientHeight || 160, pad = 30;
  const padT = Number(el.dataset.padt || 0), padB = Number(el.dataset.padb || 0);
  const Hv = Math.max(60, H - padT - padB); // the part of the map that isn't covered
  const px = pts.map((p) => ({ ...p, ...toMapPx(p) }));
  const xs = px.map((p) => p.x), ys = px.map((p) => p.y);
  const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys);
  const kind = el.dataset.map;
  let mv = S.mapView[kind];
  if (!mv || !mv.manual) {
    // auto-fit everything on the route until you zoom or drag
    const span = Math.max((maxX - minX) / (W - pad * 2), (maxY - minY) / (Hv - pad * 2), 1e-6);
    const single = kind === 'home' ? 1.6 : 2.2;
    mv = S.mapView[kind] = {
      manual: false,
      sc: Math.max(MAP_MIN, Math.min(3, px.length > 1 ? 1 / span : single)),
      cx: (minX + maxX) / 2, cy: (minY + maxY) / 2,
    };
  }
  // zoomed in and not dragged away: keep the moving car (or you) in the middle
  if (mv.manual && mv.follow !== false) {
    const f = kind === 'track'
      ? (px.find((p) => p.k === 'courier') || px.find((p) => p.k === 'me'))
      : (px.find((p) => p.k === 'me') || px.find((p) => p.k === 'courier'));
    if (f) { mv.cx = f.x; mv.cy = f.y; }
  }
  mv.W = W; mv.H = H;
  const { sc, cx, cy } = mv;
  const tx = W / 2 - cx * sc, ty = padT + Hv / 2 - cy * sc;
  const at = (p) => ({ left: p.x * sc + tx, top: p.y * sc + ty });

  const order = ['zonefit', 'courier', 'me', 'shop', 'home'];
  const lead = px.find((p) => p.k === 'courier') || px.find((p) => p.k === 'me');
  const shopP = px.find((p) => p.k === 'shop'), homeP = px.find((p) => p.k === 'home');
  const poly = (list) => list.map((p) => { const a = at(p); return `${a.left.toFixed(1)},${a.top.toFixed(1)}`; }).join(' ');

  // real streets whenever we have them: split at the courier / you, done part faded, the rest bold
  let lines = '';
  const roadLine = (pts, from) => {
    const rp = pts.map(toMapPx);
    if (!from) return `<polyline class="road" points="${poly(rp)}"/>`;
    let cut = 0, best = Infinity;
    rp.forEach((p, i) => { const d = (p.x - from.x) ** 2 + (p.y - from.y) ** 2; if (d < best) { best = d; cut = i; } });
    return `<polyline class="road-done" points="${poly([...rp.slice(0, cut + 1), from])}"/><polyline class="road" points="${poly([from, ...rp.slice(cut + 1)])}"/>`;
  };
  const road = kind === 'track' && S.cust && S.cust.route;
  const leg = S.cust && (S.cust.status === 'accepted' ? 'shop' : 'customer');
  const drv = S.driverRoute;
  const drvKey = kind === 'offer' && S.offer ? `offer:${S.offer.id}` : kind === 'order' && S.order ? `order:${S.order.id}:${S.order.stage}` : null;
  if (road && road.leg === leg && road.pts.length > 1 && lead) {
    lines += roadLine(road.pts, lead);
    if (leg === 'shop' && shopP && homeP) {
      // restaurant -> you: on roads too once it's planned
      const nx = S.custNext && S.custNext.id === S.cust.id && S.custNext.pts;
      lines += nx && nx.length > 1 ? `<polyline class="road-next" points="${poly(nx.map(toMapPx))}"/>` : `<polyline points="${poly([shopP, homeP])}"/>`;
    }
  } else if (drvKey && drv && drv.key === drvKey && drv.pts.length > 1) {
    lines += roadLine(drv.pts, kind === 'order' ? lead : null);
  } else {
    // otherwise a dashed "as the crow flies" guide in driving order: courier/you -> restaurant -> drop-off
    const route = [lead, shopP, homeP].filter(Boolean);
    if (route.length > 1) lines = `<polyline points="${poly(route)}"/>`;
  }
  const line = lines ? `<svg class="map-route" width="${W}" height="${H}">${lines}</svg>` : '';

  // hot zones as translucent circles on driver maps
  const b = S.cfg.map.bounds;
  const zoneHtml = kind === 'track' ? '' : S.zones.map((z) => {
    const c = at({ ...toMapPx(z) });
    const r = (z.radius / (b.xMax - b.xMin)) * S.mapSize * sc;
    const label = kind === 'home'
      ? `<em class="chip ${z.bonus >= 3 ? 'very' : ''}">${z.bonus >= 3 ? 'Very busy' : 'Busy'} +$${z.bonus}/order</em>`
      : (r > 26 ? `<em>+$${z.bonus}</em>` : '');
    return `<span class="zone ${kind === 'home' ? 'home' : ''}" style="left:${c.left.toFixed(1)}px;top:${c.top.toFixed(1)}px;width:${(r * 2).toFixed(1)}px;height:${(r * 2).toFixed(1)}px">${label}</span>`;
  }).join('');

  const pin = (p) => {
    const a = at(p);
    const base = { key: p.k, left: a.left, top: a.top };
    if (p.k === 'me') return { ...base, cls: 'mk mk-me', title: 'You', html: '' };
    if (p.k === 'shop') return { ...base, cls: 'mk mk-shop', title: p.label || 'Pickup', html: esc((p.label || 'P').charAt(0)) };
    if (p.k === 'home') return { ...base, cls: `mk mk-home ${p.faded ? 'faded' : ''}`, title: 'Drop-off', html: '⌂' };
    return { ...base, cls: 'mk mk-courier', title: 'Driver', html: p.npc ? '🛵' : '🚗' };
  };
  px.sort((a, b) => order.indexOf(b.k) - order.indexOf(a.k)); // courier + you drawn on top
  return {
    transform: `translate(${tx.toFixed(1)}px,${ty.toFixed(1)}px) scale(${sc.toFixed(4)})`,
    under: zoneHtml + line,
    pins: px.filter((p) => p.k !== 'zonefit').map(pin),
  };
}

// Keeps the <img> and the pins between updates, so moving pins glide instead of jumping.
function fillMap(el, instant) {
  const lay = mapLayout(el);
  if (!lay) { el.innerHTML = '<p class="map-empty">The map shows up once there\'s somewhere to go.</p>'; return; }
  let img = el.querySelector('.map-img');
  if (!img) {
    el.innerHTML = `<img class="map-img" src="${esc(S.cfg.map.image)}" alt="" draggable="false"
      onload="mapLoaded(this)" onerror="this.closest('.minimap').classList.add('no-img')"><div class="map-layer"></div>
      <div class="map-ctrl">
        <button data-zoom="in" aria-label="Zoom in">+</button>
        <button data-zoom="out" aria-label="Zoom out">−</button>
        <button data-zoom="fit" class="fit" aria-label="Show the whole route">⌖</button>
      </div><div class="map-pins"></div>`;
    img = el.querySelector('.map-img');
    instant = true;
  }
  if (instant) {
    // zooming / dragging / first draw: move everything at once, no glide
    el.classList.add('snap');
    const raf = window.requestAnimationFrame || ((fn) => setTimeout(fn, 16));
    raf(() => raf(() => el.classList.remove('snap')));
  }
  el.classList.toggle('manual', !!(S.mapView[el.dataset.map] || {}).manual);
  img.style.width = img.style.height = `${S.mapSize}px`;
  img.style.transform = lay.transform;
  el.querySelector('.map-layer').innerHTML = lay.under;

  const box = el.querySelector('.map-pins');
  const keep = new Set();
  for (const p of lay.pins) {
    keep.add(p.key);
    let node = box.querySelector(`[data-key="${p.key}"]`);
    if (!node) { node = document.createElement('span'); node.dataset.key = p.key; box.appendChild(node); }
    node.className = p.cls;
    node.title = p.title;
    if (node.innerHTML !== p.html) node.innerHTML = p.html;
    node.style.left = `${p.left.toFixed(1)}px`;
    node.style.top = `${p.top.toFixed(1)}px`;
  }
  box.querySelectorAll('[data-key]').forEach((n) => { if (!keep.has(n.dataset.key)) n.remove(); });
}

/* zoom (mouse wheel, +/-), drag to pan, ⌖ to snap back to the whole route */
const MAP_MIN = 0.25, MAP_MAX = 4.5;

function zoomMap(el, factor, mx, my) {
  const mv = S.mapView[el.dataset.map];
  if (!mv) return;
  const W = mv.W || el.clientWidth || 286, H = mv.H || el.clientHeight || 160;
  if (mv.follow === undefined) mv.follow = true;
  if (mx == null || mv.follow) { mx = W / 2; my = H / 2; } // following: zoom around the car
  const padT = Number(el.dataset.padt || 0), padB = Number(el.dataset.padb || 0);
  const cyScreen = padT + Math.max(60, H - padT - padB) / 2;
  if (mv.follow) my = cyScreen;
  const tx = W / 2 - mv.cx * mv.sc, ty = cyScreen - mv.cy * mv.sc;
  const ix = (mx - tx) / mv.sc, iy = (my - ty) / mv.sc; // map pixel under the cursor stays put
  const sc = Math.max(MAP_MIN, Math.min(MAP_MAX, mv.sc * factor));
  const ntx = mx - ix * sc, nty = my - iy * sc;
  Object.assign(mv, { manual: true, sc, cx: (W / 2 - ntx) / sc, cy: (cyScreen - nty) / sc });
  fillMap(el, true);
}

view.addEventListener('wheel', (e) => {
  const el = e.target.closest('.minimap');
  if (!el || !S.mapView[el.dataset.map]) return;
  e.preventDefault();
  const r = el.getBoundingClientRect();
  zoomMap(el, e.deltaY < 0 ? 1.25 : 0.8, e.clientX - r.left, e.clientY - r.top);
}, { passive: false });

let mapDrag = null;
view.addEventListener('mousedown', (e) => {
  const el = e.target.closest('.minimap');
  if (!el || e.target.closest('.map-ctrl') || !S.mapView[el.dataset.map]) return;
  mapDrag = { el, x: e.clientX, y: e.clientY };
  el.classList.add('dragging');
  e.preventDefault();
});
window.addEventListener('mousemove', (e) => {
  if (!mapDrag) return;
  const mv = S.mapView[mapDrag.el.dataset.map];
  if (!mv) return;
  mv.cx -= (e.clientX - mapDrag.x) / mv.sc;
  mv.cy -= (e.clientY - mapDrag.y) / mv.sc;
  mv.manual = true;
  mv.follow = false; // you're looking around: stop re-centering until ⌖
  mapDrag.x = e.clientX; mapDrag.y = e.clientY;
  fillMap(mapDrag.el, true);
});
window.addEventListener('mouseup', () => {
  if (mapDrag) mapDrag.el.classList.remove('dragging');
  mapDrag = null;
});
view.addEventListener('click', (e) => {
  const b = e.target.closest('[data-zoom]');
  if (!b) return;
  const el = b.closest('.minimap');
  if (b.dataset.zoom === 'in') zoomMap(el, 1.5);
  else if (b.dataset.zoom === 'out') zoomMap(el, 1 / 1.5);
  else { delete S.mapView[el.dataset.map]; fillMap(el, true); }
  e.stopPropagation();
});
view.addEventListener('dblclick', (e) => {
  const el = e.target.closest('.minimap');
  if (!el || e.target.closest('.map-ctrl')) return;
  const r = el.getBoundingClientRect();
  zoomMap(el, 1.6, e.clientX - r.left, e.clientY - r.top);
});

window.mapLoaded = (img) => {
  if (img.naturalWidth && img.naturalWidth !== S.mapSize) { S.mapSize = img.naturalWidth; refreshMaps(); }
};

function miniMap(kind, height) {
  if (!S.cfg.map) return '';
  return `<div class="minimap" data-map="${kind}" style="height:${height}px"></div>`;
}

function refreshMaps() {
  if (!S.cfg.map) return;
  view.querySelectorAll('.minimap').forEach((el) => fillMap(el));
}

/* ---------- picker ---------- */
function offerWaitText(s) {
  const w = S.cfg.offerWait;
  if (!w) return '--';
  const z = S.zoneStatus;
  const mult = (s.waitMult || 1) * (z && z.inZone ? w.inside : S.zones.length ? w.outside : 1);
  const secs = ((w.min + w.max) / 2) * mult;
  return secs < 60 ? `About ${Math.max(10, Math.round(secs / 10) * 10)} sec` : `About ${Math.round(secs / 60)} min`;
}

const clockIn = (secs) => new Date(Date.now() + secs * 1000).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });

// DoorDash-style main screen: the map up front, a sheet at the bottom with Dash / Order food.
function viewMapHome(s) {
  const dashing = !!s.online;
  const z = S.zoneStatus;
  const area = (S.pos && S.pos.area) || 'Los Santos';
  let head, sub;
  if (z && z.inZone) {
    head = S.peak ? "It's peak pay time!" : "You're in a busy area";
    sub = `+$${z.inZone.bonus}.00/order${z.inZone.endsIn ? ` until ${clockIn(z.inZone.endsIn)}` : ''}`;
  } else if (z && z.nearest) {
    head = S.peak ? 'Peak pay nearby' : 'Busy area nearby';
    sub = `+$${z.nearest.bonus}.00/order in ${esc(z.nearest.name)}, ${z.nearest.miles} mi away`;
  } else {
    head = "It's quiet right now";
    sub = 'Offers still come in. Busy areas pop up around lunch and dinner.';
  }
  if (dashing) sub = `${esc(head)}${/[.!?]$/.test(head) ? '' : '.'} ${sub}`, head = 'Looking for orders';
  const c = S.cust;
  return `
    <div class="home">
      <div class="minimap home-map" data-map="home" data-padt="${EMBEDDED ? 112 : 64}"></div>
      <div class="home-top">
        <button class="fab" data-act="menu" aria-label="Earnings and history">☰</button>
        <button class="earn" data-act="menu"><b>${money(s.today.earned)}</b><span>Today</span></button>
        <button class="fab star" data-act="ratings" aria-label="Ratings">★<small>${s.rating.toFixed(1)}</small></button>
      </div>
      <section class="sheet">
        ${activeBanner()}
        <p class="sheet-area">${esc(area)}</p>
        <h2 class="sheet-head ${dashing ? 'small' : ''}">${dashing ? '<i class="pulse"></i>' : ''}${esc(head)}</h2>
        <p class="sheet-sub">${sub}</p>
        <div class="sheet-card ${dashing ? 'two' : ''}">
          <div><span>Avg. offer wait</span><b>${offerWaitText(s)}</b></div>
          ${dashing ? `<div><span>This dash</span><b>${money(s.today.earned)}, ${s.today.count} ${s.today.count === 1 ? 'order' : 'orders'}</b></div>` : ''}
        </div>
        ${dashing ? streakBar(s) : ''}
        ${S.toast ? `<div class="toast">${esc(S.toast)}</div>` : ''}
        <div class="sheet-actions">
          ${dashing
            ? `<button class="ghost" data-act="offline">Stop dashing</button>`
            : `<button class="cta dash" data-act="dash">Dash</button>
               ${S.cfg.ordering ? `<button class="order-btn" data-act="nav" data-nav="order" aria-label="Order food">🍔<span>Order</span></button>` : ''}`}
        </div>
      </section>
    </div>`;
}

/* ---------- driver views ---------- */
function statStrip(s) {
  return `
    <div class="strip">
      <div><b><span class="star-inline">★</span> ${s.rating.toFixed(2)}</b><span>Rating</span></div>
      <div><b>${s.acceptance}%</b><span>Acceptance</span></div>
      <div><b>${esc(s.tier)}</b><span>Tier</span></div>
    </div>`;
}

function historyList(hist) {
  if (!hist.length) return `<div class="empty">No deliveries yet. Clock in to get your first offer.</div>`;
  return `<ul class="history">${hist.map((h) => `
    <li>
      <div>${esc(h.restaurant)}<small>${esc(h.dropoff)}, ${timeOf(h.t)}</small></div>
      <div class="amt">${money(h.total)}<small>${h.stars ? `<span class="star-inline">★</span> ${h.stars}` : 'Rating pending'}</small></div>
    </li>`).join('')}</ul>`;
}

function viewHome(s) {
  return `
    <header class="app-head">${back('drivehome')}<h2 class="page-title">Earnings</h2><span class="pill ${s.online ? 'on' : ''}">${s.online ? 'Dashing' : 'Not dashing'}</span></header>
    <div class="today">
      <div class="today-amt">${money(s.today.earned)}</div>
      <div class="today-sub">${s.today.count} ${s.today.count === 1 ? 'delivery' : 'deliveries'} this session, ${money(s.earned)} all time</div>
    </div>
    ${statStrip(s)}
    ${streakBar(s)}
    <h3 class="section">Recent deliveries</h3>
    ${historyList((s.history || []).slice(0, 5))}
  `;
}

function zoneCard() {
  const z = S.zoneStatus;
  if (!S.zones.length) return '';
  if (z && z.inZone) {
    return `<div class="zonecard on"><b>🔥 ${esc(z.inZone.name)} is hot</b><span>+$${z.inZone.bonus} on every order you take here${S.peak ? ', peak time' : ''}</span></div>`;
  }
  if (z && z.nearest) {
    return `<div class="zonecard"><b>Nearest hot zone: ${esc(z.nearest.name)}</b><span>${z.nearest.miles} mi away, +$${z.nearest.bonus} per order</span></div>`;
  }
  return '';
}

function streakBar(s) {
  if (!s.streakEvery) return '';
  const n = (s.streak || 0) % s.streakEvery;
  return `<div class="streak"><span>On-time streak</span><ol>${Array.from({ length: s.streakEvery }, (_, i) => `<li class="${i < n ? 'on' : ''}"></li>`).join('')}</ol><b>+${money(s.streakBonus)}</b></div>`;
}

function viewSearching(s) {
  return `
    <header class="app-head">${back('drivehome')}<div class="wordmark">${esc(S.cfg.app)}</div><span class="pill on">Clocked in</span></header>
    ${S.toast ? `<div class="toast">${esc(S.toast)}</div>` : ''}
    ${zoneCard()}
    ${S.zones.length ? miniMap('zones', 170) : `<div class="radar"><span></span><span></span><div class="dot"></div></div>`}
    <p class="searching-title">Looking for orders</p>
    <p class="searching-sub">${S.zoneStatus && S.zoneStatus.inZone ? 'Orders come a lot faster while you stay in the zone.' : 'Drive into a hot zone to get orders faster and earn more.'}</p>
    ${streakBar(s)}
    <div class="today" style="text-align:center">
      <div class="today-amt" style="font-size:34px">${money(s.today.earned)}</div>
      <div class="today-sub">${s.today.count} ${s.today.count === 1 ? 'delivery' : 'deliveries'} this session</div>
    </div>
    ${statStrip(s)}
    <button class="ghost" data-act="offline">Clock out</button>
  `;
}

function viewOffer(o) {
  const tipRow = o.tip > 0
    ? `<div class="tip"><dt>Customer tip${o.bigTip ? '<span class="hightip">High tipper</span>' : ''}</dt><dd>${money(o.tip)}</dd></div>`
    : `<div class="tip zero"><dt>Customer tip</dt><dd>No tip</dd></div>`;
  const who = o.player ? esc(o.customerName) : 'the customer';
  return `
    <div class="offer-top">
      <div class="offer-timer"><b data-offer-left>0:${String(S.offerTotal).padStart(2, '0')}</b> to respond${o.player ? '<span class="pill live">Player order</span>' : ''}</div>
      <div class="offer-total">${money(o.total)}</div>
      <div class="offer-guar">Guaranteed, tip included</div>
    </div>
    <dl class="breakdown">
      <div><dt>${esc(S.cfg.app)} pay</dt><dd>${money(o.base)}</dd></div>
      ${tipRow}
      ${o.hotBonus ? `<div class="hot"><dt>🔥 ${esc(o.hotZone)} hot zone</dt><dd>+${money(o.hotBonus)}</dd></div>` : ''}
    </dl>
    ${miniMap('offer', 130)}
    <ol class="route">
      <li><b>${esc(o.restaurant.label)}</b><span>Pickup in ${esc(o.restaurant.area)}</span></li>
      <li><b>${esc(o.dropoff.label)}</b><span>${o.faceToFace ? `Hand it to ${who}` : 'Leave it at the door'}${o.dropoff.area ? ', ' + esc(o.dropoff.area) : ''}</span></li>
    </ol>
    <div class="meta"><span><b>${o.miles} mi</b> total</span><span>Deliver within <b>${Math.ceil(o.eta / 60)} min</b></span></div>
    <p class="items">${itemsText(o.items)}</p>
    <div class="offer-actions">
      <button class="decline" data-act="decline">Decline</button>
      <button class="accept" data-act="accept"><span class="accept-fill" data-offer-bar></span><span class="accept-label">Accept</span></button>
    </div>
    <p class="fine">Declining lowers your acceptance rate.</p>
  `;
}

function photoTile(stage, label) {
  const p = S.photos[stage];
  if (!p) return `<div class="photo">${label}</div>`;
  if (p === 'taken') return `<div class="photo has">Photo taken<em>${label}</em></div>`;
  return `<div class="photo has"><img src="${p}" alt=""><em>${label}</em></div>`;
}

function conditionMeter() {
  const v = Math.round(S.condition);
  const cls = v < 45 ? 'bad' : v < 75 ? 'meh' : '';
  return `<div class="cond ${cls}"><div class="cond-head"><span>Food condition</span><b data-cond>${v}%</b></div><div class="bar"><i data-cond-bar style="width:${v}%"></i></div></div>`;
}

function viewOrder(o) {
  const pickup = o.stage === 'pickup';
  const steps = pickup ? ['now', '', '', ''] : ['done', 'done', 'now', ''];
  const who = o.player ? esc(o.customerName) : 'the customer';
  const how = pickup
    ? `Someone from the restaurant has it ready outside. Take a photo when you grab it.`
    : o.faceToFace
      ? (o.player ? `${who} wants it handed to them. They ordered from here, so look for them nearby.` : `${who} asked you to hand it to them. They'll meet you at the door.`)
      : `Leave it at the door and take a photo so they know it arrived.`;
  return `
    <header class="order-head">
      <div><span class="label">Deliver within</span><span class="clock" data-deadline>--:--</span></div>
      <div class="order-pay">${money(o.total)}</div>
    </header>
    <ol class="steps">${steps.map((c) => `<li class="${c}"></li>`).join('')}</ol>
    ${pickup ? '' : conditionMeter()}
    ${miniMap('order', 170)}
    <div class="task">
      <div class="step-no">${pickup ? 'Pickup' : 'Dropoff'}${o.player ? ' for ' + who : ''}</div>
      <h2>${pickup ? esc(o.restaurant.label) : esc(o.dropoff.label)}</h2>
      <div class="where">${pickup ? esc(o.restaurant.area) : esc(o.dropoff.area)}</div>
      <p class="how ${!pickup && o.faceToFace ? 'f2f' : ''}">${how}</p>
      <button class="cta" data-act="gps">Set GPS</button>
    </div>
    <div class="photos">
      ${photoTile('pickup', 'Pickup')}
      ${o.faceToFace ? `<div class="photo">No photo needed</div>` : photoTile('dropoff', 'Dropoff')}
    </div>
    <p class="items">${itemsText(o.items)}</p>
    <button class="unassign ${S.armed ? 'armed' : ''}" data-act="unassign">
      ${S.armed ? 'Tap again to unassign. It counts as a decline.' : 'Unassign order'}
    </button>
  `;
}

function viewDelivered(r) {
  const notes = [];
  if (r.late > 0) notes.push(`${mmss(r.late)} late`);
  if (r.spilled) notes.push(r.condition != null ? `the food was at ${r.condition}%` : 'the food took a hit');
  const note = r.player
    ? `Waiting on ${esc(r.customerName)}'s rating`
    : notes.length ? 'Customer noted: ' + notes.join(' and ') : `Customer rated you ${r.stars} stars`;
  return `
    <div class="done">
      <div class="done-mark">✓</div>
      <h2>Delivered to ${esc(r.player ? r.customerName : r.dropoff)}</h2>
      <div class="done-total">${money(r.total)}</div>
      ${r.stars ? `<div class="done-stars">${starRow(r.stars)}</div>` : ''}
      <p class="done-note">${note}</p>
      <dl class="breakdown">
        <div><dt>${esc(S.cfg.app)} pay</dt><dd>${money(r.base)}</dd></div>
        <div class="tip ${r.tip > 0 ? '' : 'zero'}"><dt>Customer tip</dt><dd>${r.tip > 0 ? money(r.tip) : 'No tip'}</dd></div>
        ${r.hotBonus ? `<div class="hot"><dt>🔥 ${esc(r.hotZone)} hot zone</dt><dd>+${money(r.hotBonus)}</dd></div>` : ''}
        ${r.streakBonus ? `<div class="hot"><dt>On-time streak (${r.streakEvery} in a row)</dt><dd>+${money(r.streakBonus)}</dd></div>` : ''}
        ${r.condition != null ? `<div><dt>Food condition</dt><dd class="${r.condition < 45 ? 'bad' : r.condition < 75 ? 'meh' : ''}">${r.condition}%</dd></div>` : ''}
      </dl>
      ${r.ruined ? `<p class="heads-up">Your driving ruined the ${esc(r.ruined)}. The customer didn't get it.</p>` : ''}
      <div class="photos">
        ${photoTile('pickup', 'Pickup')}
        ${r.faceToFace ? `<div class="photo">Handed to customer</div>` : photoTile('dropoff', 'Dropoff')}
      </div>
      <button class="cta" data-act="continue">Keep dashing</button>
    </div>
  `;
}

function reviewList(reviews) {
  if (!reviews || !reviews.length) return `<div class="empty">No written reviews yet. Customers leave them after deliveries.</div>`;
  return `<ul class="reviews">${reviews.map((r) => `
    <li>
      <div class="rv-head"><span class="rv-stars">${starRow(r.stars)}</span><span class="rv-time">${ago(r.t)}</span></div>
      <p>${esc(r.text)}</p>
      <span class="rv-name">${esc(r.name)}</span>
    </li>`).join('')}</ul>`;
}

function viewRatings(s) {
  const cur = s.tier;
  return `
    <header class="app-head">${back('drivehome')}<h2 class="page-title">Ratings</h2><span></span></header>
    <div class="rating-big">
      <div class="num">${s.rating.toFixed(2)}</div>
      <div class="stars">${starRow(s.rating)}</div>
      <p>${s.ratingCount ? `Average of your last ${s.ratingCount} customer ratings` : 'Everyone starts at 5.00. Late or damaged orders pull it down.'}</p>
    </div>
    <div class="meter">
      <div class="meter-head"><span>Acceptance rate</span><b>${s.acceptance}%</b></div>
      <div class="bar ${s.acceptance < 50 ? 'low' : ''}"><i style="width:${s.acceptance}%"></i></div>
      <p>Based on your last ${s.window} offers. Declined, expired, and unassigned orders count against you.</p>
    </div>
    <h3 class="section">What customers say</h3>
    ${reviewList(s.reviews)}
    <h3 class="section">Tiers</h3>
    <ul class="tiers">
      ${s.tiers.map((t) => `
        <li class="${t.name === cur ? 'current' : ''}">
          <b>${esc(t.name)}</b>
          <span>${t.minDeliveries === 0 ? 'Where everyone starts' : `${t.minAcceptance}% acceptance, ${t.minRating.toFixed(1)} rating, ${t.minDeliveries} deliveries`}</span>
        </li>`).join('')}
    </ul>
    <p class="explain">Higher tiers see high-tip orders more often and wait less between offers. Lower tiers get more no-tip orders. You've made ${money(s.earned)} across ${s.deliveries} deliveries.</p>
  `;
}

/* ---------- customer views ---------- */
function statusLine(c) {
  switch (c.status) {
    case 'searching': return 'Finding you a driver';
    case 'accepted': return `${c.driverName || 'Your driver'} is heading to ${c.restaurant}`;
    case 'pickedup': return `${c.driverName || 'Your driver'} is on the way${c.driverMiles != null ? `, ${c.driverMiles} mi away` : ''}`;
    case 'arriving': return `${c.driverName || 'Your driver'} is pulling up`;
    default: return '';
  }
}

function loadMenu(force) {
  if (S.menuLoading || (S.menu && !force)) return;
  S.menuLoading = true;
  post('customer:menu').then((d) => {
    S.menuLoading = false;
    S.menu = d && d.restaurants ? d : { restaurants: [], drivers: 0, tips: [0], deliveryFee: 0, serviceRate: 0 };
    if (S.tip === null) S.tip = S.menu.defaultTip ? { pct: S.menu.defaultTip } : { amount: 0 };
    render();
  });
}

const shopData = () => S.menu && S.menu.restaurants.find((r) => r.i === S.shop);
const cartCount = () => Object.values(S.cart).reduce((a, b) => a + b, 0);
// Tip: a share of the food total, a typed-in amount, or nothing.
function tipAmount(subtotal) {
  const t = S.tip || { amount: 0 }, m = S.menu || {};
  const max = m.maxTip || 100;
  if (t.pct) return Math.min(max, Math.max(m.minTip || 1, Math.round((subtotal * t.pct) / 100)));
  return Math.min(max, Math.max(0, Math.floor(t.amount || 0)));
}

function cartTotals() {
  const shop = shopData();
  let subtotal = 0;
  if (shop) for (const m of shop.menu) subtotal += (S.cart[m.i] || 0) * m.price;
  const fee = subtotal > 0 ? S.menu.deliveryFee : 0;
  const service = Math.ceil(subtotal * S.menu.serviceRate);
  const tip = subtotal > 0 ? tipAmount(subtotal) : 0;
  return { subtotal, fee, service, tip, total: subtotal + fee + service + tip };
}

// ---- store cards (Order tab) ----
const mi = (m) => (m / 1609.34).toFixed(1);
function walkText(r) {
  const walk = Math.max(1, Math.round(r.meters / 80));            // ~80 m a minute on foot
  if (walk <= 15) return `${walk} min walk`;
  return `${Math.max(1, Math.round((r.meters * 1.3) / 800))} min drive`; // ~30 mph on the road
}
const distText = (m) => (m < 2000 ? `${Math.round(m)}m` : `${mi(m)} mi`);

// Banner: the store's own picture, or the map around it tinted in the store's colour
function bannerStyle(r, w, h) {
  const map = S.cfg.map;
  if (!map || !hasXY(r)) return '';
  const b = map.bounds, worldW = b.xMax - b.xMin;
  const size = worldW * 0.42;                       // px per world metre at this zoom
  const p = toMapPx(r), k = size / S.mapSize;
  const x = -(p.x * k - w / 2), y = -(p.y * k - h / 2);
  return `background-image:url('${esc(map.image)}');background-size:${size.toFixed(0)}px;background-position:${x.toFixed(0)}px ${y.toFixed(0)}px`;
}

function storeLogo(r, big) {
  if (r.logo) return `<span class="store-logo ${big ? 'big' : ''}"><img src="${esc(r.logo)}" alt="" onerror="this.parentNode.textContent='${esc(r.icon || r.label.charAt(0))}'"></span>`;
  return `<span class="store-logo ${big ? 'big' : ''}" style="--c:${esc(r.color || '#3B82F6')}">${esc(r.icon || r.label.charAt(0))}</span>`;
}

function storeBanner(r, h, big) {
  const pic = r.banner
    ? `<img class="banner-img" src="${esc(r.banner)}" alt="" onerror="this.remove()">`
    : `<span class="banner-map" style="${bannerStyle(r, big ? 300 : 280, h)}"></span>`;
  return `<div class="store-banner ${big ? 'big' : ''}" style="--c:${esc(r.color || '#3B82F6')};height:${h}px">
    ${pic}<span class="banner-tint"></span>${storeLogo(r, big)}
    ${r.open === false ? `<span class="open-pill closed">CLOSED</span>` : `<span class="open-pill"><i></i>OPEN</span>`}
  </div>`;
}

function storeCard(r) {
  return `<button class="store" data-act="shop" data-i="${r.i}">
    ${storeBanner(r, 112)}
    <span class="store-info"><span><b>${esc(r.label)}</b><small>${r.menu.length} items · ${walkText(r)}</small></span><i class="chev">›</i></span>
  </button>`;
}

function deliverTo() {
  const where = (S.menu && S.menu.street) || (S.pos && S.pos.area) || 'your location';
  return `<button class="deliver-to" data-act="refresh"><span class="pin">⬤</span>Deliver to ${esc(where)}<span class="re">⟳</span></button>`;
}

function topHead(title, sub = '') {
  return `<header class="dl-head"><h1>${esc(title)}</h1>${sub}</header>`;
}

function activeBanner() {
  const c = S.cust;
  if (!c) return '';
  return `<button class="banner" data-act="nav" data-nav="orders"><span class="banner-dot"></span><span><b>Your ${esc(c.restaurant)} order</b><small>${esc(statusLine(c))}</small></span><i class="chev">›</i></button>`;
}

function viewShops() {
  if (!S.menu) { loadMenu(); return `${topHead('Delivery', deliverTo())}<p class="muted loading">Loading restaurants…</p>`; }
  const m = S.menu;
  const open = m.restaurants.filter((r) => r.open !== false);
  const closed = m.restaurants.filter((r) => r.open === false);
  const drivers = m.drivers
    ? `${m.drivers} ${m.drivers === 1 ? 'driver' : 'drivers'} online`
    : m.npcCourier ? 'Couriers delivering' : 'No drivers online';
  return `
    ${topHead('Delivery', deliverTo())}
    ${activeBanner()}
    ${S.custToast ? `<div class="toast">${esc(S.custToast)}</div>` : ''}
    <p class="drivers ${m.drivers || m.npcCourier ? '' : 'none'}"><i></i>${drivers}</p>
    ${open.length ? `<div class="stores">${open.map(storeCard).join('')}</div>` : `<div class="empty">Everything nearby is closed right now. Check back later.</div>`}
    ${closed.length ? `
      <button class="closed-head ${S.showClosed ? 'on' : ''}" data-act="closed"><span>${closed.length} closed</span><i class="chev">›</i></button>
      ${S.showClosed ? `<ul class="closed-list">${closed.map((r) => `
        <li>${storeLogo(r)}<span><b>${esc(r.label)}</b><small>${r.opensAt ? `Opens ${esc(r.opensAt)}` : 'Closed'}${r.area ? ' · ' + esc(r.area) : ''}</small></span><em>${distText(r.meters)}</em></li>`).join('')}</ul>` : ''}` : ''}
  `;
}

// ---- Orders tab ----
const STATUS_TEXT = { active: 'On the way', delivered: 'Delivered', cancelled: 'Cancelled', ended: 'Ended' };
function recentList() {
  const list = (S.menu && S.menu.recent || []).filter((o) => !S.cust || o.id !== S.cust.id);
  if (!list.length) return '';
  return `<h3 class="section">Recent orders</h3><ul class="recent">${list.map((o) => `
    <li><span class="r-logo">${esc((o.restaurant || '?').charAt(0))}</span>
      <span><b>${esc(o.restaurant)}</b><small>${o.count} ${o.count === 1 ? 'item' : 'items'} · ${money(o.total)}${o.t ? ' · ' + timeOf(o.t) : ''}</small></span>
      <em class="st ${esc(o.status)}">${STATUS_TEXT[o.status] || esc(o.status)}</em></li>`).join('')}</ul>`;
}

function viewOrders() {
  if (!S.menu) loadMenu();
  return `
    ${topHead('Orders')}
    ${S.custToast ? `<div class="toast">${esc(S.custToast)}</div>` : ''}
    <div class="empty-state">
      <div class="es-icon">🧾</div>
      <b>No active orders</b>
      <p>Food you order shows up here, with your driver on the map.</p>
      <button class="cta" data-act="nav" data-nav="order">Find food</button>
    </div>
    ${recentList()}
  `;
}

function stepper(i, qty) {
  return `<div class="stepper"><button data-act="dec" data-i="${i}" aria-label="Remove one">−</button><span>${qty}</span><button data-act="inc" data-i="${i}" aria-label="Add one">+</button></div>`;
}

function viewMenu() {
  const shop = shopData();
  if (!shop) { S.cview = 'list'; return viewShops(); }
  const n = cartCount();
  return `
    <div class="menu-hero">${storeBanner(shop, 132, true)}${back('cview', 'data-v="list"')}</div>
    <h2 class="menu-title">${esc(shop.label)}</h2>
    <p class="muted shop-sub">${esc(shop.category)} · ${esc(shop.area)} · ${walkText(shop)}${shop.hours ? ` · ${esc(shop.hours)}` : ''}</p>
    ${shop.open === false ? `<div class="heads-up">Closed right now${shop.opensAt ? `, opens at ${esc(shop.opensAt)}` : ''}. You can look, but not order.</div>` : ''}
    <div class="grid">
      ${shop.menu.map((m) => {
        const q = S.cart[m.i] || 0;
        const src = imgFor(m.image || `${m.item}.png`);
        return `
        <div class="tile ${q ? 'in' : ''}">
          <div class="tile-img" data-initial="${esc(m.label.charAt(0))}">${src ? `<img src="${esc(src)}" alt="" onerror="this.remove()">` : ''}</div>
          <b>${esc(m.label)}</b>
          <span class="price">${money(m.price)}</span>
          ${shop.open === false ? '' : q ? stepper(m.i, q) : `<button class="add" data-act="inc" data-i="${m.i}">Add</button>`}
        </div>`;
      }).join('')}
    </div>
    ${n && shop.open !== false ? `<button class="cartbar" data-act="cview" data-v="cart"><span>View cart <em>${n}</em></span><b>${money(cartTotals().subtotal)}</b></button>` : ''}
  `;
}

function viewCart() {
  const shop = shopData();
  const t = cartTotals();
  if (!shop || !t.subtotal) { S.cview = 'menu'; return viewMenu(); }
  const lines = shop.menu.filter((m) => S.cart[m.i]);
  return `
    <header class="app-head">${back('cview', 'data-v="menu"')}<h2 class="page-title">Your cart</h2><span></span></header>
    ${S.custToast ? `<div class="toast">${esc(S.custToast)}</div>` : ''}
    <ul class="cart">
      ${lines.map((m) => `<li><span><b>${esc(m.label)}</b><small>${money(m.price)} each</small></span>${stepper(m.i, S.cart[m.i])}</li>`).join('')}
    </ul>
    <h3 class="section">Drop-off</h3>
    <div class="seg">
      <button class="${S.handoff === 'hand' ? 'on' : ''}" data-act="handoff" data-v="hand">Hand it to me</button>
      <button class="${S.handoff === 'door' ? 'on' : ''}" data-act="handoff" data-v="door">Leave it here</button>
    </div>
    <h3 class="section">Tip your driver</h3>
    <div class="chips">
      ${(S.menu.tipPercents || []).map((p) => `<button class="${S.tip && S.tip.pct === p ? 'on' : ''}" data-act="tip" data-v="${p}">${p}%<small>${money(Math.max(S.menu.minTip || 1, Math.round((t.subtotal * p) / 100)))}</small></button>`).join('')}
      <button class="${S.tip && S.tip.custom ? 'on' : ''}" data-act="tipcustom">Custom</button>
      <button class="${S.tip && !S.tip.pct && !S.tip.custom ? 'on' : ''}" data-act="tip" data-v="0">No tip</button>
    </div>
    ${S.tip && S.tip.custom ? `
    <label class="tip-custom">
      <span>$</span>
      <input id="tipInput" type="number" inputmode="numeric" min="0" max="${S.menu.maxTip || 100}" step="1" value="${esc(S.tipCustom)}" placeholder="Enter a tip">
    </label>` : ''}
    <p class="fine left">Drivers see the tip before accepting. The whole tip goes to them.</p>
    ${!S.menu.drivers && S.menu.npcCourier && !(t.tip > 0) ? `<p class="heads-up">No drivers are online, so a courier will bring this. Couriers are careless with no-tip orders, and part of it might not make it.</p>` : ''}
    <dl class="breakdown">
      <div><dt>Subtotal</dt><dd>${money(t.subtotal)}</dd></div>
      <div><dt>Delivery fee</dt><dd>${money(t.fee)}</dd></div>
      <div><dt>Service fee</dt><dd>${money(t.service)}</dd></div>
      <div><dt>Driver tip</dt><dd data-tip-amt>${money(t.tip)}</dd></div>
      <div class="total"><dt>Total</dt><dd data-total>${money(t.total)}</dd></div>
    </dl>
    <p class="fine left">Delivered to where you're standing now. Paid from your bank account.${!S.menu.drivers && S.menu.npcCourier ? ' No drivers are online, so a DoorDrop courier will deliver it.' : ''}</p>
    <button class="cta" data-act="place" ${S.placing ? 'disabled' : ''}>${S.placing ? 'Placing order…' : `Place order for ${money(t.total)}`}</button>
  `;
}

// typing a custom tip: update the numbers without re-rendering (keeps the cursor in the box)
function onTipInput(e) {
  const max = (S.menu && S.menu.maxTip) || 100;
  let v = Math.floor(Number(e.target.value) || 0);
  if (v > max) { v = max; e.target.value = String(max); }
  S.tipCustom = e.target.value;
  S.tip = { custom: true, amount: Math.max(0, v) };
  const t = cartTotals();
  const set = (sel, txt) => { const n = view.querySelector(sel); if (n) n.textContent = txt; };
  set('[data-tip-amt]', money(t.tip));
  set('[data-total]', money(t.total));
  set('[data-act="place"]', `Place order for ${money(t.total)}`);
}

const etaText = (sec) => (sec == null ? '' : sec < 60 ? 'under a minute' : `about ${Math.round(sec / 60)} min`);

function tracker(c) {
  if (c.status === 'searching') return '';
  const p = Math.round(Math.max(0, Math.min(1, c.progress || 0)) * 100);
  const vehicle = c.npc ? '🛵' : '🚗';
  const sub = c.status === 'accepted'
    ? `Picking up at ${esc(c.restaurant)}${c.eta != null ? `, arriving in ${etaText(c.eta)}` : ''}`
    : c.status === 'arriving' ? 'Almost there. Look out for them.'
    : `${c.driverMiles ?? '?'} mi away, ${etaText(c.eta)}`;
  return `
    <div class="tracker">
      <div class="tk-row">
        <span class="tk-end" title="${esc(c.restaurant)}">${esc(c.restaurant.charAt(0))}</span>
        <div class="tk-line"><i style="width:${p}%"></i><span class="tk-dot" style="left:${p}%">${vehicle}</span></div>
        <span class="tk-end home">⌂</span>
      </div>
      <p class="tk-sub">${sub}</p>
      <p class="tk-map">Follow ${c.npc ? 'the courier' : esc(c.driverName || 'your driver')} live on your map.</p>
    </div>`;
}

function viewCustDone(c) {
  const short = c.missing && c.missing.length;
  return `
    <div class="done">
      <div class="done-mark ${short ? 'warn' : ''}">${short ? '!' : '✓'}</div>
      <h2>${short ? 'Your order came up short' : 'Enjoy your food'}</h2>
      <p class="done-note">${esc(c.note || `${c.driverName} delivered your ${c.restaurant} order.`)} It's in your inventory.</p>
      <p class="items dark center">${itemsText(c.items)}</p>
      ${short ? `
      <div class="missing">
        <b>Missing from the bag</b>
        <ul>${c.missing.map((m) => `<li>${m.qty}× ${esc(m.label)}</li>`).join('')}</ul>
        <p>${c.refunded ? `${money(c.refunded)} was refunded to your bank.` : 'Couriers go the extra mile for orders with a tip.'}</p>
      </div>` : ''}
      <button class="cta" data-act="custdone">Done</button>
    </div>`;
}

function viewTracking(c) {
  const idx = { searching: 0, accepted: 1, pickedup: 2, arriving: 2 }[c.status] ?? 0;
  const canCancel = c.status === 'searching' || c.status === 'accepted' || c.status === 'pickedup';
  const late = c.status === 'pickedup';
  const lateBack = Math.round((c.total || 0) * (S.cfg.lateCancelRefund || 0));
  const armedText = !late ? 'Tap again to cancel. You get a full refund.'
    : lateBack > 0 ? `Your food's already picked up. Tap again to cancel and get ${money(lateBack)} back.`
    : "Your food's already picked up, so there's no refund. Tap again to cancel anyway.";
  return `
    ${topHead('Orders')}
    ${c.status === 'searching' ? `<div class="radar small"><span></span><span></span><div class="dot"></div></div>` : ''}
    <h2 class="track-title">${esc(statusLine(c))}</h2>
    <ol class="steps three">${[0, 1, 2].map((i) => `<li class="${i < idx ? 'done' : i === idx ? 'now' : ''}"></li>`).join('')}</ol>
    ${miniMap('track', 190)}
    ${tracker(c)}
    <div class="task">
      <div class="step-no">${esc(c.restaurant)}, ${esc(c.area)}</div>
      <p class="items dark">${itemsText(c.items)}</p>
      <p class="how">${c.handoff === 'door'
        ? `Your driver will leave it where you ordered from${c.street ? ` on ${esc(c.street)}` : ''}.`
        : `Your driver will hand it to you. Stay near where you ordered${c.street ? ` on ${esc(c.street)}` : ''}.`}</p>
    </div>
    <dl class="breakdown">
      <div><dt>Food</dt><dd>${money(c.subtotal)}</dd></div>
      <div><dt>Fees</dt><dd>${money(c.deliveryFee + c.serviceFee)}</dd></div>
      <div><dt>Driver tip</dt><dd>${money(c.tip)}</dd></div>
      <div class="total"><dt>Paid</dt><dd>${money(c.total)}</dd></div>
    </dl>
    ${canCancel ? `<button class="unassign ${S.custArmed ? 'armed' : ''}" data-act="ccancel">
      ${S.custArmed ? armedText : 'Cancel order'}</button>` : ''}
    ${recentList()}
  `;
}

function viewRate(r) {
  return `
    <div class="done">
      <div class="done-mark">✓</div>
      <h2>Your ${esc(r.restaurant)} order arrived</h2>
      ${r.condition != null && r.condition < 75 ? `<div class="missing"><b>It arrived in rough shape (${r.condition}%)</b><p>${r.ruined ? `The ${esc(r.ruined)} was ruined on the way and didn't make it.` : 'Things got shaken up on the drive.'}</p></div>` : ''}
      <p class="done-note">How did ${esc(r.driverName)} do?</p>
      <div class="rate-stars">
        ${[1, 2, 3, 4, 5].map((i) => `<button class="${i <= S.rateStars ? 'on' : ''}" data-act="star" data-v="${i}" aria-label="${i} stars">★</button>`).join('')}
      </div>
      <textarea id="rateText" maxlength="200" placeholder="Leave a review (optional)">${esc(S.rateText)}</textarea>
      <button class="cta" data-act="rate" ${S.rateStars ? '' : 'disabled'}>Submit review</button>
      <button class="unassign" data-act="rateskip">Skip</button>
    </div>
  `;
}

/* ---------- render ---------- */
// Which bottom tab fits what's going on right now
function autoNav() {
  const s = S.snap;
  if (S.offer || S.order || S.result || (s && s.online)) return 'drive';
  if (S.cust || S.rateFor || S.custDone) return 'orders';
  return S.cfg.ordering ? 'order' : 'drive';
}

const TAB_ICONS = {
  order: '<svg viewBox="0 0 24 24"><path d="M6 7h12l-1 13H7L6 7Z"/><path d="M9 7a3 3 0 0 1 6 0" fill="none"/></svg>',
  orders: '<svg viewBox="0 0 24 24"><path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6" fill="none"/></svg>',
  drive: '<svg viewBox="0 0 24 24"><circle cx="6" cy="17" r="3" fill="none"/><circle cx="18" cy="17" r="3" fill="none"/><path d="M6 17h6l3-7h3M11 8h4" fill="none"/></svg>',
};

function renderTabs(show) {
  const items = [S.cfg.ordering && ['order', 'Order'], S.cfg.ordering && ['orders', 'Orders'], ['drive', 'Drive']].filter(Boolean);
  if (!tabs.dataset.built || tabs.dataset.built !== String(items.length)) {
    tabs.innerHTML = items.map(([k, label]) => `<button data-act="nav" data-nav="${k}">${TAB_ICONS[k]}<span>${label}</span></button>`).join('');
    tabs.dataset.built = String(items.length);
  }
  tabs.classList.toggle('hide', !show);
  tabs.querySelectorAll('button').forEach((b) => b.classList.toggle('active', b.dataset.nav === S.nav));
}

function render() {
  const s = S.snap;
  if (!s) { tabs.classList.add('hide'); view.innerHTML = `<p class="muted loading">Loading…</p>`; return; }

  if (S.offer || S.order || S.result) S.nav = 'drive';
  if (!S.nav || (!S.cfg.ordering && S.nav !== 'drive')) S.nav = autoNav();
  S.role = S.nav === 'drive' ? 'driver' : 'customer';

  const driveHome = S.nav === 'drive' && !S.page && S.tab !== 'ratings' && !S.result && !S.order && !S.offer;
  // focused screens hide the bottom bar so nothing gets tapped by accident
  const focused = S.offer || S.order || S.result || (S.nav === 'orders' && (S.rateFor || S.custDone));
  renderTabs(!focused);

  let html, screen;
  view.classList.toggle('fullbleed', driveHome);
  if (S.nav === 'drive') {
    if (S.page === 'earnings') { html = viewHome(s); screen = 'earnings'; }
    else if (driveHome) { html = viewMapHome(s); screen = 'home'; }
    else if (S.tab === 'ratings' && !S.offer) { html = viewRatings(s); screen = 'ratings'; }
    else if (S.result) { html = viewDelivered(S.result); screen = 'done'; }
    else if (S.order) { html = viewOrder(S.order); screen = `order${S.order.id}`; }
    else { html = viewOffer(S.offer); screen = `offer${S.offer.id}`; }
  } else if (S.nav === 'orders') {
    if (S.custDone) { html = viewCustDone(S.custDone); screen = 'cdone'; }
    else if (S.rateFor) { html = viewRate(S.rateFor); screen = 'rate'; }
    else if (S.cust) { html = viewTracking(S.cust); screen = 'track'; }
    else { html = viewOrders(); screen = 'orders'; }
  } else {
    if (S.cview === 'menu') html = viewMenu();
    else if (S.cview === 'cart') html = viewCart();
    else html = viewShops();
    screen = 'order-' + S.cview;
  }
  // a different screen starts at the top (keep your scroll when the same screen just updates)
  const jump = screen !== S.lastScreen;
  S.lastScreen = screen;
  view.innerHTML = html;
  if (jump) view.scrollTop = 0;
  const hm = view.querySelector('.home-map'), sheet = view.querySelector('.sheet');
  if (hm && sheet) hm.dataset.padb = String(sheet.offsetHeight - 18);
  refreshMaps();
  // typing inside the phone: ask the phone to keep keyboard focus so keys don't reach the game
  view.querySelectorAll('input, textarea').forEach((f) => {
    f.addEventListener('focus', () => { try { if (typeof setKeepInput === 'function') setKeepInput(true); } catch (e) {} });
    f.addEventListener('blur', () => { try { if (typeof setKeepInput === 'function') setKeepInput(false); } catch (e) {} });
  });
  const ta = $('#rateText');
  if (ta) ta.addEventListener('input', () => { S.rateText = ta.value; });
  const ti = $('#tipInput');
  if (ti) {
    ti.addEventListener('input', onTipInput);
    if (S.focusTip) { S.focusTip = false; ti.focus(); }
  }
  tick();
}

function tick() {
  const now = Date.now();
  $('#clock').textContent = new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }).replace(/\s?[AP]M/, '');
  if (S.offer) {
    const left = Math.max(0, (S.offerEnd - now) / 1000);
    const el = view.querySelector('[data-offer-left]');
    if (el) el.textContent = mmss(Math.ceil(left));
    const bar = view.querySelector('[data-offer-bar]');
    if (bar) bar.style.width = (left / S.offerTotal) * 100 + '%';
  }
  if (S.order) {
    const left = (S.orderDeadline - now) / 1000;
    const el = view.querySelector('[data-deadline]');
    if (el) { el.textContent = mmss(Math.ceil(left)); el.classList.toggle('late', left < 0); }
  }
}
setInterval(tick, 200);

/* ---------- input ---------- */
view.addEventListener('click', onAct);
tabs.addEventListener('click', onAct);

function onAct(e) {
  const btn = e.target.closest('[data-act]');
  if (!btn || btn.disabled || (!EMBEDDED && S.mode !== 'open')) return;
  const act = btn.dataset.act;
  const v = btn.dataset.v;
  const i = Number(btn.dataset.i);
  if (act !== 'unassign') S.armed = false;
  if (act !== 'ccancel') S.custArmed = false;

  switch (act) {
    // navigation
    case 'dash':
      S.nav = 'drive'; S.tab = 'dash'; S.toast = null; S.page = null;
      post('toggleOnline', { online: true });
      break;
    case 'menu': S.nav = 'drive'; S.page = 'earnings'; break;
    case 'ratings': S.nav = 'drive'; S.page = null; S.tab = 'ratings'; break;
    case 'drivehome': S.nav = 'drive'; S.page = null; S.tab = 'dash'; break;
    case 'nav': {
      const to = btn.dataset.nav;
      if (to === S.nav && to === 'order') S.cview = 'list';        // tapping Order again goes back to the list
      if (to === 'drive' && S.nav === 'drive') { S.page = null; S.tab = 'dash'; }
      if (to !== 'drive') S.custToast = null;
      if (to === 'drive') S.toast = null;
      S.nav = to;
      if (to !== 'drive') loadMenu(true);
      break;
    }
    case 'refresh': loadMenu(true); break;
    case 'closed': S.showClosed = !S.showClosed; break;
    case 'cview': S.cview = v; S.custToast = null; break;

    // driver
    case 'online': S.toast = null; post('toggleOnline', { online: true }); break;
    case 'offline': S.toast = null; post('toggleOnline', { online: false }); break;
    case 'accept': post('respond', { accept: true }); break;
    case 'decline': post('respond', { accept: false }); break;
    case 'gps': post('gps'); break;
    case 'continue': S.result = null; S.photos = {}; post('dismissResult'); break;
    case 'unassign':
      if (S.armed) { S.armed = false; post('unassign'); } else S.armed = true;
      break;

    // customer
    case 'shop':
      if (S.shop !== i) S.cart = {};
      S.shop = i; S.cview = 'menu';
      break;
    case 'inc': {
      const total = cartCount();
      if (total >= (S.menu.maxItems || 15)) { S.custToast = `Max ${S.menu.maxItems} items per order.`; break; }
      S.cart[i] = Math.min((S.cart[i] || 0) + 1, S.menu.maxQty || 10);
      break;
    }
    case 'dec':
      S.cart[i] = Math.max(0, (S.cart[i] || 0) - 1);
      if (!S.cart[i]) delete S.cart[i];
      break;
    case 'handoff': S.handoff = v; break;
    case 'tip': S.tip = Number(v) > 0 ? { pct: Number(v) } : { amount: 0 }; break;
    case 'tipcustom': S.tip = { custom: true, amount: Number(S.tipCustom) || 0 }; S.focusTip = true; break;
    case 'place':
      S.placing = true; S.custToast = null;
      post('customer:place', { restaurant: S.shop, items: S.cart, tip: cartTotals().tip, handoff: S.handoff }).then((r) => {
        if (r && !r.ok && /closed/i.test(r.reason || '')) loadMenu(true);
        S.placing = false;
        if (r && r.ok) { S.cust = r.order; S.cart = {}; S.cview = 'list'; S.nav = 'orders'; }
        else S.custToast = (r && r.reason) || 'Could not place the order.';
        render();
      });
      break;
    case 'ccancel':
      if (!S.custArmed) { S.custArmed = true; break; }
      S.custArmed = false;
      post('customer:cancel').then((r) => {
        if (r && r.ok) { S.cust = null; S.menu = null; S.custToast = r.message || 'Order cancelled.'; loadMenu(true); }
        else S.custToast = (r && r.reason) || 'Could not cancel.';
        render();
      });
      break;
    case 'custdone': S.custDone = null; loadMenu(true); break;
    case 'star': S.rateStars = Number(v); break;
    case 'rate':
    case 'rateskip':
      post('customer:rate', { stars: act === 'rate' ? S.rateStars : 0, text: act === 'rate' ? S.rateText : '' });
      S.custToast = act === 'rate' ? 'Thanks for the review.' : null;
      S.rateFor = null; S.rateStars = 0; S.rateText = '';
      loadMenu(true);
      break;
  }
  render();
}

document.addEventListener('keydown', (e) => {
  if (!EMBEDDED && e.key === 'Escape' && S.mode === 'open') post('close');
});

/* ---------- messages from Lua ---------- */
function applySnapshot(snap) {
  S.snap = snap;
  if (!snap) return;
  S.cust = snap.customer || null;
  if (snap.rateable && !S.rateFor) S.rateFor = snap.rateable;
}

/* ---------- offer ringtone (our own page only, so it never plays twice) ---------- */
let ringAudio = null;
function playSound(d) {
  if (EMBEDDED) return;
  if (ringAudio) { ringAudio.pause(); ringAudio = null; }
  if (!d || d.stop || !d.file) return;
  try {
    ringAudio = new Audio(d.file);
    ringAudio.volume = Math.max(0, Math.min(1, Number(d.volume ?? 0.45)));
    ringAudio.loop = !!d.loop;
    const p = ringAudio.play();
    if (p && p.catch) p.catch(() => {});
  } catch (e) { ringAudio = null; }
}

window.addEventListener('message', async ({ data: msg }) => {
  if (!msg || !msg.action) return;
  // our own page gets { action, data }; the phone forwards { action, payload }
  const d = msg.data ?? msg.payload ?? {};

  switch (msg.action) {
    case 'sound': playSound(d); return;
    case 'config':
      S.cfg = { ...S.cfg, ...d };
      $('#openKey').textContent = S.cfg.key;
      return;
    case 'phone': setMode(d.mode); return;
    case 'pos': {
      const areaChanged = !S.pos || S.pos.area !== d.area;
      S.pos = d;
      if (areaChanged && view.querySelector('.home')) render(); else refreshMaps();
      return;
    }
    case 'zones':
      S.zones = d.list || []; S.peak = !!d.peak;
      refreshMaps();
      return;
    case 'driverRoute':
      S.driverRoute = d;
      refreshMaps();
      return;
    case 'custNextRoute':
      S.custNext = d;
      refreshMaps();
      return;
    case 'zoneStatus': {
      const was = JSON.stringify(S.zoneStatus && [S.zoneStatus.inZone, S.zoneStatus.nearest && S.zoneStatus.nearest.name]);
      S.zoneStatus = d; if (d.zones) S.zones = d.zones;
      const now = JSON.stringify([d.inZone, d.nearest && d.nearest.name]);
      if (was !== now && (view.querySelector('.home') || (S.nav === 'drive' && !S.offer && !S.order && !S.result))) render(); else {
        const card = view.querySelector('.zonecard');
        if (card) { const t = document.createElement('div'); t.innerHTML = zoneCard(); card.replaceWith(t.firstElementChild || card); }
        refreshMaps();
      }
      return;
    }
    case 'condition': {
      S.condition = d.value;
      const b = view.querySelector('[data-cond]'), bar = view.querySelector('[data-cond-bar]');
      if (b && bar) {
        b.textContent = `${d.value}%`; bar.style.width = `${d.value}%`;
        b.closest('.cond').className = `cond ${d.value < 45 ? 'bad' : d.value < 75 ? 'meh' : ''}`;
      }
      return;
    }
    case 'hud':
      if (!EMBEDDED) renderHud(d && Object.keys(d).length ? d : null, msg.shift, msg.cfg);
      return;
    case 'flash': flash(); return;
    case 'state': applySnapshot(d); break;
    case 'sync':
      if (d.snapshot) applySnapshot(d.snapshot);
      S.offer = d.offer || null;
      if (S.offer) { S.offerTotal = d.offerTotal || 30; S.offerEnd = Date.now() + (d.offerLeft || 0) * 1000; }
      if (d.order) { S.order = d.order; S.orderDeadline = Date.now() + d.order.deadlineIn * 1000; }
      else S.order = null;
      if ('result' in d) S.result = d.result || null;
      if (d.photos) {
        S.photos = {};
        for (const [stage, img] of Object.entries(d.photos)) {
          S.photos[stage] = typeof img === 'string' ? (await thumb(img)) || 'taken' : 'taken';
        }
      }
      if (!S.nav) S.nav = autoNav();
      break;
    case 'offer':
      S.mapView = {};
      S.offer = d.offer;
      S.offerTotal = d.total;
      S.offerEnd = Date.now() + d.left * 1000;
      S.result = null; S.toast = null; S.tab = 'dash'; S.page = null; S.nav = 'drive';
      break;
    case 'offerGone':
      S.offer = null;
      if (d.reason === 'expired') S.toast = 'That offer expired and counted as a decline.';
      if (d.reason === 'cancelled') S.toast = 'The customer cancelled that order.';
      break;
    case 'order':
      S.mapView = {};
      S.order = d;
      S.orderDeadline = Date.now() + d.deadlineIn * 1000;
      S.photos = {}; S.armed = false; S.result = null; S.toast = null; S.page = null; S.nav = 'drive';
      break;
    case 'stage': if (S.order) S.order.stage = d.stage; break;
    case 'orderCancelled':
      S.order = null; S.armed = false; S.photos = {};
      S.toast = d.reason || null;
      break;
    case 'delivered': S.order = null; S.result = d; break;
    case 'photo':
      S.photos[d.stage] = d.img ? (await thumb(d.img)) || 'taken' : 'taken';
      break;
    case 'customer':
      if (!d || !d.status) break;
      if (d.status === 'none') { S.cust = null; break; }
      if (S.custEnded && d.id === S.custEnded && d.status !== 'cancelled' && d.status !== 'delivered') return; // late update
      if (d.route === undefined && S.cust && S.cust.id === d.id) d.route = S.cust.route;
      else if (d.route === false) d.route = null;
      // same stage, tracker on screen: update it in place so the dot glides instead of jumping
      if (S.cust && S.cust.id === d.id && S.cust.status === d.status && S.nav === 'orders' && view.querySelector('.tracker')) {
        S.cust = d;
        const p = Math.round(Math.max(0, Math.min(1, d.progress || 0)) * 100) + '%';
        view.querySelector('.tk-line i').style.width = p;
        view.querySelector('.tk-dot').style.left = p;
        const tmp = document.createElement('div');
        tmp.innerHTML = tracker(d);
        view.querySelector('.tk-sub').innerHTML = tmp.querySelector('.tk-sub').innerHTML;
        const title = view.querySelector('.track-title');
        if (title) title.textContent = statusLine(d);
        refreshMaps();
        return;
      }
      if (d.status === 'cancelled' || d.status === 'delivered') S.custEnded = d.id;
      if (d.status === 'cancelled') { S.cust = null; S.custToast = d.reason || 'Your order was cancelled.'; S.menu = null; }
      else if (d.status === 'delivered' && d.npc) { S.cust = null; S.custDone = d; if (!S.offer && !S.order) S.nav = 'orders'; }
      else if (d.status === 'delivered') { S.cust = null; S.rateFor = { driverName: d.driverName, restaurant: d.restaurant, condition: d.condition, ruined: d.ruined }; if (!S.offer && !S.order) S.nav = 'orders'; }
      else S.cust = d;
      break;
  }
  render();
});

/* ---------- on-screen delivery timer (our own page only, never inside the phone) ---------- */
function renderHud(d, shift, cfg) {
  const el = document.getElementById('hud');
  if (!el) return;
  if (cfg) {
    el.style.setProperty('--hud-right', cfg.right || '2.5vw');
    el.style.setProperty('--hud-bottom', cfg.bottom || '30vh');
    el.style.setProperty('--hud-shift', cfg.phoneOpenRight || '390px');
    el.classList.toggle('compact', cfg.compact !== false);
  }
  el.classList.toggle('shift', !!shift);
  if (!d) { el.classList.remove('show'); return; }

  let top, time, place, sub, late = false;
  if (d.kind === 'driver') {
    late = d.left < 0;
    top = `<span class="hud-stage">${d.stage === 'pickup' ? 'Pick up' : d.handoff ? 'Hand off' : 'Drop off'}</span><span class="hud-pay">${money(d.pay)}</span>`;
    time = mmss(d.left);
    place = esc(d.place);
    sub = `${d.area ? esc(d.area) + ', ' : ''}${d.miles} mi away`;
  } else {
    top = `<span class="hud-stage">Your ${esc(d.restaurant || '')} order</span>`;
    time = d.status === 'searching' ? '--:--' : d.status === 'arriving' ? 'Now' : d.eta != null ? mmss(d.eta) : '--:--';
    place = d.status === 'searching' ? 'Finding a driver'
      : d.status === 'accepted' ? `${esc(d.name || 'Driver')} is picking it up`
      : d.status === 'arriving' ? `${esc(d.name || 'Driver')} is pulling up`
      : `${esc(d.name || 'Driver')} is on the way`;
    sub = d.miles != null && d.status !== 'searching' ? `${d.miles} mi away` : 'Hang tight';
  }
  const cond = d.kind === 'driver' && d.condition != null
    ? `<div class="hud-cond ${d.condition < 45 ? 'bad' : d.condition < 75 ? 'meh' : ''}"><span>Food</span><i><b style="width:${d.condition}%"></b></i><em>${d.condition}%</em></div>`
    : '';
  el.innerHTML = `
    <div class="hud-top">${top}</div>
    <div class="hud-time ${late ? 'late' : ''}">${time}</div>
    <div class="hud-label">${late ? 'Running late' : d.kind === 'driver' ? 'Time left' : 'Arriving in'}</div>
    <div class="hud-place">${place}</div>
    <div class="hud-sub">${sub}</div>${cond}`;
  el.classList.add('show');
}

/* ---------- boot ---------- */
if (EMBEDDED) {
  let booted = false;
  const boot = () => {
    if (booted) return;
    booted = true;
    S.mode = 'open';
    window.__dispatchAction = (action) => (action === 'GetCurrentRoute' ? '/' : undefined);
    window.__externalAppReady = true;
    try { if (typeof setExternalRouting === 'function') setExternalRouting(window.name, [{ path: '/', index: true }]); } catch (e) {}
    render();
    post('appLoaded');
  };
  window.LoadRoot = boot;
  setTimeout(boot, 1500);
} else {
  render();
}
