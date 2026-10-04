Config = {}

Config.Framework = 'qb' -- auto / esx / qb / qbox

Config.Language = 'EN' -- PL / EN

Config.ItemName               = 'lottery_ticket'    -- original lottery (number grid)
Config.ScratchItemName        = 'green_bingo'        -- scratchcard (3x3 BINGO) green
Config.ScratchItemNameBlue    = 'blue_bingo'         -- scratchcard (3x3 BINGO) blue
Config.ScratchItemNameDiamond = 'dollars_diamond'    -- scratchcard (3x3) dollars/diamond
Config.ScratchItemNameScratcher = 'the_scratcher'   -- scratchcard (3x3) The Scratcher

-- ── SCRATCHCARD ──────────────────────────────────────────────
-- Base URL for item images. Must end WITHOUT a trailing slash.
-- Examples:
--   nui://ox_inventory/web/images
--   nui://qs-inventory/html/img/items
--   nui://ps-inventory/html/images/items
Config.ItemImagePath = 'nui://inventory_images/images'

-- Items placed on the 3x3 grid (3 copies of each of 3 randomly selected items)
-- Item names must match your inventory image filenames (e.g. ox_inventory)
-- 3 item types → grid of 3 copies each = 9 cells (same as blue bingo)
Config.ScratchItems = {
    'money',
    'water',
    'bandage',
}

-- Reward when player finds 3 matching icons
-- item  = item name to give
-- min   = minimum quantity (inclusive)
-- max   = maximum quantity (inclusive)
-- label = display name shown in result overlay
-- NRP economy: the grid always holds 3 of each of 3 items and you scratch 3 cells,
-- so a card wins 1 time in 28 (3.6%). Keep prizes small.
Config.ScratchRewards = {
    money      = { item = 'cash',      min = 100,  max = 300,   label = 'cash'    },
    water      = { item = 'water',      min = 1,    max = 3,     label = 'water'   },
    bandage    = { item = 'bandage',    min = 1,    max = 2,     label = 'bandage' },
}

-- ── BLUE BINGO (blue_bingo) ──────────────────────────────────
-- NRP economy: AP pistols removed (scratchcards were a gun printer).
Config.ScratchItemsBlue = {
    'jammer',
    'usb_black',
    'bandage',
    'money',
}

Config.ScratchRewardsBlue = {
    jammer       = { item = 'jammer',       min = 1, max = 1, label = 'Jammer'    },
    usb_black     = { item = 'usb_black',      min = 1, max = 1, label = 'Hack Usb'   },
    bandage    = { item = 'bandage',    min = 1,  max = 3, label = 'bandage' },
    money      = { item = 'money',      min = 150,  max = 450,  label = 'Money'   },
}

-- ── DOLLARS DIAMOND (dollars_diamond) ───────────────────────
-- (strips are cash-based — no item pool needed here)

-- ══════════════════════════════════════════════════════════════
--  BINGO WIN CHANCES  (unused — win is determined by scratched items)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
--  DOLLARS DIAMOND  —  strip-based cash prizes
-- ══════════════════════════════════════════════════════════════
-- MATCH-3 mechanic: every strip shows a cash amount. Find `matchRequired`
-- identical amounts to win that amount.
Config.DiamondStrips = {
    stripCount    = 5,   -- number of scratchable strips
    matchRequired = 3,   -- how many identical amounts must appear to win
    winChance     = 8,   -- % chance the card is a winner (was 95!). About 1 card in 12.
    -- Item image shown in the win overlay (from Config.ItemImagePath, e.g. money.png).
    -- Since Diamond pays cash, we display the 'money' inventory icon by default.
    winImage      = 'money',

    -- weight = relative probability that this amount is the winning one.
    -- Total weight = 100, so each weight reads directly as a % of all wins.
    prizes = {
        { amount = 50,     weight = 60 },  -- 60% of wins → $50
        { amount = 100,    weight = 25 },  -- 25% of wins → $100
        { amount = 250,    weight = 12 },  -- 12% of wins → $250
        { amount = 450,    weight = 3  },  --  3% of wins → $450 (jackpot)
    },
}

