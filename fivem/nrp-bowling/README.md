# nrp-bowling v2.0.0

A full rebuild of `loaf_bowling` for the Breze bowling MLO (the `bowling` map resource, unchanged).

## Install
1. **Remove `loaf_bowling`** from your resources and server.cfg.
2. Keep the `bowling` map resource. Drop in `nrp-bowling`.
3. server.cfg:
   ```
   ensure bowling
   ensure nrp-bowling
   ```

## How players use it
1. **Front desk** (blip "Neighborhood Lanes", gold marker at the ball rack): press **E**.
   - Pick a lane and **Open Lane** (full 10-frame game or quick 5-frame game). It costs **$15 per player**.
   - Friends click **Join** on that lane (up to 4 bowlers).
2. Walk to your lane (it's set as your waypoint). The lane owner presses **G** at the lane to start.
3. On your turn, a gold marker lights up on the approach. Press **E** to pick up your ball.
4. Bowl:
   | Key | Action |
   |---|---|
   | **A / D** | step left / right on the approach |
   | **← / →** or mouse | aim (±5°) |
   | **Q / E** | spin left / right; the ball hooks in the back of the lane |
   | **SPACE** (hold) | power meter. Release in the **green** for a straight, accurate ball |
   | **C** | swap camera |
   | **BACKSPACE** | step off without bowling |
   - A guide line on the lane shows where the ball will go with your aim and spin. It turns red if it heads for the gutter.
5. The camera follows the ball, then switches to a pin cam. Pins are counted, the fallen ones are swept away, and the standing ones stay for your second ball.
6. **DELETE** leaves your lane at any time (rebindable in Settings > Key Bindings > FiveM).

## Mechanics
- **Real ten-pin scoring:** strikes, spares, and the 10th-frame bonus balls, on a live score sheet for everyone on the lane.
- **Power meter:** the sweet spot is 80–94%. Releasing outside it adds up to ±2.2° of random error, so skill matters.
- **Gutter balls:** a ball that leaves the 1.05 m lane drops into the gutter and rolls past the pins (0 pins).
- **Physics:** the ball is guided down the lane (consistent rolls, hook from spin), then real physics takes over just before the pins.
  A pin counts as down if it tips past 20°, drops into the pit, or is knocked off the deck.
- **Multiplayer:** everyone bowls frame 1 before anyone bowls frame 2. Other bowlers see your ball and pins.
- **Server-checked:** the server only accepts rolls from whoever's turn it is, and never more pins than are standing.
- **Fail-safes:**
  - Walking more than 45 m away removes you from the game.
  - Taking more than 2 minutes on your turn removes you (AFK).
  - Leaving or disconnecting passes the turn on.
  - An empty lane frees itself, and a finished lane frees itself 15 s after the winner banner.
- **Rack balls** at the desk spawn locally only, so they no longer duplicate for every player.

## Tuning (config.lua)
- `Config.Price`, `Config.MaxPlayers`, `Config.GameLengths`
- `Config.Ball`: speeds, hook strength, aim/position limits, power meter speed, sweet spot, error
- `Config.LaneHalfWidth` / `Config.GutterOffset`: gutter detection
- `Config.TurnTimeout`, `Config.LeaveDistance`
- `Config.Lanes`: approach spot + 10 pin spots per lane (same coords as the original)
