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

let L = {};
const t = (k, fallback) => (L[k] && L[k] !== k ? L[k] : fallback);
const fmt = (s, v) => String(s).replace('%s', v);
const arr = (x) => (Array.isArray(x) ? x : []);

/* ================================================================ tickets */
function renderTickets(boxId, tickets, selectedId, onPick) {
    const box = $(boxId);
    box.innerHTML = tickets.map((tk) => `
        <div class="ticket ${tk.id === selectedId ? 'on' : ''}" data-id="${esc(tk.id)}">
            <span class="dot"></span>
            <span class="label">${esc(tk.label)}:</span>
            <span class="price">$${Number(tk.price) || 0}</span>
        </div>`).join('');
    box.onclick = (e) => {
        const row = e.target.closest('.ticket');
        if (row) onPick(row.dataset.id);
    };
}

/* ============================================================== scorecard */
// strokes can come as an array (live) or "3,2,0,..." (saved item metadata)
function strokesOf(x) {
    if (Array.isArray(x)) return x.map((v) => Number(v) || 0);
    if (typeof x === 'string') return x.split(',').map((v) => Number(v) || 0);
    if (x && typeof x === 'object') return Object.keys(x).sort((a, b) => a - b).map((k) => Number(x[k]) || 0);
    return [];
}

function fillCard({ course, name, strokes, holes, footer, leftEarly }) {
    holes = holes || strokes.length || 12;
    const half = Math.ceil(holes / 2);

    $('cCourse').textContent = String(course || 'Minigolf').toUpperCase();
    $('cTitle').textContent = t('card_title', 'Scorecard').toUpperCase();
    $('cNameLabel').textContent = `${t('card_name', "Participant's name")} :`;
    $('cName').textContent = name || '';

    const hn = t('card_holeno', 'Hole no').toUpperCase();
    const sc = t('card_score', 'Score').toUpperCase();
    const hole = t('hole', 'Hole').toUpperCase();
    let html = `<tr><th>${esc(hn)}:</th><th>${esc(sc)}:</th><th class="sep">${esc(hn)}:</th><th>${esc(sc)}:</th></tr>`;
    const cell = (i) => {
        if (i >= holes) return '<td class="sep"></td><td></td>';
        const v = strokes[i] || 0;
        return `<td>${esc(hole)} ${i + 1}:</td><td class="v ${v ? '' : 'empty'}">${v || '-'}</td>`;
    };
    for (let r = 0; r < half; r++) {
        const right = cell(r + half).replace('<td>', '<td class="sep">');
        html += `<tr>${cell(r)}${right}</tr>`;
    }
    $('cTable').innerHTML = html;

    $('cTotalLabel').textContent = t('card_total', 'Total').toUpperCase();
    $('cTotal').textContent = strokes.reduce((a, b) => a + b, 0);
    $('cFoot').innerHTML = footer || '';
    $('cStamp').textContent = t('card_left', 'left early').toUpperCase();
    $('cStamp').classList.toggle('hidden', !leftEarly);
}

function showCard(mode) {
    const wrap = $('CardWrap');
    wrap.classList.remove('hidden', 'peek', 'interactive');
    wrap.classList.add(mode);
}

/* live, while holding the scorecard key: your card + the group's totals */
function peekScorecard(item) {
    const rows = arr(item.rows);
    const me = rows.find((r) => r.me || (item.myId && Number(r.id) === Number(item.myId))) || rows[0];
    if (!me) return;
    L = Object.assign(L, item.labels || {});

    fillCard({ course: item.course, name: me.name, strokes: strokesOf(me.strokes), holes: item.holes });

    const side = $('cSide');
    if (rows.length > 1) {
        side.classList.remove('hidden');
        side.innerHTML = `<h4>${esc(t('card_group', 'Your group').toUpperCase())}</h4>` + rows.map((r) => {
            const total = strokesOf(r.strokes).reduce((a, b) => a + b, 0);
            const isMe = r === me;
            const left = r.status === 'quit' ? `<span class="left">${esc(t('card_left', 'left early'))}</span>` : '';
            return `<div class="row ${isMe ? 'me' : ''}"><span>${esc(r.name)}${left}</span><b>${total}</b></div>`;
        }).join('');
    } else {
        side.classList.add('hidden');
    }
    $('cButtons').classList.add('hidden');
    showCard('peek');
}

