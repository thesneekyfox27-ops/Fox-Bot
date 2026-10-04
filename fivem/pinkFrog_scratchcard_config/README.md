# pinkFrog_scratchcard: NRP economy config

`server.lua` / `client.lua` are escrow-encrypted by pinkFrog, so only `shared/config.lua` can be changed.
Drop this `config.lua` into `pinkFrog_scratchcard/shared/` and restart the resource.

Every prize is now under $500.

| Card | Before | After |
|---|---|---|
| Dollars Diamond | wins 95%, $5k-$150k | wins 8%, $50 / $100 / $250 / $450 |
| The Scratcher | wins 40%, $8k-$120k | wins 6%, $40-$495 |
| Green Bingo | $3k-$10k cash, 10-25 water, 5-15 bandages | $100-$300, 1-3 water, 1-2 bandages |
| Blue Bingo | $15k-$40k, 3-9 AP pistols, 20-50 jammers, 15-35 USBs | $150-$450, 1 jammer, 1 USB, 1-3 bandages, no guns |
| Lottery | draw every 3 min, $10k per ticket, always a winner, up to 10x pool | hourly, $25 per ticket, needs at least 1 hit, max 95% of pool |

Bingo odds are fixed by the encrypted script: 3 of each of 3 items on the grid, and you scratch 3 cells.
That's a 1 in 28 (3.6%) win, so only the prizes could be lowered there.

Simulated nonstop spam (one card every 8 s, 450 cards an hour):
- Diamond about $7.70 per card (was about $40,900)
- Scratcher about $8.60 per card
- Bingo about $2.50 per card in cash

Sell cards for $25+ and every card loses money on average, so spamming no longer pays.
