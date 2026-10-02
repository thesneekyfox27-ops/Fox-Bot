# mrw_minigolf (QBCore / ESX / standalone)

Mini golf for the Patoche golf mapping. Original by Morow, extended with
QBCore support, group play, ticket pricing and keepable scorecards.

## Install

```cfg
ensure mrw_minigolf
```

Works with **qb-core**, **es_extended**, or no framework (`Config.Framework`
in `shared/shared.lua`, `'auto'` picks whichever is running).

## Playing

- Walk to the club rental and press **E**: the pricing board opens. Pick a
  ticket (Adults / Kids / Seniors-Military), tick any friends standing nearby,
  then **Buy ticket & start**. Nothing is charged until you press it.
- Invited friends get a card to pick their own ticket and join, or decline.
- Hold the scorecard key while playing to see your card and your group's totals.
- **Delete** quits early (asks first). Players can rebind it in
  Settings > Key Bindings > FiveM.
- At the end of the round (or when you quit) your scorecard pops up with
  **Keep scorecard**, which puts it in your inventory. Using the item opens it.

## Prices

`Config.tickets` in `shared/shared.lua`. Add `jobs = { 'army' }` to a ticket
to limit who can buy it.

## Scorecard item

The item has to exist in your inventory before it can be given. Add ONE of these.

**qb-inventory** (`qb-core/shared/items.lua`):

```lua
minigolf_scorecard = { name = 'minigolf_scorecard', label = 'Minigolf Scorecard', weight = 10, type = 'item', image = 'minigolf_scorecard.png', unique = true, useable = true, shouldClose = true, description = 'Your round at Portside Minigolf.' },
```

**ox_inventory** (`ox_inventory/data/items.lua`):

```lua
['minigolf_scorecard'] = {
    label = 'Minigolf Scorecard',
    weight = 10,
    stack = false,
    close = true,
    description = 'Your round at Portside Minigolf.',
    client = { event = 'mrw_minigolf:viewCard' },
},
```

The card is built on the server from its own record of the round, so it can't
be edited. Its metadata shows the date, strokes and holes played in the
inventory tooltip. Turn the item off with `Config.scorecard_item.enabled = false`.

## Language

`language` at the top of `shared/shared.lua`: `en`, `es` or `fr`.
