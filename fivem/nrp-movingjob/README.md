# nrp-movingjob

Haulaway Moving Co. — contract moving work for The Neighborhood RP.

Talk to the yard boss, take a contract off the board, pull a van out of a bay,
carry furniture and boxes onto it one piece at a time, drive across town, stack
it on the customer's step, bring the van back and settle up.

## Install

```cfg
ensure nrp-movingjob
```

Requires `ox_lib`, `qb-core`, `oxmysql`. Targeting uses `nrp-target` if it is
started, otherwise `ox_target`; set `Config.UseTarget = false` for a plain [E]
prompt instead.

## Wiring it to the rest of the server

Only two functions at the bottom of `shared/config.lua` touch other resources:

- `Config.GiveKeys(vehicle, plate)` — currently fires `0r-vehiclekeys`
- `Config.SetFuel(vehicle, amount)` — currently calls your `LegacyFuel`

Everything else is self-contained.

## Placing it

The coords in `Config.Boss`, `Config.Depot`, `Config.Van.bays` and
`Config.Drops` are staging values. Re-place them in-game before release.

`Config.Van.slots` are cargo positions in vehicle space — they are tuned for
`boxville2`. If you swap the van model, re-measure them.

## How the money works

Payout is `(pay per item x items delivered) + completion bonus`, minus a
penalty for anything fragile that got dropped from height. The server owns all
of it — the client never sends an amount, only that a step happened, and every
step is checked against the player's real position before it counts.

With a crew, `Config.Crew.splitPay` divides the total across everyone on the
job. Only the boss can cash the contract in.

## Difficulty knobs

`Config.Weights` is where the job gets its texture. Heavier cargo walks slower
and takes longer to set down, which is what makes hiring a second pair of hands
worth the split. Fragile cargo is the only class that can be damaged.


## Tuning how cargo sits in the hands

Prop pivots are inconsistent, so the offsets shipped in `Config.Cargo` are
starting points, not finished values. Dial each one in live:

```
/carrytune 1     -- index into Config.Cargo
```

Arrow keys move it, Page Up/Down changes height, numpad 4/6/8/2/7/9 rotates,
hold Left Shift for coarse steps. Enter prints the finished `carry = { ... }`
block to F8 and copies it to your clipboard; paste it over that item's line in
`shared/config.lua`. Backspace cancels without saving.

The bone everything hangs off is `Config.CarryBone` (28422 / IK_R_Hand, what
the box-carry animation is built around). A single item can override it with
`carry.bone` if it needs a different one.

## Finding a prop that actually exists

Prop names are easy to get wrong and a bad one soft-locks a contract, so the
resource validates every cargo model on startup and prints any misses.

Two commands help you pick:

```
/testprop                 -- test a built-in list of household props
/testprop model_a model_b -- test specific names
/propview <model>         -- spawn one in front of you for 20s to eyeball it
```

Workflow for adding a piece of cargo: `/testprop` to see what exists,
`/propview` to check the size is sane, then set it in `Config.Cargo` and
`/carrytune <index>` to place it in the hands.

## Hand truck (currently disabled)

`client/dolly.lua` is commented out in `fxmanifest.lua` and
`Config.Dolly.enabled` is `false`. The file is still in the resource, so to
turn it on: uncomment the manifest line, flip the config flag, restart, and
confirm you see `hand truck module loaded` in console.

Everything below describes it once enabled.

A dolly you push around instead of carrying one piece at a time. Walk to the
pallet during a contract and press **G** to grab one, G again to put it back
(only when it is empty).

While you are pushing it:

- **Pallet** — [E] stacks a piece onto the truck, up to `Config.Dolly.capacity`
- **Van rear, loading** — [E] moves one piece off the truck into the van
- **Van rear, at the address** — [E] moves one piece out of the van onto the truck
- **Doorstep** — [E] takes the top piece off and sets it down

So a full round trip is three pieces per walk instead of one. You move slower
while pushing, which is the trade.

Tune how it sits in your hands with `/dollytune` — same controls as
`/carrytune`. The push animation is `Config.Dolly.anim`; swap it for a proper
trolley-push clip if you have one you like better.

Parking the truck destroys anything still on it, so unload before you let go.
The prompt only offers to put it back when it is empty.

## Troubleshooting

**"attempt to index a nil value (global 'Dolly')"**

`client/dolly.lua` is not loading. On resource start you should see:

```
[nrp-movingjob] hand truck module loaded.
```

If instead you see the red "did not load" warning, the file is not reaching
the server. Check, in order:

1. `client/dolly.lua` actually exists in the resource folder on the server and
   is not 0 bytes — a half-finished upload leaves the file there but empty.
2. `client/dolly.lua` is listed in `fxmanifest.lua` under `client_scripts`.
3. You did a full `restart nrp-movingjob` after uploading, not just a reconnect.

The job itself keeps working either way — without the module it falls back to
plain hand-carry instead of erroring on every pickup.


## Uniform

Clocking in puts you in the hi-vis and snapshots what you were wearing. The
snapshot is keyed to your **citizenid**, so it can never be replayed onto a
different character.

`Config.Uniform.restoreMode` decides what happens when the job ends:

