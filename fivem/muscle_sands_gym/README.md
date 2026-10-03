# Muscle Sands Gym (Vespucci Beach)

Outdoor gym on the Vespucci boardwalk. Buy a day pass from the trainer, then walk
up to a station and press **E** to train. Your **strength** and **stamina** climb.
Works **standalone** and **auto-detects QBCore**.

## Install
1. Drop the `muscle_sands_gym` folder into your `resources` directory.
2. Add to `server.cfg`:
   ```
   ensure muscle_sands_gym
   ```
3. (QBCore only) Register the `gym_pass` item — see **Gym Pass** below.
4. Restart the server.

## Gym Pass
A trainer NPC stands at the gym (dumbbell blip on the map). Buy a pass from them:
- **qb-target** is used automatically if it's running; otherwise walk up and press **E**.
- The pass lasts for the **rest of the in-game day** it was bought on, then is
  **automatically removed** when that in-game day ends.
- **Machine markers stay hidden** until a valid pass is held, and disappear again
  when it expires.

**QBCore:** charges money (`Config.GymPass.price` / `account`), gives the
`gym_pass` membership item, and tracks the in-game day in player metadata. When
the day ends the script clears the metadata and removes the item.

To register the item:
1. Copy the `['gym_pass']` block from `GYMPASS_ITEM.lua` into your items file
   (`qb-core/shared/items.lua`, or `tgiann-inventory/items/items.lua`).
2. Copy `images/gym_pass.png` into your inventory's image folder
   (e.g. `qb-inventory/html/images/`, `ox_inventory/web/images/`, or
   `tgiann-inventory/web/images/`).

Using tgiann and the item check misbehaves? Set
`Config.GymPass.hasItemExport = true` to use tgiann's `HasItem` export.

**Standalone:** no economy/inventory exists, so the pass is granted free on
purchase and saved locally via KVP (no item).

## Stations
Free Weights + Pull-Up Bar (strength), Sit-Ups + Stretching (stamina).
Strength affects melee damage; stamina lengthens sprinting. Cap is 100.

## Config (config.lua)
- `Config.Framework`  — `auto` / `qbcore` / `standalone`
- `Config.UseTarget`  — `auto` / `on` / `off` for the vendor NPC
- `Config.GymPass`    — price, account, item name, NPC model/coords, blip
- `Config.Stations`   — coords, animation, and which stat each trains
- `GainPerSession`, `WorkoutDuration`, `MaxStat` — tuning

## Progression & Effects
- **Slow gains:** `Config.GainPerSession` (default 1) plus a long `WorkoutDuration`
  and `Config.WorkoutCooldown` make raising a stat to 100 a real grind.
- **Tire faster:** the game only uses a fraction of your stored stamina for sprint
  endurance (`Config.Effects.staminaGameRatio`). Untrained = gas out fast.
- **Speed boost:** higher stamina scales run/swim speed up toward GTA's ~1.49x cap.
- **Decay:** skip the gym past `Config.Decay.graceHours` and you lose
  `Config.Decay.lossPerDay` from both stats per idle day (real time).
- **Stats board:** a floating readout at the gym shows strength, stamina, and the
  live speed/endurance bonuses (`Config.StatsBoard`).
- **Appearance:** strength feeds the GTA muscle stat. GTA has no native muscle
  slider for the freemode ped, so for a guaranteed body morph enable
  `Config.Appearance` and wire your appearance resource into `applyAppearance()`
  in client.lua.

## Energy / Exhaustion
Players can't grind the gym all day. Each workout burns `Config.Energy.costPerWorkout`
energy; when you don't have enough left you get **"You're too exhausted to work out"**
and must rest. Energy regenerates `Config.Energy.regenPerMin` per **real** minute
(persisted, so relogging won't refill it). While exhausted your sprint stamina is cut
(`exhaustedStaminaMult`), so you also tire much faster until recovered. Current energy
shows on the stats board.

## Placement note (boardwalk)
The gym sits on a raised deck, so auto ground-snapping finds the sand underneath and
sinks the trainer/props. `Config.GymPass.groundSnap` and `Config.StatsBoard.groundSnap`
default to **false** — set the Z to the deck surface (stand there, `/gymcoords`, paste).

## In-game commands
- `/gympass`   — check if your pass is active
- `/gymstats`  — show your current strength & stamina
- `/gymcoords` — print your exact position + heading to the F8 console

## Notes
- The duplicate-weights bug is fixed: scenario props are deleted (not dropped)
  when a workout ends. Any leftover bars from earlier testing clear on restart.
- Coords are a Muscle Sands starting point — fine-tune with `/gymcoords`.
- This version uses native GTA strength/stamina stats (no external skill
  resource needed).
