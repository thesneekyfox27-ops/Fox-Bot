// =========================
// JOB PAYOUTS
// =========================
// Every economy command that pays out reads its numbers from this file.
// These are the defaults. Admins can override them per server with /payout;
// edit the values here and restart the bot to change the defaults.
// Run `npm run payouts` to print a summary table of everything below.
//
// Chances are decimals: 0.4 = 40%. Multipliers: 1.5 = +50%.

export const jobPayouts = {
    // /work — random amount between min and max.
    work: {
        min: 50,
        max: 300,
        // Applied when the user owns a laptop.
        laptopMultiplier: 1.5,
    },

    // /beg — succeeds `successChance` of the time, then pays min..max.
    beg: {
        min: 50,
        max: 200,
        successChance: 0.7,
    },

    // /daily — flat amount, plus a bonus for the guild's premium role.
    daily: {
        amount: 1000,
        premiumBonus: 0.1,
    },

    // /fish — random amount between min and max.
    fish: {
        min: 300,
        max: 900,
        // Applied when the user owns a fishing rod.
        fishingRodMultiplier: 1.5,
    },

    // /mine — random amount between min and max.
    mine: {
        min: 400,
        max: 1200,
        pickaxeMultiplier: 1.2,
        diamondPickaxeMultiplier: 2.0,
    },

    // /crime — each type pays min..max; `risk` is the chance of getting caught.
    // Names appear as the command's choices, so renaming one here renames it in Discord
    // (re-deploy slash commands after renaming).
    crime: {
        types: [
            { name: "Pickpocketing", min: 100, max: 500, risk: 0.3 },
            { name: "Burglary", min: 300, max: 1000, risk: 0.4 },
            { name: "Bank Heist", min: 1000, max: 5000, risk: 0.6 },
            { name: "Art Theft", min: 2000, max: 10000, risk: 0.7 },
            { name: "Cybercrime", min: 5000, max: 20000, risk: 0.8 },
        ],
    },

    // /slut — a random activity is picked; a successful roll pays min..max.
    // Higher `risk` lowers the success chance (never below 35%).
    slut: {
        activities: [
            { name: "Cam Stream", min: 120, max: 450, risk: 0.2 },
            { name: "Private Dance Session", min: 220, max: 700, risk: 0.25 },
            { name: "After-Hours Club Host", min: 320, max: 900, risk: 0.3 },
            { name: "VIP Companion Booking", min: 550, max: 1400, risk: 0.35 },
            { name: "Exclusive Livestream", min: 850, max: 2200, risk: 0.4 },
        ],
    },

    // /gamble — a win pays bet × payoutMultiplier.
    gamble: {
        baseWinChance: 0.4,
        payoutMultiplier: 2.0,
        cloverWinBonus: 0.1,
        charmWinBonus: 0.08,
    },

    // /rob — on success steals stealPercentage of the victim's wallet;
    // on failure the robber is fined finePercentage of their own wallet.
    rob: {
        successChance: 0.25,
        stealPercentage: 0.15,
        finePercentage: 0.1,
    },
};
