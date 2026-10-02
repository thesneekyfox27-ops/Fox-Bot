const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'mrw_minigolf';
const $ = (id) => document.getElementById(id);

/* the Crazy Golf logo lives in this file, so it shows even if the image file
   wasn't sent to the player (e.g. the server wasn't refreshed after an update) */
const LOGO = 'data:image/jpeg;base64,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';
document.querySelectorAll('img[data-logo]').forEach((img) => { img.src = LOGO; });

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

    $('cCourse').textContent = String(course || 'Crazy Golf').toUpperCase();
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

        case 'Controls':
            if (!status) { $('Controls').classList.add('hidden'); break; }
            $('ctlTitle').textContent = String(item.title || 'Controls').toUpperCase();
            $('ctlList').innerHTML = arr(item.items).map((c) => `
                <div class="ctl-row"><span class="ctl-key">${esc(c.key)}</span><span class="ctl-label">${esc(c.label)}</span></div>`).join('');
            $('Controls').classList.remove('hidden');
            break;

        case 'Quit':
            $('qTitle').textContent = t('quit_title', 'Quit the game?').toUpperCase();
            $('qText').textContent = fmt(t('quit_text', 'You have %s strokes so far.'), item.strokes || 0);
            $('qYes').textContent = t('quit_yes', 'Quit');
            $('qNo').textContent = t('quit_no', 'Keep playing');
            $('Quit').classList.remove('hidden');
            break;
    }
});
