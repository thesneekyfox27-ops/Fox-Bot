/* WeatherSync :: NUI (panel, HUDs, sounds, toasts) */
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'weathersync';
const $ = (id) => document.getElementById(id);
const pad = (n) => String(n).padStart(2, '0');
const post = (name, data) => fetch(`https://${RES}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}),
}).catch(() => {});

let weatherTypes = [];
const state = { id: 'sunny', value: 'EXTRASUNNY', hour: 9, minute: 0, freeze: false, blackout: false,
    dynamic: false, isAdmin: true, restricted: true };

const entryById = (id) => weatherTypes.find(w => w.id === id);
const labelFor = (id) => (entryById(id) || {}).label || id;
const locked = () => state.restricted && !state.isAdmin;

/* ================= live sky ================= */
const GREY   = ['OVERCAST', 'CLOUDS', 'CLEARING', 'SMOG', 'RAIN', 'THUNDER'];
const RAINY  = ['RAIN', 'THUNDER'];
const SNOWY  = ['SNOW', 'SNOWLIGHT', 'BLIZZARD', 'XMAS'];
const FOGGY  = ['FOGGY', 'SMOG'];
const CLOUDY = ['CLOUDS', 'OVERCAST', 'CLEARING', 'RAIN', 'THUNDER', 'SMOG'];
const SKY = {
    day:   'linear-gradient(180deg,#2a6cb5,#6fb0e6 60%,#cfe4f5)',
    dawn:  'linear-gradient(180deg,#3b3a6b,#9b6a8f 45%,#f0b27a)',
    dusk:  'linear-gradient(180deg,#1f2a52,#7a4f78 45%,#e8804f)',
    night: 'linear-gradient(180deg,#070d1c,#11203f 65%,#1a2c4a)',
};
const SKY_GREY = {
    day:   'linear-gradient(180deg,#5b6675,#8b95a3 60%,#aeb6c0)',
    dawn:  'linear-gradient(180deg,#4a4858,#7c7585 55%,#a99a92)',
    dusk:  'linear-gradient(180deg,#33384a,#5f5564 55%,#8a6e62)',
    night: 'linear-gradient(180deg,#0a0e16,#1a2230 70%,#262f3c)',
};
const SKY_SCENARIO = {
    tornado:  'linear-gradient(180deg,#1a2417,#3f4a2c 50%,#5a5234)',
    flooding: 'linear-gradient(180deg,#0c1822,#243a44 55%,#3a5560)',
};
const dayPhase = (h) => (h >= 5 && h < 8) ? 'dawn' : (h >= 8 && h < 18) ? 'day' : (h >= 18 && h < 21) ? 'dusk' : 'night';

let thunderTimer = null;
function renderSky() {
    const ph = dayPhase(state.hour), grey = GREY.includes(state.value), scenario = !!SKY_SCENARIO[state.id];
    $('skyBody').style.background = SKY_SCENARIO[state.id] || (grey ? SKY_GREY[ph] : SKY[ph]);

    const cel = $('celestial'), night = ph === 'night';
    const t = Math.min(1, Math.max(0, (state.hour + state.minute / 60 - 5) / 16));
    cel.className = 'celestial ' + (night ? 'moon' : 'sun');
    cel.style.left = (12 + t * 76) + '%';
    cel.style.top = (night ? 26 : (70 - Math.sin(t * Math.PI) * 52)) + '%';
    cel.style.opacity = (grey || FOGGY.includes(state.value) || scenario) ? '0.2' : '1';

    $('clouds').classList.toggle('on', CLOUDY.includes(state.value) || scenario);
    $('clouds').classList.toggle('grey', grey || scenario);
    $('rain').classList.toggle('on', RAINY.includes(state.value) || scenario);
    $('snow').classList.toggle('on', SNOWY.includes(state.value));
    $('fog').classList.toggle('on', FOGGY.includes(state.value));
    $('weatherNow').textContent = labelFor(state.id);

    clearInterval(thunderTimer);
    const flash = $('flash');
    if (state.value === 'THUNDER') {
        thunderTimer = setInterval(() => {
            flash.classList.remove('strike'); void flash.offsetWidth; flash.classList.add('strike');
        }, state.id === 'tornado' ? 2600 : 4200);
    } else flash.classList.remove('strike');
}

function renderClock() {
    $('clock').textContent = `${pad(state.hour)}:${pad(state.minute)}`;
    $('freezeFlag').classList.toggle('on', !!state.freeze);
}

/* ================= weather buttons ================= */
function selectWeather(id) {
    if (locked()) return;
    const e = entryById(id);
    if (!e) return;
    post('setWeather', { id });
    state.id = id; state.value = e.value;
    markActive(); renderSky();
}

function weatherButton(w, featured) {
    const b = document.createElement('button');
    b.className = featured ? 'cond' + (w.sim ? ' sim' : '') : 'tile';
    b.dataset.id = w.id;
    b.innerHTML = `<span class="ico">${w.icon || ''}</span><span class="name"></span>` + (featured ? '<span class="desc"></span>' : '');
    b.querySelector('.name').textContent = w.label;
    if (featured) b.querySelector('.desc').textContent = w.desc || '';
    b.addEventListener('click', () => selectWeather(w.id));
    return b;
}

function buildWeather() {
    $('conditions').replaceChildren(...weatherTypes.filter(w => w.featured).map(w => weatherButton(w, true)));
    $('weatherGrid').replaceChildren(...weatherTypes.filter(w => !w.featured).map(w => weatherButton(w, false)));
    markActive();
}

function markActive() {
    document.querySelectorAll('.cond,.tile').forEach(el => el.classList.toggle('active', el.dataset.id === state.id));
}

/* ================= time ================= */
const slider = $('timeSlider');
function showTime(mins) {
    state.hour = Math.floor(mins / 60) % 24; state.minute = mins % 60;
    $('sliderReadout').textContent = `${pad(state.hour)}:${pad(state.minute)}`;
    renderClock(); renderSky();
}
function setSlider(mins) { slider.value = mins; showTime(mins); }
slider.addEventListener('input', () => showTime(+slider.value));
slider.addEventListener('change', () => { if (!locked()) post('setTime', { hour: state.hour, minute: state.minute }); });

function buildPresets(presets) {
    $('presets').replaceChildren(...(presets || []).map(p => {
        const c = document.createElement('button');
        c.className = 'chip'; c.textContent = p.label;
        c.addEventListener('click', () => {
            if (locked()) return;
            setSlider(p.hour * 60 + p.minute);
            post('setTime', { hour: p.hour, minute: p.minute });
        });
        return c;
    }));
}

/* ================= switches ================= */
const setToggle = (id, on) => { $(id).dataset.on = String(!!on); };

// flips the switch and tells the server; extra() can add data to the request
function wireToggle(id, callback, extra) {
    const el = $(id);
    el.addEventListener('click', () => {
        if (locked()) return;
        const next = el.dataset.on !== 'true';
        el.dataset.on = String(next);
        post(callback, Object.assign({ value: next }, extra ? extra(next) : {}));
    });
}
wireToggle('toggleFreeze', 'toggleFreeze');
wireToggle('toggleBlackout', 'toggleBlackout');
wireToggle('toggleDynamic', 'toggleDynamic');
wireToggle('toggleLightning', 'toggleLightning');
wireToggle('toggleAlert', 'toggleAlert', (on) => on ? { seconds: restartSeconds } : {});
wireToggle('togglePurge', 'togglePurge');   // enables the scheduled purge

// restart countdown length
let restartSeconds = 300;
const rsRange = $('rsRange');
const rsFmt = (t) => { const m = Math.floor(t / 60), s = t % 60; return m && s ? `${m}m ${s}s` : m ? `${m}m` : `${s}s`; };
function rsUpdate() {
    restartSeconds = parseInt(rsRange.value, 10) || 300;
    $('rsValue').textContent = rsFmt(restartSeconds);
    rsRange.style.setProperty('--rs-pct', ((restartSeconds - 5) / (3600 - 5) * 100) + '%');
}
rsRange.addEventListener('input', () => { if (locked()) { rsRange.value = restartSeconds; return; } rsUpdate(); });
rsUpdate();

/* ================= sounds ================= */
const clampVol = (v) => typeof v === 'number' ? Math.max(0, Math.min(1, v)) : 0.6;

function makeAudio(src, loop) {
    const a = new Audio(src);
    a.loop = !!loop; a.preload = 'auto'; a._want = false;
    a.addEventListener('error', () => { a._broken = true; });
    a.addEventListener('playing', () => { a._broken = false; });
    return a;
}

function playAudio(a, volume) {
    a._want = true;
    a.volume = clampVol(volume);
    try { if (a.error || a._broken) { a.load(); a._broken = false; } } catch (e) {}
    try { a.currentTime = 0; } catch (e) {}
    let p;
    try { p = a.play(); } catch (e) { return; }
    // a stop that lands while play() is still starting wins
    if (p && p.then) p.then(() => { if (!a._want) a.pause(); }).catch(() => {});
}

function stopAudio(a) {
    a._want = false;
    try { a.pause(); a.currentTime = 0; } catch (e) {}
}

// loops: don't restart if already playing, just adjust the volume
function startLoop(a, vol) {
    if (a._want && !a.paused && !a.error && !a._broken) { a.volume = clampVol(vol); return; }
    playAudio(a, vol);
}

const sirenAudio   = makeAudio('sounds/restart_siren.mp3', true);

// The siren loops for the whole countdown. It starts part-way into the clip so
// that its LAST play is a full one that finishes exactly as the server restarts
// (e.g. a 5:00 timer with a 3:04 siren: 1:56 of it, then the whole siren to 0).
function startSiren(vol, remaining) {
    const align = () => {
        const dur = sirenAudio.duration;
        if (!remaining || !isFinite(dur) || dur <= 0) return;
        const rem = remaining % dur;
        try { sirenAudio.currentTime = rem > 0.5 ? dur - rem : 0; } catch (e) {}
    };
    const wasPlaying = sirenAudio._want && !sirenAudio.paused;
    startLoop(sirenAudio, vol);
    if (wasPlaying && !remaining) return;   // just a volume change
    if (sirenAudio.readyState >= 1) align();
    else sirenAudio.addEventListener('loadedmetadata', align, { once: true });
}
const warningAudio = makeAudio('sounds/tornado_warning.mp3', false);
const rumbleAudio  = makeAudio('sounds/storm_rumble.mp3', true);

// purge sounds come from config, created on demand; only one plays at a time
const purgeSounds = {};
function purgeAudio(file, loop) {
    if (!purgeSounds[file]) {
        const a = makeAudio('sounds/' + file, loop);
        a.addEventListener('error', () => console.error(`[weathersync] purge sound failed to load: sounds/${file} - check the filename in config and that the file is in html/sounds/`));
        purgeSounds[file] = a;
    }
    purgeSounds[file].loop = !!loop;
    return purgeSounds[file];
}
function startPurgeSound(file, vol, loop) {
    if (!file) return console.warn('[weathersync] purge sound skipped - no filename provided');
    for (const k in purgeSounds) if (k !== file) stopAudio(purgeSounds[k]);
    const a = purgeAudio(file, loop);
    if (loop) startLoop(a, vol);
    else { stopAudio(a); playAudio(a, vol); }
}
function stopPurgeSounds() { for (const k in purgeSounds) stopAudio(purgeSounds[k]); }

/* ================= restart countdown HUD ================= */
let rhTimer = null, rhTotal = 0, rhRemain = 0;
function rhRender() {
    const r = Math.max(0, rhRemain);
    $('rhTime').textContent = `${pad(Math.floor(r / 60))}:${pad(r % 60)}`;
    $('rhFill').style.width = (rhTotal > 0 ? r / rhTotal * 100 : 0) + '%';
}
function stopRestartHud() {
    clearInterval(rhTimer); rhTimer = null;
    $('restartHud').classList.add('hidden');
}
function startRestartHud(seconds) {
    stopRestartHud();
    rhTotal = rhRemain = seconds;
    $('restartHud').classList.remove('hidden');
    rhRender();
    rhTimer = setInterval(() => {
        rhRemain--; rhRender();
        if (rhRemain <= 0) {
            clearInterval(rhTimer); rhTimer = null;
            setTimeout(() => $('restartHud').classList.add('hidden'), 2500);
        }
    }, 1000);
}

/* ================= Emergency Alert System banner ================= */
let ebsTimer = null, ebsOutTimer = null;
function showEbs(kind, title, heading, message, seconds) {
    const ebs = $('ebs');
    clearTimeout(ebsTimer); clearTimeout(ebsOutTimer);
    $('ebsTitle').textContent = title || 'EMERGENCY ALERT SYSTEM';
    $('ebsHeading').textContent = heading || '';
    $('ebsMsg').textContent = message || '';
    ebs.classList.remove('hidden', 'out', 'start', 'end');
    ebs.classList.add(kind === 'ending' ? 'end' : 'start');
    void ebs.offsetWidth;   // restart the slide-in on repeat broadcasts
    ebsTimer = setTimeout(() => {
        ebs.classList.add('out');
        ebsOutTimer = setTimeout(() => { ebs.classList.add('hidden'); ebs.classList.remove('out'); }, 450);
    }, (parseInt(seconds, 10) || 9) * 1000);
}

/* ================= toasts ================= */
const TOAST_ICON = { success: '✓', error: '!', warning: '!', primary: 'i' };
function showToast(text, kind) {
    if (!text) return;
    kind = TOAST_ICON[kind] ? kind : 'primary';
    const el = document.createElement('div');
    el.className = 'toast ' + kind;
    el.innerHTML = `<span class="t-ico">${TOAST_ICON[kind]}</span><span class="t-msg"></span>`;
    el.querySelector('.t-msg').textContent = text;
    const box = $('toasts');
    box.appendChild(el);
    while (box.children.length > 4) box.firstChild.remove();
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 320); }, 3400);
}

/* ================= open / close ================= */
function applyLock() {
    document.querySelector('.console').classList.toggle('locked', locked());
    $('lockBanner').classList.toggle('hidden', !locked());
}
function close() { $('app').classList.add('hidden'); post('close'); }
$('closeBtn').addEventListener('click', close);
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !$('app').classList.contains('hidden')) close(); });

function open(d) {
    weatherTypes = d.weatherTypes || [];
    Object.assign(state, {
        id: d.currentId, value: d.currentValue, freeze: d.freeze, blackout: d.blackout, dynamic: d.dynamic,
        alert: d.alert, isAdmin: d.isAdmin, restricted: d.restricted,
    });
    buildWeather();
    buildPresets(d.timePresets);
    setSlider(d.hour * 60 + d.minute);
    setToggle('toggleFreeze', d.freeze);
    setToggle('toggleBlackout', d.blackout);
    setToggle('toggleDynamic', d.dynamic);
    setToggle('toggleAlert', d.alert);
    setToggle('toggleLightning', d.lightning);
    setToggle('togglePurge', d.purge);
    applyLock();
    $('app').classList.remove('hidden');
}

/* ================= messages from Lua ================= */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    switch (d.action) {
        case 'open': open(d); break;
        case 'close': $('app').classList.add('hidden'); break;
        case 'updateWeather':
            state.id = d.id; state.value = d.value; state.blackout = d.blackout;
            setToggle('toggleBlackout', d.blackout); markActive(); renderSky(); break;
        case 'updateTime':
            state.freeze = d.freeze; setSlider(d.hour * 60 + d.minute); setToggle('toggleFreeze', d.freeze); break;
        case 'updateDynamic': state.dynamic = d.dynamic; setToggle('toggleDynamic', d.dynamic); break;
        case 'updateLightning': setToggle('toggleLightning', d.lightning); break;
        case 'updateAlert': state.alert = d.alert; setToggle('toggleAlert', d.alert); break;
        case 'updatePurge': setToggle('togglePurge', d.purge); break;
        case 'setAdmin': state.isAdmin = d.isAdmin; applyLock(); break;

        case 'restartHud': d.active ? startRestartHud(d.seconds) : stopRestartHud(); break;
        case 'purgeHud': break;   // the emergency broadcast is the only purge pop-up
        case 'purgeBroadcast': showEbs(d.kind, d.title, d.heading, d.message, d.seconds); break;
        case 'notify': showToast(d.text, d.kind); break;

        case 'purgeSiren': d.on ? startPurgeSound(d.sound, d.volume, d.loop) : stopPurgeSounds(); break;
        case 'playSiren': startSiren(d.volume, d.remaining); break;
        case 'stopSiren': stopAudio(sirenAudio); break;
        case 'playWarning': playAudio(warningAudio, d.volume); break;
        case 'startRumble': startLoop(rumbleAudio, d.volume); break;
        case 'stopRumble': stopAudio(rumbleAudio); break;
    }
});
