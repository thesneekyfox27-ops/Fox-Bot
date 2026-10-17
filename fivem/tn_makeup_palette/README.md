# tn_makeup_palette

Item-based makeup toggle for QBCore + ox_lib + tgiann-inventory.

## Install

1. Drop the folder in `resources/[nrp]/tn_makeup_palette`
2. Add `ensure tn_makeup_palette` to `server.cfg` (after `qb-core` and `ox_lib`)
3. Copy the block from `shared/items.lua` into `tgiann-inventory/items/items.lua`
4. Put `makeup_palette.png` in `tgiann-inventory/inventory_images/images/`

No SQL required.

## Using it

Use the palette and a menu shows what's on your face and what's saved:

- **Wipe it all off** / **Wipe off Lipstick** (or Eye makeup, Blush): one part or everything
- **Put it all back on** / **Put Lipstick back on**: brings back exactly what you had (same style, colour, opacity)

While you do it, a close-up "mirror" camera shows your face (turn it off in `Config.Camera`).
One part is quicker (`Config.ProgressSingle`) than everything (`Config.Progress`).

## How it works

Makeup in GTA V is a **head overlay**, not a clothing component:

| Index | Overlay |
|-------|---------|
| 4 | Eye makeup (eyeshadow is part of this) |
| 5 | Blush |
| 8 | Lipstick |

Which parts the palette handles is `Config.Parts`. Scars, freckles, beard,
ageing, complexion and tattoos are different indices and are never touched.

## Persistence

What you wipe off is saved in **QBCore player metadata** (`savedmakeup`), so it
survives relogs and restarts with no SQL. The client asks the server for it
whenever your character loads, respawns, or the resource restarts.

Appearance scripts (17mov, illenium, qb-clothing) reload your whole look on
spawn and outfit changes, makeup included. While something is wiped off the
palette checks every `Config.WatchEvery` ms:

- the saved makeup came back: it's taken off again
- **different** makeup showed up (you went to the barber): the new look is kept
  and the old saved one is forgotten, no extra setup needed

It pauses while a menu has focus, so barber previews aren't touched.

## Exports

```lua
exports['tn_makeup_palette']:ClearSaved()       -- forget the saved look
exports['tn_makeup_palette']:HasSavedMakeup()   -- true if anything is wiped off
exports['tn_makeup_palette']:GetSavedParts()    -- e.g. { [8] = true }
```

`/makeupreset` unsticks the palette if it ever says it's still busy.

## Config

Everything lives in `config.lua`: item name, whether it's used up
(`ConsumeItem` only takes it when something gets wiped off), progress times,
camera, animation/prop, parts and usage restrictions.
