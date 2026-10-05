# nrp-bowling v2.8.3

A full rebuild of `loaf_bowling` for the Breze bowling MLO (the `bowling` map resource, unchanged).

## Install
1. Remove `loaf_bowling`. Keep the `bowling` map resource.
2. server.cfg:
   ```
   ensure bowling
   ensure nrp-bowling
   ```
3. **Place the staff ped in game:** as an admin, stand where she should be (facing where customers stand) and type **`/bowlstaff`**.
   She moves there for everyone right away and the spot is saved on the server (resource KVP, backed up to `staff.json`).
   It survives restarts and dropping in a new version of the zip.
   (`/bowlcoords` still prints your position if you'd rather put it in `Config.Staff.coords`.)
4. **Place each lane's ball return:** as an admin, stand at the ball return for a lane and type **`/bowlreturn 1`** (the lane number).
   With no number it picks the lane whose circle is closest. Spots are saved the same way (KVP + `returns.json`), so they stay after restarts and updates.
   Lanes you skip use a guess (behind the circle, between the lane pair; see `Config.ReturnBack` / `Config.ReturnSide`).

## How it works
1. **Talk to the staff ped** at the desk (ox_target / qb-target, or press **E**). The neon price sheet opens:
   - **Adult tickets:** 1 game $9, 2 games $17. Friends you invite pay for their own ticket when they accept.
   - **Game deals** (2 games, host pays for everyone): 2–6 players, $34–$102.
     A deal **stays locked until you've invited enough friends** standing near you to fill it; the button shows "Invite N more".
     The server checks this as well.
   - Tick friends standing near you to invite them, choose **Cash** or **Card**, then **Pay & pick lane**.
     Card takes the money from the bank. Refunds go back to the same place you paid from.
     `Config.PayMethods` sets the options (remove one to allow only the other); `Config.Account` is the one picked by default.
2. **Pick your lane** at the desk, or hit **Auto pick a free lane**. Don't pick within 90 s and you're refunded.
3. **Invites** pop up for your friends with a 45 s timer:
   - On a deal they join **free**.
   - On a single ticket they pay the adult price when they join, by cash or card (their choice on the invite).
4. The lane owner presses **G** at the lane to start. 2-game tickets and deals play game 1 and then game 2 automatically.
5. On your turn, a **blue marker with a bouncing arrow** shows your lane's **ball return**, and a **flashing map blip** points to it.
   Press **E** there: your character bends down and picks up a ball in their right hand.
   Then **walk the ball** at your side (no running, jumping or crouching) to the **glowing ring** on the lane and press **E** to start aiming.
   After every ball you're free to move again; go back to the ball return for your next one.
6. **Skill-based throw.** The markers are painted on the real lane, like the video, and each one swings by itself.
   Press **SPACE** to lock each one:
   1. **Position:** a red marker slides along the foul line.
   2. **Direction:** a dark arrow sweeps left and right down the lane.
   3. **Spin:** a sideways arrow on the lane; the ball hooks that way late in the lane.
   4. **Power:** stop the meter in the blue for a perfectly accurate ball.
   **BACKSPACE** goes back a step, and **C** changes the camera.
   - Your character stands still holding the ball the whole time; only the ball's start spot moves.
     On release they swing the ball through underhand.
   - While aiming, the bowler waits a couple of steps back on the approach.
     The camera sits low in front of them with a wide lens, so the red marker, the arrows and the pins are all on screen.
     **C** or **V** cycles 3 cameras: down the lane, facing the bowler, side view.
     If C is your crouch key, the crouch is cancelled straight away while you bowl.
   - When you lock in power, the bowler walks up to the line and swings the ball through underhand.
     GTA has no real bowling animation, so this is the closest built-in one.
     The default is `Config.AnimPreset = 'original'` (loaf_bowling's animations, ball in the right hand).
     Set it to `'bowling'` for a two-hand hold and underhand swing, or put a custom animation in `Config.Anims`.
   - **BACKSPACE** on the first step steps you out of the circle, still holding the ball.
   - After every ball you're left at the line; walk back to the ball return for the next one.
7. **Lane monitor:** red and blue player rows, white frame boxes, yellow scores, **Max** possible score, the total, and "Game 1 of 2".
   STRIKE / SPARE / GUTTER banners show, and the winner is announced at the end.
8. **DELETE** leaves your lane.

## Sounds
All sound files are in `html/sounds/`. To swap one, drop in your own mp3 with the same name. Volumes are set in `Config.Sounds`.
- `release.mp3`: when the ball leaves your hand.
- `pins.mp3`: when the ball hits the pins.
- `spare.mp3` and `strike.mp3`: play on a spare or strike.
- `gutter.mp3`: plays when a ball knocks down no pins.
- All of these clips are levelled to the same loudness. At volume 0.7 they sit a little above the background music (0.25).
- `ambient1.mp3` and `ambient2.mp3`: background music inside the building.
  They play one after the other and loop back round, fading in as you walk in and out as you leave.
  `Config.Sounds.ambient` sets the area (`center` / `radius`) and the volume.

**No sound?** Type **`/bowlsound`**. It plays the strike sound and prints to F8 whether you're inside the music area.
If a sound can't play, the reason is printed in F8 too (`[nrp-bowling] sound "..." did not play: ...`).

Lane sounds are heard by everyone near that lane, and get quieter the further away you are (`hearDistance`).

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