| mode | behaviour |
|---|---|
| `auto` | changes you straight back (default) |
| `prompt` | asks first, keep the vest or change back |
| `off` | leaves the vest on until you run `/myclothes` |

`/myclothes` changes you back at any time, in any mode.

### Point it at your character system

The snapshot only covers the five component slots the uniform touches, which
is a blunt way to restore an outfit. Your character system already knows the
character's real appearance, so prefer delegating to it — fill in
`Config.Uniform.reapply` and return `true`:

```lua
reapply = function()
    exports['17mov_CharacterSystem']:ApplySkin()
    return true
end
```

With that wired up the snapshot becomes a fallback and is only used if the
hook returns false.

### Recovery after a crash or restart

On load, the resource waits for your character to finish loading, checks the
snapshot belongs to that character, and then checks whether you are actually
still wearing uniform pieces. If the character system already dressed you
correctly it clears the snapshot and does nothing — it will not overwrite a
correctly loaded outfit.


## Work clothes

The job puts you in a hi-vis vest and puts your own clothes back afterwards.
How it puts them back is `Config.Uniform.restoreMode`:

- `prompt` (default) — asks before changing you back
- `auto` — changes you back straight away
- `off` — leaves the vest on until you run `/myclothes`

`/myclothes` changes you back at any time, including mid-contract.

### Why it can lose an outfit, and how to stop it

The self-contained fallback snapshots five component slots (arms, legs, shoes,
undershirt, top) at clock-in and replays them at the end. That is lossy: it
knows nothing about the rest of your appearance, and the snapshot goes stale
the moment you change clothes somewhere else.

The fix is to let your character system re-apply the real saved appearance
instead. `Config.Uniform.reapply` does that, routed through
`Config.Uniform.clothingResource` (set to `17mov_CharacterSystem`). It tries
the known export names and stops at the first that works.

Afterwards the script checks your ped: if you are still in the vest, the
re-apply silently did nothing and it falls back to the snapshot. So a wrong
export name degrades instead of stranding you.

Set `Config.Uniform.clothingDebug = true` for one run to see which attempt
landed, then leave it off.

Coming back from a crash or restart **always** asks, whatever `restoreMode`
says — that snapshot could be hours old, and replaying it silently is the one
case that would overwrite an outfit you changed into since.


## Reading and editing the uniform

```lua
male = {
    components = {
        [3]  = { drawable = 41, texture = 0 },
        [11] = { drawable = 56, texture = 0 }
    },
    props = {                      -- optional
        [0] = { drawable = -1, texture = 0 }
    }
}
```

The number in brackets is the **slot**. `drawable` is which garment goes in
that slot, `texture` is that garment's colourway. A drawable of `-1` on a prop
means "nothing there".

Clothing slots:

| ID | Slot | ID | Slot |
|----|------|----|------|
| 1  | Mask | 7  | Accessory (tie, chain) |
| 3  | Arms / gloves | 8  | Undershirt |
| 4  | Legs / pants | 9  | Body armour |
| 5  | Backpack | 10 | Decal / badge |
| 6  | Shoes | 11 | Top / jacket |

Prop slots: `0` hat, `1` glasses, `2` earpiece.

Slots you leave out of the table are untouched, so the player keeps their own.

**Male and female drawable numbers are unrelated.** Drawable 41 on
`mp_m_freemode_01` and drawable 41 on `mp_f_freemode_01` are different
garments, which is why there are two blocks and why each needs its own pass.

### The editor

```
/uniformtune
```

Dresses the uniform on your own ped so you can see it. It edits whichever
gender you currently are, so run it once on a male character and once on a
female one.

- **PgUp / PgDn** — move between slots
- **Left / Right** — change the garment
- **Up / Down** — change its colour
- **Shift** — jump 10 at a time
- **Space** — include or exclude this slot from the uniform
- **Enter** — print the block to F8 and copy it to your clipboard
- **Backspace** — cancel, back into your own clothes

Paste the result over the matching `male = { ... }` or `female = { ... }`
block in `Config.Uniform`.

## Drop points

A drop entry can be written two ways:

```lua
-- Preferred: stand in the spot, face the house, capture it.
{ label = 'Mirror Park drive', arrival = vector3(1229.7, -725.5, 60.8), heading = 142.0 },

-- Older form, still supported.
{ label = 'Mirror Park house', door = vector3(...), arrival = vector3(...) },
```

`arrival` is where the stack is centred and where the van has to be parked
near. `heading` is which way the pieces face. The layout around that point
comes from `Config.DropPattern`.

**Put these outdoors.** A coordinate taken from a house you cannot walk into
leaves the stack inside the shell, unreachable, and the contract can never be
finished. Driveways, paths and garage aprons all work.

On startup the resource checks every drop point and prints a warning for any
that sit inside an interior.

### Placing them

```
/dropeditor      -- stand where the stack goes, facing the house
/droptest <n>    -- teleport to drop n and see whether it reads as indoors
```

In the editor you get a translucent preview of the entire delivery laid out in
front of you before you commit:

- **R** — snap to where you are standing now
- **Arrows** — nudge the stack, **Shift** for coarse steps
- **[** and **]** — rotate the layout
- **Enter** — name it, then the entry is printed to F8 and copied
- **Backspace** — cancel

Paste the result into `Config.Drops`.
