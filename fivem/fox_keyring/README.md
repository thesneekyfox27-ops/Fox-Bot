# fox_keyring

A keyring item for **QBCore + tgiann-inventory + 0r-vehiclekeys**.

Use the keyring in your inventory and it opens a 25-slot container that only accepts vehicle keys. tgiann-inventory opens it the same way it opens wallets and bags. Keys on a keyring still work: you can lock, unlock and start any car whose key is on a keyring you're carrying. 0r-vehiclekeys keeps doing all the key work, and this resource connects the two.

- Every keyring is its own container. Give someone your keyring and they get every key on it.
- Only `vehiclekeys` items fit on a keyring.
- Only keys for **your own cars** go on a keyring automatically. That means a `player_vehicles` row with your citizenid and no `job`. Job cars (police, EMS, mechanic...), Lunar society cars, and stolen or hotwired cars always go into your pockets.
- When a job car is returned and 0r-vehiclekeys takes its key back, it also checks your keyrings, in case someone dragged the key onto one by hand.
- New keys for your own cars go straight onto your keyring. Whenever 0r-vehiclekeys gives you a key (garage, buying a car, a key from another player), it lands on the first keyring you carry that has room. With no keyring, or a full one, it goes into your pockets as usual. Turn this off with `Config.AutoAddKeys = false`.
- Storing a car in Lunar Garage doesn't pull its key off the keyring. Taking it out again doesn't add a duplicate.

## Install

### 1. Add the keyring to tgiann-inventory

**a) The item.** Add it next to your other items in tgiann-inventory's items file. Copy the format of your `vehiclekeys` entry if it looks different:

```lua
keyring = {
    name = 'keyring',
    label = 'Keyring',
    weight = 50,
    type = 'item',
    image = 'keyring.png',
    unique = true,
    hasMetadata = true,
    useable = true,
    shouldClose = true,
    description = 'Holds up to 25 vehicle keys',
},
```

`unique` and `hasMetadata` must both be `true`, because each keyring stores its own id. Put a `keyring.png` in tgiann's image folder.

**b) The container.** In `tgiann-inventory/configs/configItemStash.lua`, add this to the end of `config.itemStash`:

```lua
    {
        item = "keyring",
        maxweight = 0,
        slots = 25,
        label = "Keyring",
        whitelist = { "vehiclekeys" },
    },
```

If you change `slots`, change `Config.Slots` in fox_keyring's `config.lua` to match.

### 2. Patch 0r-vehiclekeys

Make three small additions to `0r-vehiclekeys/modules/inventory/tgiann-inventory/server.lua`. The full diff is in `integrations/0r-vehiclekeys.patch`.

**a)** In `Inventory.AddItem`, right after `markGranted(src, metadata.plate)`, send new keys to the keyring:

```lua
        -- fox_keyring: put the key straight onto a keyring the player is carrying, if one has room.
        if GetResourceState('fox_keyring') == 'started' then
            local ringOk, onRing = pcall(function()
                return exports['fox_keyring']:AddKeyToRing(src, item, metadata)
            end)
            if ringOk and onRing then
                print(('[0r-vehiclekeys] key for plate %s placed on keyring'):format(tostring(metadata.plate)))
                return true
            end
        end
```

**b)** In `Inventory.RemoveItem`, when the key isn't in the player's pockets, take it off their keyring instead. This is how returned job cars lose their key. See the patch file for the exact block.

**c)** In `Inventory.HasItem`, count keys that are on a keyring:

```lua
        if findItemByMetadata(src, item, metadata) ~= nil then return true end
        -- NRP: also count a vehicle key stored on the player's keyring
        if metadata.plate and GetResourceState('fox_keyring') == 'started'
           and exports['fox_keyring']:RingHasPlate(src, metadata.plate, metadata.ssn) then
            return true
        end
```

### 3. Start it

```
ensure qb-core
ensure oxmysql
ensure tgiann-inventory
ensure 0r-vehiclekeys
ensure fox_keyring
```

Do a **full server restart**, because tgiann loads its item list at boot. Give yourself a keyring and test it.

## Check it works

1. Use the keyring, drag a car key onto it and close it.
2. Walk to the car and lock it. It should work even though the key isn't in your pockets.
3. In the server console, run `keyringcheck <yourId>`. It lists each keyring you carry, the keys on it, and how they were read:
   - `read via export`: tgiann's live export works. This is the best case.
   - `read via database`: the export isn't available, so keys are read from the saved stash. Keys you just moved might not count until tgiann saves the stash.
   - `nothing`: neither worked. Check `Config.StashTable` in `config.lua` against your tgiann stash table (default `tgiann_inventory_stashitems`).

## Exports (server)

```lua
exports.fox_keyring:RingHasPlate(source, plate, ssn) -- true if a key for that plate is on a keyring they carry
exports.fox_keyring:GetRingPlates(source)            -- { 'ABC123', ... }
exports.fox_keyring:AddKeyToRing(source, item, metadata)      -- true if the key was placed on a keyring (own cars only)
exports.fox_keyring:RemoveKeyFromRing(source, item, metadata) -- true if the key was taken off a keyring
```

## Upgrading from fox_keyring 2.x

Keyrings made by the older version opened their own stash. When a player joins (or when fox_keyring starts), those keyrings are pointed at their existing stash before tgiann opens them, so the keys already on them stay put.
