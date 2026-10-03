# nrp-elevators

Elevator system for The Neighborhood RP. Everything is done in-game through
menus — no SQL, no escrow, no command spam, no config editing required.

## Install
1. Drop `nrp-elevators` into resources.
2. server.cfg (AFTER qb-core, ox_lib, ox_target):
   ensure nrp-elevators
3. Restart. Pier Motel elevator already works.

## For players
Walk up to an elevator point -> ox_target eye -> pick a floor. That's it.

## For admins — everything in-game
Press F7 (or /elevators once if you prefer) to open the Elevator Manager:

  + Create New Elevator        -> name it
  -> open it -> + Add Floor At My Position
     (stand at the spot, face the arrival direction, done)
  -> tap any floor to: rename, move point to where you're standing,
     teleport to it, job-lock it, or delete it
  -> rename / job-lock / delete whole elevators the same way

Everything saves instantly to elevators.json and syncs live to every
player on the server — no restarts needed.

The manager is a full custom UI (same style as the elevator panel):
list -> click an elevator -> everything editable on one screen:
name, job lock, one-click interaction mode buttons, add floor at your
position, and per-floor: MOVE HERE / TELEPORT / EDIT (label, exact
coords, jobs) / reorder arrows / DELETE (click twice to confirm).

F7 is rebindable per-player in GTA Settings > Key Bindings > FiveM.
Change the default in Config.Admin.keybind.

## IMPORTANT: after swapping logo.png or sound files
Fully restart the resource (or the server). FiveM caches NUI files —
if a replaced image/sound doesn't show up, restart the server and
reconnect. The logo file's EXTENSION must match Config.Panel.logo
(logo.png vs logo.jpg — a jpg renamed to .png still works, but if you
add a different extension, update the config value).

## Admin access = Discord ID allowlist
Open config.lua and put your Discord ID(s) in Config.Admin.discordIds:
  1. Discord > Settings > Advanced > Developer Mode ON
  2. Right click your name > Copy User ID
  3. Paste it in the list (with or without the discord: prefix)
QBCore groups still work as an optional fallback via Config.Admin.groups.

## Customization (config.lua)
- Config.Panel.theme      -> teal | amber | red | pink | purple | cyan | green | white | custom
- Config.Panel.customColor-> any hex when theme = 'custom'
- Config.Panel.position   -> right | left | center
- Config.Panel.topFloorFirst / showHereTag
- Config.Interaction      -> 'target' (ox_target) | 'marker' (glowing floor
                             marker + E) | 'textui' (E key) — global default.
                             Per-elevator override in the F7 menu ("Interaction Mode")
- Config.Marker           -> marker type / size / color / draw distance
- Config.CallAnimation    -> button-press animation before the panel opens
- Config.Transition       -> fade times, ride time per floor, freeze, sounds
- Config.Admin            -> permission groups, keybind, fallback command

## Sounds
Ships with two ready-made sounds in html/sounds/:
  ding.wav            -> elevator arrival chime
  elevator_moving.wav -> looping mechanical hum while riding
Drop in your own .wav / .ogg / .mp3 files and point Config.Sounds at them.
Each entry can be a custom file OR a native GTA sound, or false to mute.

The arrival ding is BROADCAST: everyone within Config.Sounds.arrival.radius
meters of the destination floor hears it (quieter with distance), so players
standing in the hallway hear the elevator arrive before someone steps out.

## Notes
- Job locks: whole elevator or single floors (locked floors show red ✕)
- Server validates every ride (job + proximity anti-teleport)
- Native GTA sounds, no audio files
- Collision-load wait after teleport so nobody falls through the map