/* end of a round, or opened from the inventory item */
function openCard(card, canKeep) {
    fillCard({
        course: card.course, name: card.name, strokes: strokesOf(card.strokes), holes: card.holes,
        leftEarly: card.finished === false,
        footer: [
            card.date ? `<span>${esc(card.date)}</span>` : '',
            card.ticket ? `<span>${esc(t('card_ticket', 'Ticket'))}: <b>${esc(card.ticket)}</b></span>` : '',
        ].join(''),
    });

    const side = $('cSide');
    const group = String(card.group || '').split(';').map((s) => s.trim()).filter(Boolean);
    if (group.length) {
        side.classList.remove('hidden');
        side.innerHTML = `<h4>${esc(t('card_group', 'Your group').toUpperCase())}</h4>` + group.map((g) => {
            const m = g.match(/^(.*):\s*(\d+)(.*)$/);
            return m
                ? `<div class="row"><span>${esc(m[1])}<span class="left">${esc(m[3].replace(/[()]/g, '').trim())}</span></span><b>${esc(m[2])}</b></div>`
                : `<div class="row"><span>${esc(g)}</span></div>`;
        }).join('');
    } else {
        side.classList.add('hidden');
    }

    $('cButtons').classList.remove('hidden');
    $('cKeep').classList.toggle('hidden', !canKeep);
    $('cKeep').textContent = t('card_keep', 'Keep scorecard');
    $('cClose').textContent = t('card_close', 'Close');
    showCard('interactive');
}

function closeCard(keep) {
    if ($('CardWrap').classList.contains('hidden')) return;
    $('CardWrap').classList.add('hidden');
    post(keep ? 'keepCard' : 'closeCard');
}
$('cKeep').onclick = () => closeCard(true);
$('cClose').onclick = () => closeCard(false);

/* ============================================================ start board */
let startState = { players: [], picked: new Set(), max: 4, tickets: [], ticket: null };

function renderStart() {
    const { players, picked, max, tickets, ticket } = startState;
    renderTickets('sTickets', tickets, ticket, (id) => { startState.ticket = id; renderStart(); });

    const full = 1 + picked.size >= max;
    $('sPlayers').innerHTML = players.length
        ? players.map((p) => `
            <div class="player ${picked.has(p.id) ? 'on' : ''} ${full ? 'full' : ''}" data-id="${Number(p.id)}">
                <span class="box"></span>${esc(p.name)}<span class="id">#${Number(p.id)}</span>
            </div>`).join('')
        : `<span class="nobody">${esc(t('menu_nobody', 'Nobody standing near you'))}</span>`;

    const tk = tickets.find((x) => x.id === ticket);
    $('sStart').disabled = !tk;
    $('sStart').textContent = tk ? `${t('menu_start', 'Buy ticket & start')} - $${tk.price}` : t('menu_start', 'Buy ticket & start');
}

$('sPlayers').addEventListener('click', (e) => {
    const row = e.target.closest('.player');
    if (!row) return;
    const id = Number(row.dataset.id);
    if (startState.picked.has(id)) startState.picked.delete(id);
    else if (1 + startState.picked.size < startState.max) startState.picked.add(id);
    renderStart();
});

$('sRefresh').onclick = async () => {
    const players = arr(await post('refresh'));
    startState.players = players;
    const here = new Set(players.map((p) => Number(p.id)));
    startState.picked.forEach((id) => { if (!here.has(id)) startState.picked.delete(id); });
    renderStart();
};

$('sStart').onclick = () => {
    if (!startState.ticket) return;
    $('Start').classList.add('hidden');
    post('start', { invite: [...startState.picked], ticket: startState.ticket });
};
$('sCancel').onclick = () => { $('Start').classList.add('hidden'); post('cancel'); };

