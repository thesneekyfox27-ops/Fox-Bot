# nrp-keepitems v2.0.0

When you die and respawn, your hospital/respawn script still clears the inventory.
This script then gives back **everything legal**. Anything **illegal** stays gone.

| Kept (legal) | Lost (illegal) |
|---|---|
| ID, licenses, phones, radios, keys, wallet, cash (`money`), bank card | **Drugs** and drug making: weed, meth, coke, crack, pills, lean, LSD, shrooms, moonshine, presses, bags... |
| Food, drinks, alcohol, cigarettes | **Dirty money**: marked bills, black money, bands/stacks of cash, cut/uncut money, money bags |
| Tools, repair kits, car parts, fishing gear, skate gear | **Guns, ammo, explosives**: every `weapon_`, every `_ammo`, ammo boxes, C4, bombs, thermite |
| Medical supplies, EMS/PD job gear, body armor | **Heist & crime tools**: lockpicks, hacking devices, heist packs, security cards, USBs, jammers, trap phone, burner SIM, zip ties, head bags |
| Clothing items, scratchcards, gym pass, rental papers | **Stolen loot**: jewellery, gold/silver bars, diamonds, Rolex, paintings, sculptures, TVs, consoles and other house-robbery items |

With your current `items.lua`: **987 items kept, 249 lost**.

## Changing it (config.lua)
- `Config.LoseItems`: exact item names that are lost.
- `Config.LosePatterns`: name rules (`^weapon_`, `_ammo$`, `^weed_`, `meth`, `coke`, `_baggy$`, ...).
  New drugs, guns or ammo you add later are lost automatically.
- `Config.KeepAnyway`: always kept even if a rule matches (e.g. `weapon_petrolcan`).
- `Config.KeepEverything = true`: keep everything.
- From another script: `exports['nrp-keepitems']:KeepsOnDeath('item_name')` returns true or false.

Notes on the defaults:
- **All guns are lost, licensed ones too.** Remove `'^weapon_'` from the patterns to keep them.
- **Police ammo is lost too.** Cops restock at the armory.

## How it works (v2)
1. **Every player's inventory is snapshotted all the time**, so the state from before a death is always known,
   even if a script wipes you the instant you die.
2. **Death is detected 5 ways** (any one counts):
   - QBCore `isdead` / `inlaststand`
   - state bags (`isDead`, `dead`, `down`)
   - ped health on the server
   - the client
   - qb-ambulancejob's death/laststand events
3. **While you're dead or downed:** any kept item that disappears comes back, even a single item.
4. **For 30 seconds after revive/respawn:** if your inventory gets wiped (half or more of it gone at once),
   the kept items come back. Eating or using items normally is never undone.
5. Inventories are read through tgiann-inventory, with QBCore as a fallback.
   The console prints which one it uses: `[nrp-keepitems] reading inventories with ...`.

## No duping
- **Robbed while downed:** if a player within 6 m picks up your item at the same moment, it's a robbery and it stays theirs.
- **Alive players** aren't touched. Selling, dropping and giving work normally.
- **Jail / confiscation scripts:** call `exports['nrp-keepitems']:AllowRemoval(source, 10)` first.
- **Ground drops:** if your inventory drops items on the ground on death, turn that off.
  Otherwise kept items exist twice.

## Check it's working: `/keepitems <id>`
Run it in the server console, or in game as an admin. It shows:
- which inventory reader is used (`NONE FOUND` means it can't see inventories at all)
- whether the player is down, whether the death was confirmed, and the after-revive timer
- exactly which of their items are KEPT and which are LOST on death

Every restore prints a line in the console, e.g. `P 1 (C1) - respawn wipe - gave back: 1x phone`.
Set `Config.Debug = true` to also see down/up changes.

## Install
1. Drop `nrp-keepitems` in your resources.
2. `ensure nrp-keepitems` after `qb-core` and `tgiann-inventory`.
3. Leave your respawn wipe ON (e.g. qb-ambulancejob `Config.WipeInventoryOnRespawn = true`).

Every death logs a line in the console (`Death wipe for ... - kept: ...`).
`Config.Webhook` also sends it to Discord.