-- ══════════════════════════════════════════════════════════════
--  THE SCRATCHER  —  symbol-matching prizes
-- ══════════════════════════════════════════════════════════════
Config.ScatcherStrips = {
    stripCount = 5,      -- number of SCRATCHABLE strips (the header strip is separate and always visible)
    winChance  = 6,      -- % chance the card is a winner (was 40!). About 1 card in 17.
    headerIcon = 'images/coin.png',   -- icon displayed above the card (change freely)

    -- Items that can appear on strips.
    --   name     = key used internally (must match filename in images/scratcher_icons/, without extension)
    --   required = how many of this symbol the player must find among the 6 strips to win
    --   weight   = relative probability of appearing on a strip (higher = more common)
    --   reward   = item given when win condition is met
    items = {
        { name = 'diamond',    required = 3, weight = 5,  reward = { item = 'money', min = 400, max = 495, label = 'Money' } },  -- jackpot (3x, rarest)
        { name = 'pool',       required = 2, weight = 10, reward = { item = 'money', min = 200, max = 300, label = 'Money' } },  -- rare
        { name = 'crown',      required = 2, weight = 15, reward = { item = 'money', min = 150, max = 250, label = 'Money' } },
        { name = 'island',     required = 2, weight = 20, reward = { item = 'money', min = 75,  max = 150, label = 'Money' } },
        { name = 'beach_ball', required = 2, weight = 20, reward = { item = 'money', min = 75,  max = 150, label = 'Money' } },
        { name = 'palm',       required = 2, weight = 30, reward = { item = 'money', min = 40,  max = 80,  label = 'Money' } },  -- most common
    },
}


-- How often the draw happens (in hours)
Config.DrawIntervalHours = 1.0   -- was 0.05 (a draw every 3 minutes!) - now once an hour

-- How many numbers the player must select on their ticket
Config.PlayerSelectCount = 3

-- How many numbers the server draws each round (out of 1-56)
Config.DrawCount = 5

-- Amount added to the prize pool each time a player submits a ticket
Config.PoolContribution = 25    -- was 10000 per ticket

-- If true:  always pick a winner from active tickets (even with 0 hits).
-- If false: only tickets with at least 1 hit win. No hits = pool carries over.
Config.AlwaysSomeoneWin = false   -- was true (someone always got paid, even with 0 hits)

-- Pool multiplier applied when nobody wins (pool carries over)
-- e.g. 1.2 = pool grows by 20% each draw with no winner
Config.PoolMultiplierOnNoWin = 1.0   -- was 1.2 (pool grew by itself every empty draw)

-- Payout as % of the current pool, based on number of hits
-- [0] is used only when AlwaysSomeoneWin = true and winner has 0 hits
-- Max hits = PlayerSelectCount (3)
-- NRP economy: was 50 / 100 / 400 / 1000 % (3 hits paid TEN TIMES the pool).
-- With $25 a ticket, 20 players in a draw = a $500 pool.
Config.PoolPayouts = {
    [0] = 0,
    [1] = 10,
    [2] = 40,
    [3] = 95,
}

