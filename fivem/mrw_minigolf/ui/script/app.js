const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'mrw_minigolf';
const $ = (id) => document.getElementById(id);

const post = (name, data = {}) =>
    fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((r) => r.json()).catch(() => null);

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

let L = {};                       // translated labels
const t = (k, fallback) => L[k] || fallback;
const fmt = (s, v) => String(s).replace('%s', v);

/* ------------------------------------------------------------ scorecard */
function renderScoreboard(item) {
    const holes = item.holes || 0;
    const rows = Array.isArray(item.rows) ? item.rows : [];
    const lbl = item.labels || {};

    let head = `<tr><th>${esc(lbl.hole || 'Hole')}</th>`;
    for (let h = 1; h <= holes; h++) head += `<th>${h}</th>`;
    head += `<th>${esc(lbl.total || 'Total')}</th></tr>`;

    const body = rows.map((r) => {
        const strokes = Array.isArray(r.strokes) ? r.strokes : [];
        let total = 0, cells = '';
        for (let h = 0; h < holes; h++) {
            const v = Number(strokes[h]) || 0;
            total += v;
            cells += v ? `<td>${v}</td>` : `<td class="empty">-</td>`;
        }
        const me = r.me || (item.myId && Number(r.id) === Number(item.myId));
        const tag = r.status === 'done' ? '<span class="tag done">done</span>'
            : r.status === 'quit' ? '<span class="tag quit">left</span>' : '';
        return `<tr class="${me ? 'me' : ''}"><td class="name">${esc(r.name)}${tag}</td>${cells}<td class="total">${total}</td></tr>`;
    }).join('');

    $('ScoreTable').innerHTML = head + body;
}

/* ------------------------------------------------------------ start card */
let startState = { players: [], picked: new Set(), max: 4, price: 0 };

function renderPlayers() {
    const box = $('sPlayers');
    const { players, picked, max } = startState;
    const full = 1 + picked.size >= max;

    box.innerHTML = players.length
        ? players.map((p) => `
            <div class="player ${picked.has(p.id) ? 'on' : ''} ${full ? 'full' : ''}" data-id="${Number(p.id)}">
                <span class="box"></span>${esc(p.name)}<span class="id">ID ${Number(p.id)}</span>
            </div>`).join('')
        : `<div class="nobody">${esc(t('menu_nobody', 'Nobody standing near you'))}</div>`;

    $('sMode').innerHTML = picked.size
        ? `${esc(t('menu_group', 'Playing with'))} <b>${picked.size}</b>`
        : esc(t('menu_solo', 'Playing solo'));
}

$('sPlayers').addEventListener('click', (e) => {
    const row = e.target.closest('.player');
    if (!row) return;
    const id = Number(row.dataset.id);
    if (startState.picked.has(id)) startState.picked.delete(id);
    else if (1 + startState.picked.size < startState.max) startState.picked.add(id);
    renderPlayers();
});

$('sRefresh').onclick = async () => {
    const players = (await post('refresh')) || [];
    startState.players = players;
    const here = new Set(players.map((p) => Number(p.id)));
    startState.picked.forEach((id) => { if (!here.has(id)) startState.picked.delete(id); });
    renderPlayers();
};

$('sStart').onclick = () => {
    $('Start').classList.add('hidden');
    post('start', { invite: [...startState.picked] });
};
$('sCancel').onclick = () => {
    $('Start').classList.add('hidden');
    post('cancel');
};

/* ------------------------------------------------------------ invite card */
let inviteTimer = null;
function closeInvite(accept) {
    clearInterval(inviteTimer);
    if ($('Invite').classList.contains('hidden')) return;
    $('Invite').classList.add('hidden');
    post('inviteAnswer', { accept });
}
$('iYes').onclick = () => closeInvite(true);
$('iNo').onclick = () => closeInvite(false);

/* -------------------------------------------------------------- quit card */
$('qYes').onclick = () => { $('Quit').classList.add('hidden'); post('quitAnswer', { quit: true }); };
$('qNo').onclick = () => { $('Quit').classList.add('hidden'); post('quitAnswer', { quit: false }); };

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('Start').classList.contains('hidden')) $('sCancel').onclick();
    else if (!$('Invite').classList.contains('hidden')) closeInvite(false);
    else if (!$('Quit').classList.contains('hidden')) $('qNo').onclick();
});

/* --------------------------------------------------------------- messages */
window.addEventListener('message', (event) => {
    const item = event.data || {};
    const status = item.status;
    if (item.labels) L = Object.assign(L, item.labels);

    switch (item.ui) {
        case 'Scoreboard':
            $('Scoreboard').classList.toggle('hidden', !status);
            if (status) renderScoreboard(item);
            break;

        case 'Power':
            $('Bar').classList.toggle('hidden', !status);
            if (item.data !== undefined && item.data <= 100) $('PowerBar').style.width = `${item.data}%`;
            break;

        case 'Start':
            if (!status) { $('Start').classList.add('hidden'); break; }
            startState = {
                players: Array.isArray(item.players) ? item.players : [],
                picked: new Set(), max: item.maxGroup || 4, price: item.price || 0,
            };
            $('sTitle').textContent = t('menu_title', 'Portside Minigolf');
            $('sPriceLabel').textContent = t('menu_price', 'Club rental');
            $('sPrice').textContent = `$${startState.price}`;
            $('sHoles').textContent = `${item.holes || 0} ${t('menu_holes', 'holes')}`;
            $('sInviteLabel').textContent = t('menu_invite', 'Bring friends:');
            $('sRefresh').textContent = t('menu_refresh', 'refresh');
            $('sStart').textContent = t('menu_start', 'Rent clubs & start');
            $('sCancel').textContent = t('menu_cancel', 'Cancel');
            renderPlayers();
            $('Start').classList.remove('hidden');
            break;

        case 'Invite': {
            $('iTitle').textContent = t('invite_title', 'Minigolf invite');
            $('iText').textContent = fmt(t('invite_text', '%s invited you to a round of minigolf.'), item.host);
            $('iYes').textContent = fmt(t('invite_accept', 'Join ($%s)'), item.price);
            $('iNo').textContent = t('invite_decline', 'No thanks');
            $('Invite').classList.remove('hidden');
            const total = Number(item.seconds) || 30;
            let left = total;
            $('iBar').style.width = '100%';
            clearInterval(inviteTimer);
            inviteTimer = setInterval(() => {
                left -= 1;
                $('iBar').style.width = `${Math.max(0, left / total * 100)}%`;
                if (left <= 0) closeInvite(false);
            }, 1000);
            break;
        }

        case 'Quit':
            $('qTitle').textContent = t('quit_title', 'Quit the game?');
            $('qText').textContent = fmt(t('quit_text', 'You have %s strokes so far.'), item.strokes || 0);
            $('qYes').textContent = t('quit_yes', 'Quit');
            $('qNo').textContent = t('quit_no', 'Keep playing');
            $('Quit').classList.remove('hidden');
            break;
    }
});
