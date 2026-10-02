// Prints every job payout from src/config/economy/payouts.js.
// Usage: npm run payouts
import { jobPayouts } from '../src/config/economy/payouts.js';

const money = n => `$${Number(n).toLocaleString()}`;
const pct = n => `${Math.round(n * 1000) / 10}%`;
const mult = n => `x${n}`;

const rows = [];
const add = (job, detail, payout, notes = '') => rows.push({ job, detail, payout, notes });

const { work, beg, daily, fish, mine, crime, slut, gamble, rob } = jobPayouts;

add('/work', '', `${money(work.min)} - ${money(work.max)}`, `laptop ${mult(work.laptopMultiplier)}`);
add('/beg', '', `${money(beg.min)} - ${money(beg.max)}`, `success ${pct(beg.successChance)}`);
add('/daily', '', money(daily.amount), `premium +${pct(daily.premiumBonus)}`);
add('/fish', '', `${money(fish.min)} - ${money(fish.max)}`, `rod ${mult(fish.fishingRodMultiplier)}`);
add('/mine', '', `${money(mine.min)} - ${money(mine.max)}`,
    `pickaxe ${mult(mine.pickaxeMultiplier)}, diamond ${mult(mine.diamondPickaxeMultiplier)}`);
for (const c of crime.types) {
    add('/crime', c.name, `${money(c.min)} - ${money(c.max)}`, `caught ${pct(c.risk)}`);
}
for (const a of slut.activities) {
    const success = Math.max(0.35, 0.55 - a.risk * 0.2);
    add('/slut', a.name, `${money(a.min)} - ${money(a.max)}`, `success ${pct(success)}`);
}
add('/gamble', '', `bet ${mult(gamble.payoutMultiplier)}`,
    `win ${pct(gamble.baseWinChance)} (+${pct(gamble.cloverWinBonus)} clover, +${pct(gamble.charmWinBonus)} charm)`);
add('/rob', '', `${pct(rob.stealPercentage)} of victim wallet`,
    `success ${pct(rob.successChance)}, fine ${pct(rob.finePercentage)} of own wallet`);

const headers = { job: 'Job', detail: 'Type', payout: 'Payout', notes: 'Notes' };
const cols = Object.keys(headers);
const width = Object.fromEntries(cols.map(c => [c, Math.max(headers[c].length, ...rows.map(r => r[c].length))]));
const line = r => cols.map(c => r[c].padEnd(width[c])).join('  ').trimEnd();

console.log(line(headers));
console.log(cols.map(c => '-'.repeat(width[c])).join('  '));
for (const r of rows) console.log(line(r));
console.log('\nEdit src/config/economy/payouts.js to change these, then restart the bot.');