-- Locale strings
Config.Locale = {
    PL = {
        notify_title     = 'Zdrapka',
        draw_title       = 'WYNIKI LOSOWANIA ZDRAPKI',
        drawn_numbers    = 'Wylosowane liczby',
        pool_label       = 'Pula',
        hits_label       = 'Trafienia',
        of_pool          = 'puli',
        winner           = 'Wygrał/a',
        no_winner        = 'Nikt nie wygrał. Aktualna pula przechodzi do ponownego losowania.',
        reward           = 'Nagroda',
        forced_by        = 'Losowanie zostało odbyte przez pracownika San Andreas State Lottery',
        already_in_pool  = 'Masz już los w puli. Poczekaj na wyniki losowania.',
        no_item          = 'Nie posiadasz zdrapki.',
        ticket_added     = 'Los został dodany do puli! Czekaj na losowanie.',
        you_won          = 'Wygrałeś/aś $%d! Sprawdź swoje kieszenie.',
        -- UI
        select_exact     = 'Musisz zaznaczyć dokładnie %d numerów.',
        ui_title         = 'WYBIERZ TRZY I WYGRAJ NIESAMOWITE NAGRODY!',
        ui_count_label   = 'ILOŚĆ NUMERÓW',
        ui_numbers_label = 'NUMERKI',
        ui_confirm_btn   = 'POTWIERDŹ',
        -- The Scratcher header strip text
        scratcher_find   = 'ZNAJDŹ',
        scratcher_win    = 'ABY WYGRAĆ NAGRODĘ',
        -- Scratchcard taglines (nagłówek nad planszą)
        tagline_green    = 'ZNAJDŹ TRZY TAKIE SAME OBRAZKI I WYGRAJ NAGRODĘ!',
        tagline_blue     = 'ZNAJDŹ TRZY TAKIE SAME OBRAZKI I WYGRAJ NAGRODĘ!',
        tagline_diamond  = 'ZNAJDŹ TRZY TAKIE SAME KWOTY I WYGRAJ NAGRODĘ!',
        -- Scratchcard result overlay
        result_win       = '🎉 UDAŁO CI SIĘ WYGRAĆ!',
        result_lose      = 'BRAK WYGRANEJ',
        result_retry     = 'Spróbuj ponownie!',
        result_confirm   = 'YAY!',
        -- Notify messages
        notify_win       = 'Wygrałeś! %s',
        notify_win_cash  = 'Wygrałeś $%d!',
        notify_lose      = 'Niestety, brak wygranej.',
        -- Webhook
        webhook_announce_title   = '🎰 LOSOWANIE W TOKU',
        webhook_announce_desc    = 'Rozpoczynamy sprawdzanie Waszych numerów!\nW dzisiejszej puli znajduje się: **%{pool}**\n\nSzczęśliwy numer zostanie ogłoszony lada moment...',
        webhook_winner_title     = '💸 JEST ZWYCIĘZCA',
        webhook_winner_desc      = 'Zwycięzca: **%{names}**\nWygrana: **%{reward}**\n\nWylosowane numery: %{drawn}',
        webhook_no_winner_title  = '📣 BRAK ZWYCIĘZCY',
        webhook_no_winner_desc   = 'Wylosowane numery: **%{drawn}**\n\nNiestety nikt nie trafił!\nPula **%{pool}** przechodzi na kolejny dzień z mnożnikiem → **%{newpool}**',
    },
    EN = {
        notify_title     = 'Scratchcard',
        draw_title       = 'SCRATCHCARD DRAW RESULTS',
        drawn_numbers    = 'Drawn numbers',
        pool_label       = 'Pool',
        hits_label       = 'Hits',
        of_pool          = 'of pool',
        winner           = 'Winner',
        no_winner        = 'Nobody won. The current pool carries over to the next draw.',
        reward           = 'Reward',
        forced_by        = 'This draw was conducted by a San Andreas State Lottery employee',
        already_in_pool  = 'You already have a ticket in the pool. Wait for the results.',
        no_item          = 'You do not have a scratchcard.',
        ticket_added     = 'Your ticket has been added to the pool! Wait for the draw.',
        you_won          = 'You won $%d! Check your pockets.',
        -- UI
        select_exact     = 'You must select exactly %d numbers.',
        ui_title         = 'SELECT THREE AND WIN INCREDIBLE PRIZES!',
        ui_count_label   = 'NUMBER COUNT',
        ui_numbers_label = 'NUMBERS',
        ui_confirm_btn   = 'CONFIRM',
        -- The Scratcher header strip text
        scratcher_find   = 'FIND',
        scratcher_win    = 'TO WIN THE PRIZE',
        -- Scratchcard taglines (header above the board)
        tagline_green    = 'FIND THREE SAME IMAGES AND WIN THE PRIZE!',
        tagline_blue     = 'FIND THREE SAME IMAGES AND WIN THE PRIZE!',
        tagline_diamond  = 'FIND THREE SAME AMOUNTS AND WIN THE PRIZE!',
        -- Scratchcard result overlay
        result_win       = 'NO WAY… YOU WON!',
        result_lose      = 'NO WIN',
        result_retry     = 'Try again!',
        result_confirm   = 'YAY!',
        -- Notify messages
        notify_win       = 'You won! %s',
        notify_win_cash  = 'You won $%d!',
        notify_lose      = 'Better luck next time!',
        -- Webhook
        webhook_announce_title   = '🎰 DRAW IN PROGRESS',
        webhook_announce_desc    = 'We are checking all tickets!\nToday\'s prize pool: **%{pool}**\n\nThe lucky numbers will be revealed shortly...',
        webhook_winner_title     = '💸 WE HAVE A WINNER',
        webhook_winner_desc      = 'Winner: **%{names}**\nPrize: **%{reward}**\n\nDrawn numbers: %{drawn}',
        webhook_no_winner_title  = '📣 NO WINNER',
        webhook_no_winner_desc   = 'Drawn numbers: **%{drawn}**\n\nNo one matched the numbers!\nPool **%{pool}** carries over with multiplier → **%{newpool}**',
    }
}