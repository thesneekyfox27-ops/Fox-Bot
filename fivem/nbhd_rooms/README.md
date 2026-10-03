# NBHD Rooms v3.0.0

Motel room system for QBCore, configured through `Config.Buildings` in `config.lua`.

## What changed in v3
- **Safes are back in every room.** All 48 rooms get a safe at the exact spot set in the config (6 floors x 8 rooms).
  - Safes only spawn while you are near the building (`Config.SpawnDistance`), once the floors have loaded. Before, they spawned at login and fell under the map.
  - Any safe that goes missing is respawned every 2 seconds while you are nearby.
  - Use `safeZOffset` to raise or lower them.
- **Your safe storage is yours.** The stash id is `<building>_locker_<citizenid>`, the same id as before, so nothing already stored is lost. It follows you even if you get a different room.
- **Same room back.** With `Config.KeepLastRoom = true` you get your last room back on login, as long as nobody else has taken it.
- **Front desk.** Press E at the receptionist to get a key card showing your room, floor and name. The floor is worked out from 8 rooms per floor:

| Floor | Rooms |
|------|-------|
| 1 | 1-8 |
| 2 | 9-16 |
| 3 | 17-24 |
| 4 | 25-32 |
| 5 | 33-40 |
| 6 | 41-48 |

  If your building counts the lobby as Floor 1, set `floorOffset = 1` so rooms 1-8 show as "Floor 2".
- **Server checks.** You can only lock or unlock your own door, standing at it (3 m). You can only open your own room's safe, standing at it. The front desk only answers when you are at the desk.
- **Inventory is detected automatically** (`Config.Inventory = 'auto'`): tgiann-inventory, then ox_inventory, then qb-inventory, then the old client event.
- **Wardrobe** opens illenium-appearance if it is running, otherwise qb-clothing.
- **Homeowners** listed in `Config.HomeTables` (qb-houses / ps-housing) are not given a room automatically. Tables that don't exist are ignored.
- **New UI:** door, safe, wardrobe and front desk panels, plus the hotel key card popup.

## Commands
- `/myroom`: your room, floor, door distance, lock state and whether your safe is spawned (F8)
- `/roomfloors`: prints which rooms are on which floor (F8)
- `/finddoor`: lists objects within 3 m (for finding door models)

## Install
Replace the whole folder, run `refresh`, then `ensure nbhd_rooms`.
The database tables (`nbhd_rooms`, `nbhd_rooms_last`) are created automatically.
