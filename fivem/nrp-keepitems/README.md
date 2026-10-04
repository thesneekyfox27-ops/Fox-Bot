# nrp-keepitems v1.0.0

Players keep their items when they die, whatever script tries to wipe them.

## How it works
FiveM doesn't let one script stop another from calling `ClearInventory` / `RemoveItem`.
So this script guards instead:

1. When a player is **dead or downed**, the server starts watching their inventory twice a second.
   It uses QBCore's `isdead` / `inlaststand` or the ped's health, so nothing can be faked from the client.
2. If their inventory is **wiped in one go**, it's put straight back: same items, amounts, serials and metadata, into the same slots where possible.
   That's what clear-on-death does: 60%+ of their stacks gone in half a second.
3. It keeps watching for **90 seconds after revive/respawn**, because hospital respawns usually wipe right then.

## What still works (no duping)
- **Robbing a downed player:** items taken one at a time are never given back.
- **Alive players:** selling, crafting, dropping and giving items are not touched.
- **Scripts that should take everything** (jail confiscation, etc.) can call this first:
  `exports['nrp-keepitems']:AllowRemoval(source, 10)`.
  That allows wipes for that player for 10 seconds.

## Install
1. Drop `nrp-keepitems` in your resources.
2. `ensure nrp-keepitems` after `qb-core` and `tgiann-inventory`.
3. Recommended: also turn off the wipe at the source, so items never leave:
   - qb-ambulancejob `config.lua`: `Config.WipeInventoryOnRespawn = false`
   - tgiann-inventory: turn off "drop / clear items on death" if you have it on.
     If items are dropped on the ground AND given back, someone could pick up the copy.

## Config
- `Config.NeverRestore`: items allowed to be lost on death (e.g. `markedbills = true`)
- `Config.WipeRatio` / `Config.MinStacks`: what counts as a wipe
- `Config.WatchAfterReviveSec`: how long to keep watching after revive
- `Config.Webhook`: optional Discord log of every blocked wipe (also printed in the console)
