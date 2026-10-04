# nrp-keepitems v1.1.0

When you die and respawn, your respawn/hospital script still clears your inventory as normal.
**Only the items on the keep list come back**, e.g. ID, licenses, phone, radio, keys, wallet and gym pass.
Guns, cash, drugs, food and everything else are still lost.

## The keep list (config.lua -> Config.KeepItems)
Add or remove item names (the keys from your tgiann `items.lua`):
```lua
Config.KeepItems = {
    id_card = true,
    phone   = true,
    car_key = true,
    -- my_item = true,
}
```
The default list includes ID & licenses, phones/sim/radios, car/house/door keys, wallet,
bank card, gym pass, rental papers and the minigolf scorecard.
`Config.KeepEverything = true` keeps everything instead.

## How it works
1. When a player is **dead or downed**, the server watches their inventory twice a second.
   It uses QBCore `isdead` / `inlaststand` or ped health, so nothing can be faked from the client.
2. When the inventory gets **wiped in one go** (the respawn wipe), the kept items are given straight back.
   They keep the same amounts, serials and metadata, and go into the same slots where possible.
3. It keeps watching for 90 seconds after revive/respawn, because that's when hospital scripts wipe.

## No duping
- **Robbing a downed player:** items taken one at a time are never given back, even kept items.
- **Alive players** aren't watched at all.
- **Scripts that should take everything** (jail confiscation, etc.) can call this first:
  `exports['nrp-keepitems']:AllowRemoval(source, 10)`
- If your inventory **drops items on the ground** on death, turn that off.
  Otherwise kept items exist twice: one on you, one on the ground.

## Install
1. Drop `nrp-keepitems` in your resources.
2. `ensure nrp-keepitems` after `qb-core` and `tgiann-inventory`.
3. Keep your respawn wipe ON (e.g. qb-ambulancejob `Config.WipeInventoryOnRespawn = true`). This script only hands back the kept items.

Every death logs a line in the server console (`Death wipe for ... - kept: ...`).
Set `Config.Webhook` to also post it to Discord.
