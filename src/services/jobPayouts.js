import { jobPayouts as DEFAULT_JOB_PAYOUTS } from '../config/economy/payouts.js';
import { getGuildConfig, updateGuildConfig } from './guildConfig.js';

// Field kinds control how a value is shown and validated.
// money: whole number >= 0, chance: 0-1 (entered as a percent), mult: number >= 0.
const MONEY = 'money';
const CHANCE = 'chance';
const MULT = 'mult';

export const toSlug = name => name.toLowerCase().replace(/\s+/g, '-');

const JOB_FIELDS = {
    work: [['min', 'Min payout', MONEY], ['max', 'Max payout', MONEY], ['laptopMultiplier', 'Laptop multiplier', MULT, 'laptop']],
    beg: [['min', 'Min payout', MONEY], ['max', 'Max payout', MONEY], ['successChance', 'Success chance %', CHANCE, 'success']],
    daily: [['amount', 'Daily amount', MONEY, 'amount'], ['premiumBonus', 'Premium bonus %', CHANCE, 'premium bonus']],
    fish: [['min', 'Min payout', MONEY], ['max', 'Max payout', MONEY], ['fishingRodMultiplier', 'Fishing rod multiplier', MULT, 'rod']],
    mine: [
        ['min', 'Min payout', MONEY],
        ['max', 'Max payout', MONEY],
        ['pickaxeMultiplier', 'Pickaxe multiplier', MULT, 'pickaxe'],
        ['diamondPickaxeMultiplier', 'Diamond pickaxe multiplier', MULT, 'diamond pickaxe'],
    ],
    gamble: [
        ['baseWinChance', 'Base win chance %', CHANCE, 'win chance'],
        ['payoutMultiplier', 'Win payout multiplier', MULT, 'win pays bet'],
        ['cloverWinBonus', 'Clover win bonus %', CHANCE, 'clover'],
        ['charmWinBonus', 'Charm win bonus %', CHANCE, 'charm'],
    ],
    rob: [
        ['successChance', 'Success chance %', CHANCE, 'success'],
        ['stealPercentage', 'Steal % of victim wallet', CHANCE, 'steals'],
        ['finePercentage', 'Fine % of own wallet', CHANCE, 'fine'],
    ],
};

const CRIME_FIELDS = [['min', 'Min payout', MONEY], ['max', 'Max payout', MONEY], ['risk', 'Chance of getting caught %', CHANCE, 'caught']];
const SLUT_FIELDS = [['min', 'Min payout', MONEY], ['max', 'Max payout', MONEY], ['risk', 'Risk % (higher = less success)', CHANCE, 'risk']];

// [name, form label, kind, short label shown in the /payout list]
const toFields = defs => defs.map(([name, label, kind, short = name]) => ({ name, label, kind, short }));

// Every editable job, keyed by a stable id used in guild overrides and component custom ids.
export function listPayoutEntries(payouts) {
    const entries = Object.keys(JOB_FIELDS).map(job => ({
        key: job,
        command: `/${job}`,
        label: `/${job}`,
        fields: toFields(JOB_FIELDS[job]),
        values: payouts[job],
    }));

    for (const type of payouts.crime.types) {
        entries.push({
            key: `crime.${toSlug(type.name)}`,
            command: '/crime',
            label: `/crime — ${type.name}`,
            fields: toFields(CRIME_FIELDS),
            values: type,
        });
    }

    for (const activity of payouts.slut.activities) {
        entries.push({
            key: `slut.${toSlug(activity.name)}`,
            command: '/slut',
            label: `/slut — ${activity.name}`,
            fields: toFields(SLUT_FIELDS),
            values: activity,
        });
    }

    return entries;
}

export function findPayoutEntry(payouts, key) {
    return listPayoutEntries(payouts).find(entry => entry.key === key) || null;
}

// Defaults from the config file with this guild's overrides layered on top.
export function resolveJobPayouts(overrides = {}) {
    const resolved = {};

    for (const job of Object.keys(JOB_FIELDS)) {
        resolved[job] = { ...DEFAULT_JOB_PAYOUTS[job], ...(overrides[job] || {}) };
    }

    resolved.crime = {
        types: DEFAULT_JOB_PAYOUTS.crime.types.map(type => ({
            ...type,
            ...(overrides[`crime.${toSlug(type.name)}`] || {}),
        })),
    };

    resolved.slut = {
        activities: DEFAULT_JOB_PAYOUTS.slut.activities.map(activity => ({
            ...activity,
            ...(overrides[`slut.${toSlug(activity.name)}`] || {}),
        })),
    };

    return resolved;
}

export async function getGuildJobPayouts(client, guildId) {
    const config = await getGuildConfig(client, guildId);
    return resolveJobPayouts(config.jobPayouts || {});
}

export async function setGuildJobPayout(client, guildId, key, values) {
    const config = await getGuildConfig(client, guildId);
    const overrides = { ...(config.jobPayouts || {}), [key]: values };
    await updateGuildConfig(client, guildId, { jobPayouts: overrides });
    return resolveJobPayouts(overrides);
}

export async function resetGuildJobPayouts(client, guildId) {
    await updateGuildConfig(client, guildId, { jobPayouts: {} });
    return resolveJobPayouts({});
}

// Display a stored value the way an admin types it (chances as percents).
export function formatFieldInput(field, value) {
    if (field.kind === CHANCE) return String(Math.round(value * 1000) / 10);
    return String(value);
}

export function formatFieldDisplay(field, value) {
    if (field.kind === MONEY) return `$${Number(value).toLocaleString()}`;
    if (field.kind === CHANCE) return `${Math.round(value * 1000) / 10}%`;
    return `x${value}`;
}

// Parses admin input for one entry. Returns { values } or { error }.
export function parseEntryInput(entry, rawValues) {
    const values = {};

    for (const field of entry.fields) {
        const raw = String(rawValues[field.name] ?? '').trim().replace(/[$,%x]/gi, '');
        const num = Number(raw);

        if (raw === '' || !Number.isFinite(num) || num < 0) {
            return { error: `**${field.label}** must be a number of 0 or more.` };
        }

        if (field.kind === MONEY) {
            if (!Number.isInteger(num)) return { error: `**${field.label}** must be a whole number.` };
            values[field.name] = num;
        } else if (field.kind === CHANCE) {
            if (num > 100) return { error: `**${field.label}** must be between 0 and 100.` };
            values[field.name] = num / 100;
        } else {
            values[field.name] = num;
        }
    }

    if ('min' in values && 'max' in values && values.min > values.max) {
        return { error: '**Min payout** cannot be higher than **Max payout**.' };
    }

    return { values };
}
