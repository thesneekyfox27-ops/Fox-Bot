const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nrp-barriers';

const $ = (id) => document.getElementById(id);
const app = $('app');
const list = $('list');

let walls = [];
let highlight = null;
let editing = null;      // index of the wall being renamed
let pendingDelete = null;

function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});
}

function esc(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
}

function fmtDist(m) {
    if (m < 1) return 'here';
    if (m < 1000) return `${Math.round(m)} m`;
    return `${(m / 1000).toFixed(1)} km`;
}

function render() {
    // do not rebuild while typing a new name, it would steal the focus
    if (editing !== null) return;

    const q = $('search').value.trim().toLowerCase();
    const sort = $('sort').value;

    let rows = walls.filter((w) =>
        !q || w.name.toLowerCase().includes(q) || String(w.index) === q);

    rows.sort((a, b) => {
        if (sort === 'name') return a.name.localeCompare(b.name);
        if (sort === 'index') return a.index - b.index;
        return a.distance - b.distance;
    });

    $('count').textContent = walls.length;
    $('empty').classList.toggle('hidden', walls.length > 0);

    list.innerHTML = rows.map((w) => `
        <li class="wall ${w.index === highlight ? 'hl' : ''}" data-i="${w.index}">
            <div class="top">
                <span class="num">#${w.index}</span>
                <span class="name" title="Double click to rename">${esc(w.name)}</span>
                <span class="dist">${fmtDist(w.distance)}</span>
            </div>
            <div class="meta">
                ${w.points} points &middot; ${w.height.toFixed(1)} m tall &middot;
                z ${w.zMin.toFixed(1)} &rarr; ${w.zMax.toFixed(1)} &middot;
                ${w.x.toFixed(0)}, ${w.y.toFixed(0)}
            </div>
            <div class="actions">
                <button class="btn tp" data-act="teleport">Teleport</button>
                <button class="btn hl ${w.index === highlight ? 'active' : ''}" data-act="highlight">Highlight</button>
                <button class="btn" data-act="rename">Rename</button>
                <button class="btn danger" data-act="delete">Delete</button>
            </div>
        </li>`).join('');
}

function startRename(li, index) {
    const w = walls.find((x) => x.index === index);
    if (!w) return;
    editing = index;

    const span = li.querySelector('.name');
    span.innerHTML = `<input type="text" maxlength="40" value="${esc(w.name)}">`;
    const input = span.querySelector('input');
    input.focus();
    input.select();

    const finish = (save) => {
        if (editing === null) return;
        const name = input.value.trim();
        editing = null;
        if (save && name && name !== w.name) {
            w.name = name;
            post('rename', { index, name });
        }
        render();
    };

    input.addEventListener('keydown', (e) => {
        e.stopPropagation();
        if (e.key === 'Enter') finish(true);
        if (e.key === 'Escape') finish(false);
    });
    input.addEventListener('blur', () => finish(true));
}

list.addEventListener('click', (e) => {
    const btn = e.target.closest('button');
    const li = e.target.closest('.wall');
    if (!btn || !li) return;

    const index = Number(li.dataset.i);
    const act = btn.dataset.act;

    if (act === 'teleport') post('teleport', { index });
    if (act === 'highlight') post('highlight', { index });
    if (act === 'rename') startRename(li, index);
    if (act === 'delete') {
        const w = walls.find((x) => x.index === index);
        pendingDelete = index;
        $('confirmText').innerHTML = `Delete <b>${esc(w ? w.name : '#' + index)}</b> for everyone? This can not be undone.`;
        $('confirm').classList.remove('hidden');
    }
});

list.addEventListener('dblclick', (e) => {
    const name = e.target.closest('.name');
    const li = e.target.closest('.wall');
    if (name && li) startRename(li, Number(li.dataset.i));
});

$('confirmNo').onclick = () => {
    pendingDelete = null;
    $('confirm').classList.add('hidden');
};

$('confirmYes').onclick = () => {
    if (pendingDelete !== null) post('delete', { index: pendingDelete });
    pendingDelete = null;
    $('confirm').classList.add('hidden');
};

$('close').onclick = () => post('close');
$('build').onclick = () => post('build');
$('toggleBlocking').onclick = () => post('toggleBlocking');
$('toggleOutlines').onclick = () => post('toggleOutlines');
$('search').addEventListener('input', render);
$('sort').addEventListener('change', render);

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('confirm').classList.contains('hidden')) {
        $('confirmNo').onclick();
        return;
    }
    post('close');
});

function setChip(el, label, on) {
    el.textContent = `${label}: ${on ? 'ON' : 'OFF'}`;
    el.classList.toggle('on', on);
    el.classList.toggle('off', !on);
}

window.addEventListener('message', (e) => {
    const d = e.data || {};

    if (d.action === 'open') {
        app.classList.remove('hidden');
        $('search').value = '';
    }

    if (d.action === 'close') {
        app.classList.add('hidden');
        $('confirm').classList.add('hidden');
        editing = null;
    }

    if (d.action === 'walls') {
        walls = d.walls || [];
        highlight = d.highlight ?? null;
        setChip($('toggleBlocking'), 'Blocking', !!d.blocking);
        setChip($('toggleOutlines'), 'Outlines', !!d.outlines);
        document.querySelector('.dot').classList.toggle('off', !d.blocking);
        render();
    }
});
