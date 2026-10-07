# WeatherSync v2.2 — Time & Weather Sync (QBCore / Standalone)

## What's new in 2.0
- **Swim in the flood.** Flood water is real GTA water and the game now swims you itself: real swim
  and dive animations, cars float and sink. The old fake-swim code forced animations that don't exist
  in GTA, which is what made you T-pose. If you're in deep water but still standing on the street,
  you're lifted up until the game switches you to swimming. `Config.Flood.buoyancy = false` still
  makes a lethal flood that drags you under.
- **Cleaner panel.** Two columns, with everything on one screen and no scrolling. Same buttons, same features.
- **Tidier code.** client/server/NUI reorganised and dead code removed. Every command, event and
  **config value is unchanged** — drop your old `config.lua` in if you edited it.
- The restart timer now drops below the purge banner when both are on screen.
- **The restart siren finishes right at the restart.** It loops during the countdown, but it's timed so
  the last play is a whole one that ends exactly as the server restarts. Players who join partway
  through hear it in sync.
- **Proper sounds for each event.** `purge_start`, `purge_end` and `restart_siren` used to be the same
  3-minute file (your Purge announcement). Now:
  - `purge_start.mp3`: The Purge announcement (69 s).
  - `purge_end.mp3`: the Purge siren, looped twice with a smooth blend and a fade-out (35 s).
  - `restart_siren.ogg`: an air-raid wail that loops with no gap (32 s).
  To use your own, drop a file in `html/sounds/` with the same name.
