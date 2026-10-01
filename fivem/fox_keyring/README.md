# fox_keyring

A keyring item for **QBCore + tgiann-inventory + 0r-vehiclekeys**.

Use the keyring in your inventory and it opens a 25-slot container that only accepts vehicle keys. Keys on a keyring still work: you can lock, unlock and start any car whose key is on a keyring you're carrying. 0r-vehiclekeys keeps doing all the key work, and this resource adds the container.

- Every keyring is its own container. Give someone your keyring and they get every key on it.
- Only `vehiclekeys` items fit on a keyring.
- Storing a car in Lunar Garage doesn't pull its key off the keyring. Taking it out again doesn't add a duplicate.

## Install

### 1. Add the keyring item to tgiann-inventory

Add it next to your other items in tgiann-inventory's items file. Copy the format of your `vehiclekeys` entry if it looks different:

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

**Don't** also add `keyring` to tgiann's `configItemStash.lua`. This resource opens it, and adding it there makes it open twice.

### 2. Patch 0r-vehiclekeys

In `0r-vehiclekeys/modules/inventory/tgiann-inventory/server.lua`, in `Inventory.HasItem`, add the `fox_keyring` check (see `integrations/0r-vehiclekeys.patch`):

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
```
