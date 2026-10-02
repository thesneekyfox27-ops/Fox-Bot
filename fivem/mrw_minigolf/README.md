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

- Talk to the **Crazy Golf** staff member at the club rental (target eye, or
  **E** if you don't run a target resource). The pricing board opens: pick a
  ticket, tick any friends standing nearby, then **Buy ticket & start**.
  Nothing is charged until you press it.
- Invited friends get a card to pick their own ticket and join, or decline.
- **Turns, like real golf.** A group plays each hole together. The ball
  farthest from the cup plays next (everyone level on the tee: fewest strokes,
  then join order). When everyone has finished a hole, the group moves on.
- **Walk to your ball.** No screen fades: on your turn an orange arrow sits over
  your ball. Walk up and press **E** to line up, **X** to step away again.
  Out of bounds puts the ball back on the tee and you walk back to it.
- **Your ball is yours.** Other players and their balls pass straight through
  it, and only you can play it.
- A turn not taken within `Config.turn_seconds` (90) is scored at the stroke
  limit so nobody holds the group up (solo play has no timer).
- Hold the scorecard key to see your card and your group's totals.
- **Delete** quits early (asks first). Players can rebind it in
  Settings > Key Bindings > FiveM.
- At the end of the round (or when you quit) your scorecard pops up with
  **Keep scorecard**, which puts it in your inventory. Using the item opens it.

## Prices

`Config.tickets` in `shared/shared.lua`. Add `jobs = { 'army' }` to a ticket
to limit who can buy it.

## Scorecard item

The item has to exist in your inventory before it can be given. Add ONE of these.

**tgiann-inventory** (`tgiann-inventory/items/items.lua`, inside `itemsData`):

```lua
minigolf_scorecard = { name = 'minigolf_scorecard', label = 'Minigolf Scorecard', weight = 10, type = 'item', image = 'minigolf_scorecard.png', unique = true, useable = true, shouldClose = true, description = 'Your round at Crazy Golf.' },
```

**qb-inventory** (`qb-core/shared/items.lua`):

```lua
minigolf_scorecard = { name = 'minigolf_scorecard', label = 'Minigolf Scorecard', weight = 10, type = 'item', image = 'minigolf_scorecard.png', unique = true, useable = true, shouldClose = true, description = 'Your round at Crazy Golf.' },
```

**ox_inventory** (`ox_inventory/data/items.lua`):

```lua
['minigolf_scorecard'] = {
    label = 'Minigolf Scorecard',
    weight = 10,
    stack = false,
    close = true,
    description = 'Your round at Crazy Golf.',
    client = { event = 'mrw_minigolf:viewCard' },
},
```

The card is built on the server from its own record of the round, so it can't
be edited. Its metadata shows the date, strokes and holes played in the
inventory tooltip. Turn the item off with `Config.scorecard_item.enabled = false`.

## Language

`language` at the top of `shared/shared.lua`: `en`, `es` or `fr`.
