# fox_keyring

A standalone FiveM vehicle keyring. It needs no framework. If [ox_lib](https://github.com/overextended/ox_lib) is running, menus and notifications use it.

## Features

- A keyring for each player, tied to their license. It saves to `data/keys.json`, so keys survive restarts.
- Lock and unlock with **L** (players can rebind it). The server checks the key, the lights flash, the horn chirps and the key fob animation plays.
- Engine protection: you can't start a vehicle unless you have its key.
- Give keys to other players (a copy, or a transfer), locate your vehicles with a waypoint, and name your keys.
- Temporary keys for rentals and jobs. They're removed when the player disconnects.
- Server exports so garages, dealerships and jobs can hand out keys.

## Install

1. Copy `fox_keyring` into your server's `resources` folder.
2. Add `ensure fox_keyring` to `server.cfg` (after `ox_lib`, if you use it).
3. Allow admins to use `/addkey`:
   ```
   add_ace group.admin command.addkey allow
   ```

Requires OneSync, which is the default on current servers.

## Commands

| Command | Description |
| --- | --- |
| `/keyring` | Open your keyring (ox_lib menu, or a list in chat) |
| `L` / `/togglelock` | Lock or unlock the nearest vehicle you have a key for |
| `/givekey [id] [plate]` | Give a key. With no arguments it gives the key for your nearest vehicle to the closest player |
| `/dropkey [plate]` | Remove a key from your keyring |
| `/labelkey [plate] [name]` | Give a key a name, e.g. `Daily driver` |
| `/addkey [id]` | Admin: give a key for the vehicle you're sitting in |

## Giving keys from other scripts (server side)

```lua
exports.fox_keyring:GiveKey(source, plate, 'Sultan RS')  -- permanent key (label optional)
exports.fox_keyring:GiveTempKey(source, plate)           -- removed on disconnect
exports.fox_keyring:RemoveKey(source, plate)
exports.fox_keyring:HasKey(source, plate)                -- true/false
exports.fox_keyring:GetKeys(source)                      -- { 'ABC123', ... }
```

Client side: `exports.fox_keyring:HasKey(plate)`.

For example, in a garage's "take vehicle out" server handler, call `GiveKey(source, plate)` once the vehicle has spawned.

## Config

Every option is in `config.lua`: the lock key, distances, max keys, persistence, the identifier type, engine protection and exempt vehicle classes.