- Fixed a script error: `SetScenarioPedDensityMultipliersThisFrame` -> `...MultiplierThisFrame`
  (a typo carried over from the original, which stopped the flood's traffic removal).
- **You float to the top of the flood and stay swimming there.** If you get stuck under something,
  you're moved straight up to the surface.
- `storm_rumble` and `tornado_warning` are now .mp3 (the resource is about 20 MB smaller).


One panel, one command, **admin-only**. Everything an admin changes syncs to
every player in real time. Works on **QBCore** (its permissions) or
**standalone** (ACE perms).

## Admin-only access
The menu, the keybind, and the `/weather` & `/time` commands are all gated by a
server-side admin check (`Config.RestrictToAdmins = true`). A non-admin who runs
`/weathermenu` or presses the key gets "no permission" and the panel never
opens — the check happens on the server, so it can't be bypassed from the client.
- **QBCore:** the `admin` / `god` permission groups.
- **Standalone:** `add_ace group.admin weathersync.admin allow` in `server.cfg`.
- **Owner / specific people:** add their identifier to `Config.AdminIdentifiers`
  in `config.lua` (license/steam/discord/fivem). They can find theirs by running
  `/weathersync_whoami` in chat. This always grants access, even with no group/ACE.

## Open it
`/weathermenu` or **F7** (rebindable in GTA Settings). One panel holds quick
conditions, the full weather list, the time slider, and the toggles.

## Conditions
☀️ Sunny · ☁️ Cloudy · 🌧️ Heavy Rain · ⛈️ Thunderstorm · ❄️ Snow · 🌬️ Blizzard ·
🌪️ Tornado · 🌊 Flooding — plus all base GTA types in the list below.

Real synced effects per weather: ground snow + footprints, wind, rough ocean
waves, camera rumble.

## Realistic tornado — gd_tornado (pre-wired & confirmed)
Tornado/flooding always apply the built-in storm package (heavy sky, max wind,
rumble, rough seas). For an actual funnel, install
[glitchdetector/gd_tornado](https://github.com/glitchdetector/gd_tornado) — it's
already wired up:

1. Put the `gd_tornado` folder in `resources/`.
2. `server.cfg`: `ensure gd_tornado` **before** `ensure weathersync`.
3. That's it — nothing to edit.

When tornado weather is selected, WeatherSync's server fires gd_tornado's
confirmed events — `gd_tornado:summon` (spawns and syncs the funnel to every
player) and `gd_tornado:dismiss` when the weather changes. The config already
contains:

```lua
tornado = {
    enabled         = true,
    resource        = 'gd_tornado',          -- skipped unless this is running
    serverEvent     = 'gd_tornado:summon',   -- confirmed
    serverStopEvent = 'gd_tornado:dismiss',  -- confirmed
},
```
The hook only fires when `gd_tornado` is actually started, so it's safe to leave
on even before you install it. **Note:** gd_tornado spawns the funnel at one of
its preset map locations and doesn't re-sync players who join *after* it spawned
— that's a limitation of gd_tornado itself, not WeatherSync.

**If the console says `Couldn't find resource gd_tornado`:** the folder is named
wrong. GitHub's Download ZIP extracts as `gd_tornado-master` — rename it to
exactly `gd_tornado`, drop it in `resources/`, and keep `ensure gd_tornado`
above `ensure weathersync`. Until it loads, tornado weather just uses the
built-in storm effects.

**Note on CamxxCore's `TornadoScript.dll`:** that's a *singleplayer*
ScriptHookVDotNet (.NET) mod and **cannot run on a FiveM server** — FiveM doesn't
load `.dll` script plugins. `gd_tornado` is the FiveM Lua port of that exact mod,
so it's the one to use. (Its sounds were reused here for the tornado
warning + storm rumble.)

**Placement & no duplicates:** gd_tornado's client spawns a brand-new funnel on
every spawn event and never frees the old one, so the previous build (which fired
two events) could leave a duplicate. WeatherSync now drives gd_tornado directly,
deleting any existing funnel first and sending exactly **one** spawn — so you only
ever get a single tornado. It spawns a configurable distance from whoever
triggered it (`Config.TornadoSpawn.distance`, default **280m**). The triggering
client resolves the real **ground height** at that point and sends it back, so the
funnel **touches the ground** instead of floating at your elevation (important when
you trigger it from a rooftop or hill). `mode='coords'` always drops it downtown.
Test with `/tornadohere`.

**Making the funnel visible / in the city:** gd_tornado's default summon spawns
at distant preset spots, so it barely shows. WeatherSync now spawns it at exact
coordinates via `gd_tornado:summon_right_here`, controlled by `Config.TornadoSpawn`:
- `mode = 'player'` (default) drops it ~`distance` metres (60) from whoever
  triggered tornado weather — right in front of them, wherever they are.
- `mode = 'coords'` always spawns it at a fixed point (`coords`, default downtown
  Los Santos) so it's guaranteed in the city.
- `keepLocal = true` gives it a nearby destination so it lingers instead of
  drifting off to the countryside. Lower `distance` to make it scarier/closer
  (note: it starts pulling vehicles/peds at ~57 m).

## Server restart alert (siren + countdown + real restart)
Flip **Restart alert** in the panel to drop the world into an emergency: a
top-center **countdown timer** appears for every player, the air-raid siren
plays, the weather forces to an extreme storm, and the grid blacks out. Pick the
length with the **Restart in** chips (1/5/10/15/30 min) before toggling it on.

When the timer hits 0 the server runs `Config.RestartAlert.restartCommand`
(default `quit …`), which stops FXServer — and txAdmin / your host's supervisor
brings it straight back up, i.e. a **real restart**. Toggle the switch back off
any time to cancel; the timer stops and the previous weather is restored. Set
`restartCommand = ''` if you only want the warning with no actual restart.

It also auto-fires before a **txAdmin scheduled restart** (matching txAdmin's
remaining time); in that case txAdmin performs the restart, so WeatherSync won't
also quit. Tune everything under `Config.RestartAlert`.

### ⚠ Make the restart actually fire (required one-time setup)
A FiveM resource is **not allowed to run `quit` by default** — the command is
silently ignored, so the timer ends and nothing happens. Grant permission once by
adding this to your **server.cfg** (anywhere), then restart the server a single time:

```
add_ace resource.weathersync command.quit allow
```

Then:
1. Run **`/weathersync_testrestart`** in chat (or the server console) — it runs the
   restart command immediately. If permission is still missing it prints the exact
   `add_ace` line to add; if it's fine, the server quits right away.
2. `quit` stops FXServer. Your supervisor must relaunch it: **txAdmin does this
   automatically**. On a bare `run.cmd` with no loop it will just stay down — wrap
   it in a restart loop or let txAdmin manage the server.

If you'd rather txAdmin own the schedule, leave `restartCommand` as-is for manual
use and set txAdmin's scheduled restarts; WeatherSync's `autoTriggerSeconds` will
show the synced countdown + siren before txAdmin restarts.


## Weather visuals — Realistic Storm 2.0 (separate resource)
The weather XMLs are now bundled in a separate stream resource, **realistic_storm**
(`weather.xml`, `w_thunder.xml`, `thunder_render_drop.xml`). Drop that folder in
`resources/` and `ensure realistic_storm` — since Thunderstorm/Tornado/Flooding
all use THUNDER, they'll all render with the Realistic Storm look. See that
resource's own README for details.

## Flooding (rising water)
Selecting **Flooding** raises real water across the whole map using FiveM's water
natives. By default (`Config.Flood.useBigQuad = true`) it loads `flood.xml` — a
single map-wide water plane — and raises **that**, so the water rises uniformly
and actually covers the inland city instead of leaving a jagged sheet floating
over the coast.

- `targetRise` — how high the water climbs above sea level (default **75m**, enough
  to flood the whole low city). Push it toward 120 for a biblical, hills-too flood.
- The **Restart alert** now uses Flooding by default (`Config.RestartAlert.weatherId
  = 'flooding'`), so starting any restart timer makes the flood roll in as it counts
  down. Flooding also still works on its own from the weather tile.
- `rate` / `interval` — how fast it rises.
- When the weather changes away from Flooding, the water eases back down and
  `ResetWater()` restores the game's normal water.

**Test it from street level, not a rooftop.** From up high you're looking *down*
at the surface, so it reads as a flat plane below you; at ground level you'll see
the water actually rise up the buildings around you.

`flood.xml` (one giant quad, credit **tofu-dynamic-water / Nikez**) ships inside
the resource and is registered with `data_file 'WATER_FILE' 'flood.xml'` so the
load is reliable. WeatherSync calls `ResetWater()` on boot, so your normal ocean
and inland lakes are untouched until a flood actually runs.

**Swimming:** the flood is real GTA water, so the game swims you, lets you dive and runs its own
drowning, and cars float or sink. `Config.Flood.physics` keeps you on top: in deep water you rise to
the surface and stay swimming there, and if you're stuck for about a second you're moved up to the
surface. Health drains only if your head stays under for `breathSeconds`. `buoyancy = false` drags swimmers under for a lethal flood. If you ever
see a patchy, floating-sheet flood, you're on `useBigQuad = false` — set it back to true.


## Install
1. Put `weathersync` in `resources`.
2. `server.cfg`: `ensure weathersync`
3. Standalone admin perm: `add_ace group.admin weathersync.admin allow`

> Remove any other weather/time script first (qb-weathersync, vsync,
> cd_easytime) — two clock controllers will fight.

## Commands (all admin-only)
| Action | How |
|---|---|
| Open panel | `/weathermenu` or **F7** |
| Quick weather | `/weather <id>` e.g. `/weather snow`, `/weather tornado` |
| Quick time | `/time <hour> [minute]` e.g. `/time 20 30` |
| Drop tornado on you | `/tornadohere` (needs gd_tornado running) |

Ids: `sunny, cloudy, heavyrain, storm, snow, blizzard, tornado, flooding,
extrasunny, clear, clouds, overcast, smog, foggy, clearing, rain, thunder,
snowlight, xmas, halloween, neutral`

## Config highlights
- `Config.RestrictToAdmins` / `AdminGroups` / `AcePermission` — access control
- `Config.MillisecondsPerMinute` — clock speed (2000 ≈ 48-min day)
- `Config.DynamicTime` — clock advances on its own
- `Config.DynamicWeather` — auto weather that **follows the time of day**
  (edit `Config.DayCycleWeather` to tune what each part of the day rolls)
- `Config.RestartAlert` — siren + extreme-storm restart alert
- `Config.AddonEffects` — plug in gd_tornado / other effect resources
- `Config.WeatherTypes` — each `effects` table supports `wind`, `waves`,
  `snow`, `addon`  (camera shake removed)

## Notifications
WeatherSync's confirmations ("Weather set to…", "Restart alert…") are controlled by
`Config.Notify`:
- `'clean'` — built-in dark toasts that match the panel (default)
- `'qb'` — QBCore:Notify (the green boxes)
- `'chat'` — a line in chat
- `'off'` — no notifications at all

## Ground lightning
Toggle **Ground lightning** in the panel. While it's on and the weather is a
thunder type (Thunderstorm, Thunder, Tornado, Flooding), jagged bolts strike the
ground around each player — multiple per burst — with a sky flash on each burst.
Tune frequency, count, and range in `Config.Lightning` (`boltsPerBurst`,
`minDelay`/`maxDelay`, `radius`). `damage = true` lets a close strike injure/ignite
(off by default — purely visual otherwise).

## Flood: traffic + timed rise
- `Config.Flood.suppressTraffic = true` stops ambient cars/peds spawning during a
  flood, so nothing is seen driving through the water. (Real NPC cars can't be made
  to float client-side, so they're removed instead.)
- When the flood is triggered by the **restart timer**, it no longer rushes in: the
  water rises slowly across the whole countdown and peaks right at restart, so a
  5-minute timer creeps in over 5 minutes and players can evacuate. A standalone
  Flooding weather still uses the normal `Config.Flood.rate`.
