# nrp-keepitems v1.2.0

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

## How it works
1. When a player is dead or downed, the server watches their inventory twice a second.
   It uses QBCore `isdead` / `inlaststand` or ped health, so nothing can be faked from the client.
2. When the respawn wipe empties the inventory, every kept item is put back.
   Amounts, serials and metadata stay the same, in the same slots where possible.
3. It keeps watching for 90 seconds after revive/respawn, because hospital scripts wipe right then.

## No duping
- **Robbing a downed player:** items taken one at a time are never given back.
- **Alive players** aren't watched.
- **Jail / confiscation scripts:** call `exports['nrp-keepitems']:AllowRemoval(source, 10)` first.
- **Ground drops:** turn off "drop items on the ground on death" in your inventory if it's on.

## Install
1. Drop `nrp-keepitems` in your resources.
2. `ensure nrp-keepitems` after `qb-core` and `tgiann-inventory`.
3. Leave your respawn wipe ON (e.g. qb-ambulancejob `Config.WipeInventoryOnRespawn = true`).

Every death logs a line in the console (`Death wipe for ... - kept: ...`).
`Config.Webhook` also sends it to Discord.
