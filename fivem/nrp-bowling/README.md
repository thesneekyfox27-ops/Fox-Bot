# nrp-bowling v2.5.0

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
   - **Adult tickets:** 1 game $9, 2 games $17. Friends you invite pay for their own ticket when they accept.
   - **Game deals** (2 games, host pays for everyone): 2–6 players, $34–$102.
     A deal **stays locked until you've invited enough friends** standing near you to fill it; the button shows "Invite N more".
     The server checks this as well.
   - Tick friends standing near you to invite them, then **Pay & pick lane**.
2. **Pick your lane** at the desk, or hit **Auto pick a free lane**. Don't pick within 90 s and you're refunded.
3. **Invites** pop up for your friends with a 45 s timer:
   - On a deal they join **free**.
   - On a single ticket they pay the adult price when they join.
4. The lane owner presses **G** at the lane to start. 2-game tickets and deals play game 1 and then game 2 automatically.
5. On your turn, a **glowing ring with a bouncing arrow** marks where to stand, and a **flashing map blip** shows your lane.
   Step into the ring and press **E** to pick up your ball.
   After every ball you're free to move again; walk back into the ring and press **E** for your next one.
6. **Skill-based throw.** The markers are painted on the real lane, like the video, and each one swings by itself.
   Press **SPACE** to lock each one:
   1. **Position:** a red marker slides along the foul line.
   2. **Direction:** a dark arrow sweeps left and right down the lane.
   3. **Spin:** a sideways arrow on the lane; the ball hooks that way late in the lane.
   4. **Power:** stop the meter in the blue for a perfectly accurate ball.
   **BACKSPACE** goes back a step, and **C** changes the camera.
   - Your character stands still in a two-hand bowler's stance the whole time; only the ball's start spot moves.
     On release they crouch and let the ball go.
   - While aiming, the bowler waits a couple of steps back on the approach.
     The camera sits low in front of them with a wide lens, so the red marker, the arrows and the pins are all on screen.
     **C** turns it round to face the bowler.
   - When you lock in power, the bowler steps up to the line, crouches and lets the ball go.
   - After every ball you're put back on your spot on the lane, facing the pins. Press **E** to pick up the ball again.
   - Your character stands still in a two-hand bowler's stance the whole time; only the ball's start spot moves.
     On release they crouch and let the ball go.
   - While aiming, the bowler waits a couple of steps back on the approach.
     The camera sits low in front of them with a wide lens, so the red marker, the arrows and the pins are all on screen.
     **C** turns it round to face the bowler.
   - When you lock in power, the bowler steps up to the line, crouches and lets the ball go.
   - After every ball you're put back on your spot on the lane, facing the pins. Press **E** to pick up the ball again.
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
- `Config.Tickets` (adult only), `Config.GameDeals`, `Config.FamilyDeals` (empty = off): prices
- `Config.Staff`: ped model, coords, scenario
- `Config.Ball`: swing speeds (`positionSpeed`, `directionSpeed`, `spinSpeed`, `meterSpeed`; higher = harder),
  plus sweet spot, ball speeds, hook strength, aim/position range
- `Config.MaxPlayers`, `Config.InviteRange`, `Config.InviteSeconds`, `Config.BookingSeconds`, `Config.TurnTimeout`
