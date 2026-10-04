# pinkFrog_scratchcard: NRP economy config

`server.lua` / `client.lua` are escrow-encrypted by pinkFrog, so only `shared/config.lua` can be changed.
Drop this `config.lua` into `pinkFrog_scratchcard/shared/` and restart the resource.

**Cash only.** Every card pays money and nothing else. The pictures on Bingo cards (water, bandage, jammer, USB) are just symbols, and every match pays cash.
Most wins are $5-$10.

| Card | Win chance | Prizes |
|---|---|---|
| Green Bingo | 1 in 28 | $5-$10 |
| Blue Bingo | 1 in 28 | $5-$10, money symbol $20-$50 |
| Dollars Diamond | 8% | $5 / $8 / $10 most of the time, $25 (6% of wins), $100 jackpot (2%) |
| The Scratcher | 6% | $5-$10 most of the time, crown $10-$20, pool $25-$50, 3x diamond $100-$250 |
| Lottery | hourly | $25 tickets, needs at least 1 hit, max 95% of pool |

Bingo odds are fixed by the encrypted script: 3 of each of 3 items on the grid, and you scratch 3 cells.
That's a 1 in 28 (3.6%) win, so only the prizes could be lowered there.

Spamming a card nonstop for an hour (450 cards) pays roughly $15-$40 in total.