/* ================================================================ invite */
let inviteTimer = null, inviteTicket = null, inviteTickets = [];
function renderInviteTickets() {
    renderTickets('iTickets', inviteTickets, inviteTicket, (id) => { inviteTicket = id; renderInviteTickets(); });
    const tk = inviteTickets.find((x) => x.id === inviteTicket);
    $('iYes').disabled = !tk;
    $('iYes').textContent = tk ? `${t('invite_accept', 'Join')} - $${tk.price}` : t('invite_accept', 'Join');
}
function closeInvite(accept) {
    clearInterval(inviteTimer);
    if ($('Invite').classList.contains('hidden')) return;
    $('Invite').classList.add('hidden');
    post('inviteAnswer', { accept, ticket: inviteTicket });
}
$('iYes').onclick = () => { if (inviteTicket) closeInvite(true); };
$('iNo').onclick = () => closeInvite(false);

/* ================================================================== quit */
$('qYes').onclick = () => { $('Quit').classList.add('hidden'); post('quitAnswer', { quit: true }); };
$('qNo').onclick = () => { $('Quit').classList.add('hidden'); post('quitAnswer', { quit: false }); };

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('Start').classList.contains('hidden')) $('sCancel').onclick();
    else if (!$('Invite').classList.contains('hidden')) closeInvite(false);
    else if (!$('Quit').classList.contains('hidden')) $('qNo').onclick();
    else if ($('CardWrap').classList.contains('interactive')) closeCard(false);
});

/* ============================================================== messages */
window.addEventListener('message', (event) => {
    const item = event.data || {};
    const status = item.status;
    if (item.labels) L = Object.assign(L, item.labels);

    switch (item.ui) {
        case 'Scoreboard':
            // never cover an end-of-round card the player is looking at
            if ($('CardWrap').classList.contains('interactive')) break;
            if (status) peekScorecard(item);
            else $('CardWrap').classList.add('hidden');
            break;

        case 'Power':
            $('Bar').classList.toggle('hidden', !status);
            if (item.data !== undefined && item.data <= 100) $('PowerBar').style.width = `${item.data}%`;
            break;

        case 'Card':
            if (status && item.card) openCard(item.card, !!item.canKeep);
            break;

        case 'Start': {
            if (!status) { $('Start').classList.add('hidden'); break; }
            const tickets = arr(item.tickets);
            startState = {
                players: arr(item.players), picked: new Set(), max: item.maxGroup || 4,
                tickets, ticket: tickets.length ? tickets[0].id : null,
            };
            $('sTitle').textContent = t('pricing', 'Mini Golf Pricing').toUpperCase();
            $('sInfo').textContent = `${item.course || ''} · ${item.holes || 0} ${t('menu_holes', 'holes')}`;
            $('sInviteLabel').textContent = t('menu_invite', 'Bring friends:');
            $('sRefresh').textContent = t('menu_refresh', 'refresh');
            $('sCancel').textContent = t('menu_cancel', 'Cancel');
            renderStart();
            $('Start').classList.remove('hidden');
            break;
        }

        case 'Invite': {
            inviteTickets = arr(item.tickets);
            inviteTicket = inviteTickets.length ? inviteTickets[0].id : null;
            $('iTitle').textContent = t('invite_title', 'Minigolf invite').toUpperCase();
            $('iText').textContent = fmt(t('invite_text', '%s invited you to a round of minigolf.'), item.host);
            $('iNo').textContent = t('invite_decline', 'No thanks');
            renderInviteTickets();
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
            $('qTitle').textContent = t('quit_title', 'Quit the game?').toUpperCase();
            $('qText').textContent = fmt(t('quit_text', 'You have %s strokes so far.'), item.strokes || 0);
            $('qYes').textContent = t('quit_yes', 'Quit');
            $('qNo').textContent = t('quit_no', 'Keep playing');
            $('Quit').classList.remove('hidden');
            break;
    }
});
