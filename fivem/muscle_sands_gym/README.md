# Muscle Sands Gym v2.0.0 (Vespucci Beach)

Outdoor gym on the Vespucci boardwalk for QBCore. Buy a membership from the trainer, then train at the stations with a rep timing minigame to build **strength** and **stamina**.

## Install
1. Replace the whole `muscle_sands_gym` folder.
2. `ensure muscle_sands_gym` in server.cfg, after `qb-core`, `oxmysql` and your inventory.
3. `refresh` then `restart muscle_sands_gym` (or restart the server).
4. The `gym_pass` item is already in your tgiann `items.lua`. If not, copy it from `GYMPASS_ITEM.lua`, and copy `images/gym_pass.png` into your inventory images.

Existing players keep their strength and stamina (same metadata keys as v1).
Old v1 day passes used in-game time and can't be converted, so anyone who had one needs to buy again.

## What's new in v2
- **Server-side stats.** Strength, stamina, energy, decay and passes are all decided by the server. In v1 the client sent its own numbers, so anyone could set themselves to 100.
- **Rep minigame.** Each set is 8 reps. Press **SPACE** when the needle is in the green zone. Gold centre = perfect.
  Your grade (S/A/B/C/D) decides the gain. A set can't finish faster than the reps take, and you must stay at the machine.
- **Realistic gains.** A perfect set gives +1.0 at the start. Gains shrink as you get stronger (+0.4 at 95). Sloppy sets give nothing.
- **Memberships.** Day Pass $50 (2 hours), Weekly $300, Monthly VIP $1000. These are real-time, so they don't expire after 48 minutes.
  Buying again adds the time on top. Cash first, then bank. You must carry the card to train. When it expires the card is removed.
- **Trainer menu.** Your stats, energy, perks, membership time left, the tiers and a **Top Lifters** leaderboard (strongest and fittest).
- **Strength now does something:** up to +30% melee damage. Stamina still gives run/swim speed and sprint endurance.
- **One person per machine.** Someone else on it? "Someone is using this one."
- **Energy.** Each set costs 20 energy, which refills at 6 per real minute. While exhausted you tire much faster.
- **Decay.** After 48 hours without training you lose 2 points a day.
- Trainer ped spawns only when you're nearby, at the exact deck height. Works with ox_target or qb-target (or press E). ox_lib notifications.

## Commands
- `/gymstats` or `/gympass` opens your stats card anywhere (buying only works at the trainer)
- `/gymcoords` prints your position + heading to F8 (for placing stations)

## Config (config.lua)
- `Config.Workout`: reps, speed, zone size, keys, rest between sets
- `Config.Gain`: points per perfect set, minimum score, how much harder it gets near the top
- `Config.Effects`: speed / swim / melee ranges, sprint ratio
- `Config.Energy`, `Config.Decay`
- `Config.Pass.tiers`: prices and durations (add or remove tiers freely)
- `Config.Trainer`: ped model, coords, blip
- `Config.Stations`: same format as v1 (`coords2`, `coords3` ... for extra spots)
