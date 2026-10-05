# nrp-bowling v2.3.0

A full rebuild of `loaf_bowling` for the Breze bowling MLO (the `bowling` map resource, unchanged).

## Install
1. Remove `loaf_bowling`. Keep the `bowling` map resource.
2. server.cfg:
   ```
   ensure bowling
   ensure nrp-bowling
   ```
3. **Place the staff ped in game:** as an admin, stand where she should be (facing where customers stand) and type **`/bowlstaff`**.
   She moves there for everyone right away and the spot is saved (`staff.json`), so it survives restarts.
   (`/bowlcoords` still prints your position if you'd rather put it in `Config.Staff.coords`.)

## How it works
1. **Talk to the staff ped** at the desk (ox_target / qb-target, or press **E**). The neon price sheet opens:
   | | Adult | Junior |
   |---|---|---|
   | 1 game | $9 | $8 |
   | 2 games | $17 | $16 |
   - **Game deals** (2 games, host pays for everyone): 2–6 players, $34–$102.
   - **Family deals** (1 game each, host pays): family of 4 $34, family of 5 $42.
   - Tick friends standing near you to **invite** them, then **Pay & pick lane**.
2. **Pick your lane** at the desk, or hit **Auto pick a free lane**. Don't pick within 90 s and you're refunded.
3. **Invites** pop up for your friends with a 45 s timer:
   - On a deal they join **free**.
   - On a single ticket they choose adult or junior and pay when they join.
4. The lane owner presses **G** at the lane to start. 2-game tickets and deals play game 1 and then game 2 automatically.
5. On your turn, press **E** at the gold marker to pick up your ball.
6. **Skill-based throw.** A **"Your Shot" lane panel** on the left of the screen shows your shot.
   It's UI only; nothing is drawn on the real lane. Each marker swings by itself. Press **SPACE** to lock each one:
   1. **Position:** a red marker slides along the foul line.
   2. **Direction:** an arrow sweeps left and right down the lane.
   3. **Spin:** a sideways arrow grows left and right. The ball hooks that way late in the lane.
   4. **Power:** stop the meter in the blue for a perfectly accurate ball.

   **BACKSPACE** goes back a step, and **C** changes the camera.
   - Your character stands still in a two-hand bowler's stance the whole time; only the ball's start spot moves.
     On release they crouch and let the ball go.
   - The camera sits in front of the bowler, low over the lane looking at the pins.
     **C** turns it round to face the bowler.
   - The panel shows the predicted path with the hook, and the pins at the end of the lane.
   - It shows the locked values (position cm, direction °, spin %).
   - It warns **GUTTER!** if your line leaves the lane.
7. **Lane monitor:** red and blue player rows, white frame boxes, yellow scores, **Max** possible score, the total, and "Game 1 of 2".
   STRIKE / SPARE / GUTTER banners show, and the winner is announced at the end.
8. **DELETE** leaves your lane.

## Mechanics
- Real ten-pin scoring: strikes, spares, and 10th-frame bonus balls.
- The ball rolls on a guided path (aim + hook), then real physics hits the pins.
  - Gutter balls roll past the pins.
  - Fallen pins are counted and swept away; standing pins stay for ball 2.
- The server only accepts rolls from whoever's turn it is, and never more pins than are standing. Prices are charged on the server.
- Fail-safes:
  - Walking more than 45 m away removes you from the game.
  - Taking more than 2 minutes on your turn removes you.
  - Leaving or disconnecting passes the turn on.
  - Finished or empty lanes free themselves.

## Config (config.lua)
- `Config.Tickets`, `Config.GameDeals`, `Config.FamilyDeals`: prices
- `Config.Staff`: ped model, coords, scenario
- `Config.Ball`: swing speeds (`positionSpeed`, `directionSpeed`, `spinSpeed`, `meterSpeed`; higher = harder),
  plus sweet spot, ball speeds, hook strength, aim/position range
- `Config.MaxPlayers`, `Config.InviteRange`, `Config.InviteSeconds`, `Config.BookingSeconds`, `Config.TurnTimeout`
