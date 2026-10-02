# Clipboard Rentals — v2.0.0

A man with a clipboard rents you cars. Now with **signed rental contracts** and a
**temporary operating permit** (temp registration).

Author: **foxscripts**

---

## What's new in 2.0.0

- **Rental contract** — a signable agreement shown before payment. The renter types
  a signature and ticks "I agree" (both configurable). Signature is validated
  server-side, never trusted from the client.
- **Temporary registration** — a DMV-style operating permit issued with every rental,
  with holder, plate, issue/expiry times and a **live countdown**. Optional ping when
  it lapses.
- **`/papers` command + keybind** — pull up your contract and permit any time while
  driving. Also added to the ped's target menu.
- **UI revamp** — refined panel, category counts on tabs, a real "paper" look for the
  documents, smoother hover/blur states. Same purple identity.
- **Registration papers item** — on rent the renter also gets a `rental_papers`
  inventory item (ox_inventory or qb-inventory, auto-detected). Using it opens the same
  contract + permit viewer, and it carries its own data in metadata so it still works
  after a relog. Signing is unchanged. You must register the item first — see
  "Registration papers item" below. Toggle `removeOnReturn` to keep it as a souvenir.

## Registration papers item

The item has to exist in your inventory before it can be given. Add ONE of these:

**ox_inventory** — in `ox_inventory/data/items.lua`:

```lua
['rental_papers'] = {
    label = 'Rental Papers',
    weight = 50,
    stack = false,
    close = true,
    consume = 0,
    description = 'Vehicle rental agreement & temporary permit.',
    client = { event = 'clipboard_rentals:client:usePapers' },
},
```

**qb-inventory** — in `qb-core/shared/items.lua`:

```lua
rental_papers = { name = 'rental_papers', label = 'Rental Papers', weight = 50, type = 'item', image = 'rental_papers.png', unique = true, useable = true, shouldClose = true, description = 'Vehicle rental agreement & temporary permit.' },
```

(qb-inventory: drop a `rental_papers.png` into `qb-inventory/html/images/` for an icon,
or it just shows a blank one.) The name must match `Config.PaperItem.name`.

- **Vehicle keys (client-side)** — keys are handed out the moment the car spawns, using
  your keys resource's real call. `Config.VehicleKeys.system = 'auto'` detects a running
  system; or force one: `'qb'` (classic QBCore `vehiclekeys:client:SetOwner` event, works
  with qb-vehiclekeys + most forks), `'qbx'`, `'wasabi'`, `'mrnewb'`, `'qs'`, `'renewed'`,
  `'0r'`, or `'custom'` (edit `GiveVehicleKeys()` in client.lua). Leave `debug = true` to
  see the chosen system + any errors in F8.

## Config quick reference

```lua
Config.PapersCommand = 'papers'   -- chat command to open your papers
Config.PapersKey     = ''         -- optional default keybind, e.g. 'K'

Config.Contract = {
    enabled = true,
    requireAgree = true,          -- must tick "I agree"
    requireSignature = true,      -- must type a signature
    company = 'Clipboard Rentals LLC',
    terms = { ... },              -- {company} and {duration} tokens are filled live
}

Config.TempRegistration = {
    enabled = true,
    minutes = 60,                 -- permit validity window
    notifyOnExpire = true,
    authority = 'Los Santos DMV',
}

Config.PaperItem = {
    enabled = true,
    inventory = 'auto',           -- auto|ox|qb
    name = 'rental_papers',       -- must match your inventory item name
    removeOnReturn = true,        -- false = renter keeps the papers
}

Config.VehicleKeys = {
    enabled = true,
    system = 'auto',   -- auto|qb|qbx|wasabi|mrnewb|qs|renewed|0r|custom
    debug = true,      -- prints chosen system + errors to F8
}
```

## Notes / possible next steps

- Rentals are tracked per-session. If a player disconnects with a rental out, the key
  is pulled and the record cleared (the spawned car is left to the server's cleanup).
  Persisting rentals across relogs would need a DB table keyed by identifier — happy
  to add if you want it.
- The temp permit expiry is currently RP-facing (it notifies, it doesn't auto-despawn).
  If you want hard enforcement (e.g. auto-return on expiry, or a police-checkable
  export), that's a small addition.
