import {
    ActionRowBuilder,
    ButtonBuilder,
    ButtonStyle,
    MessageFlags,
    ModalBuilder,
    PermissionsBitField,
    StringSelectMenuBuilder,
    TextInputBuilder,
    TextInputStyle,
} from 'discord.js';
import { createEmbed, errorEmbed } from '../utils/embeds.js';
import { logger } from '../utils/logger.js';
import {
    findPayoutEntry,
    formatFieldDisplay,
    formatFieldInput,
    getGuildJobPayouts,
    listPayoutEntries,
    parseEntryInput,
    resetGuildJobPayouts,
    setGuildJobPayout,
} from '../services/jobPayouts.js';

const SELECT_ID = 'payout_select';
const MODAL_ID = 'payout_modal';
const RESET_ID = 'payout_reset';
const RESET_CONFIRM_ID = 'payout_reset_confirm';
const RESET_CANCEL_ID = 'payout_reset_cancel';

function canManage(interaction) {
    return interaction.member?.permissions?.has(PermissionsBitField.Flags.ManageGuild);
}

async function denyAccess(interaction) {
    await interaction.reply({
        embeds: [errorEmbed('You need **Manage Server** permission to change job payouts.')],
        flags: MessageFlags.Ephemeral,
    });
}

function describeEntry(entry) {
    const { fields, values } = entry;
    const parts = [];
    const min = fields.find(f => f.name === 'min');
    if (min) parts.push(`**${formatFieldDisplay(min, values.min)} – ${formatFieldDisplay(min, values.max)}**`);

    for (const field of fields) {
        if (field.name === 'min' || field.name === 'max') continue;
        const value = `**${formatFieldDisplay(field, values[field.name])}**`;
        parts.push(field.short === 'amount' ? value : `${field.short} ${value}`);
    }

    return parts.join(' · ');
}

// Builds the /payout panel: every job's current payout, a job picker and a reset button.
export function buildPayoutPanel(payouts, { notice = null, confirmReset = false } = {}) {
    const entries = listPayoutEntries(payouts);

    const groups = new Map();
    for (const entry of entries) {
        if (!groups.has(entry.command)) groups.set(entry.command, []);
        groups.get(entry.command).push(entry);
    }

    const fields = [...groups].map(([command, group]) => ({
        name: command,
        value: group
            .map(entry => (entry.label === command ? describeEntry(entry) : `${entry.label.split(' — ')[1]}: ${describeEntry(entry)}`))
            .join('\n'),
    }));

    const embed = createEmbed({
        title: '💼 Job Payouts',
        description: [
            notice,
            'Pick a job below to change its payout. Changes apply to this server straight away.',
        ].filter(Boolean).join('\n\n'),
        color: 'economy',
        fields,
    });

    const select = new StringSelectMenuBuilder()
        .setCustomId(SELECT_ID)
        .setPlaceholder('Choose a job to edit…')
        .addOptions(entries.map(entry => ({
            label: entry.label.slice(0, 100),
            value: entry.key,
            description: describeEntry(entry).replace(/\*\*/g, '').slice(0, 100),
        })));

    const buttons = confirmReset
        ? [
            new ButtonBuilder().setCustomId(RESET_CONFIRM_ID).setLabel('Yes, reset everything').setStyle(ButtonStyle.Danger),
            new ButtonBuilder().setCustomId(RESET_CANCEL_ID).setLabel('Cancel').setStyle(ButtonStyle.Secondary),
        ]
        : [new ButtonBuilder().setCustomId(RESET_ID).setLabel('Reset all to defaults').setStyle(ButtonStyle.Danger)];

    return {
        embeds: [embed],
        components: [
            new ActionRowBuilder().addComponents(select),
            new ActionRowBuilder().addComponents(buttons),
        ],
    };
}

export const payoutSelectMenu = {
    name: SELECT_ID,
    async execute(interaction, client) {
        if (!canManage(interaction)) return denyAccess(interaction);

        const payouts = await getGuildJobPayouts(client, interaction.guildId);
        const entry = findPayoutEntry(payouts, interaction.values[0]);
        if (!entry) {
            return interaction.reply({ embeds: [errorEmbed('That job no longer exists.')], flags: MessageFlags.Ephemeral });
        }

        const modal = new ModalBuilder()
            .setCustomId(`${MODAL_ID}:${entry.key}`)
            .setTitle(`Edit ${entry.label}`.slice(0, 45));

        for (const field of entry.fields) {
            modal.addComponents(new ActionRowBuilder().addComponents(
                new TextInputBuilder()
                    .setCustomId(field.name)
                    .setLabel(field.label.slice(0, 45))
                    .setStyle(TextInputStyle.Short)
                    .setRequired(true)
                    .setValue(formatFieldInput(field, entry.values[field.name])),
            ));
        }

        await interaction.showModal(modal);
    },
};

export const payoutModal = {
    name: MODAL_ID,
    async execute(interaction, client, args) {
        if (!canManage(interaction)) return denyAccess(interaction);

        const key = args[0];
        const payouts = await getGuildJobPayouts(client, interaction.guildId);
        const entry = findPayoutEntry(payouts, key);
        if (!entry) {
            return interaction.reply({ embeds: [errorEmbed('That job no longer exists.')], flags: MessageFlags.Ephemeral });
        }

        const raw = Object.fromEntries(entry.fields.map(f => [f.name, interaction.fields.getTextInputValue(f.name)]));
        const { values, error } = parseEntryInput(entry, raw);
        if (error) {
            return interaction.reply({ embeds: [errorEmbed(`Nothing was saved. ${error}`)], flags: MessageFlags.Ephemeral });
        }

        const updated = await setGuildJobPayout(client, interaction.guildId, key, values);
        logger.info(`Job payout updated: ${key}`, { guildId: interaction.guildId, userId: interaction.user.id, values });

        const panel = buildPayoutPanel(updated, { notice: `✅ Updated **${entry.label}**.` });
        if (interaction.isFromMessage()) {
            await interaction.update(panel);
        } else {
            await interaction.reply({ ...panel, flags: MessageFlags.Ephemeral });
        }
    },
};

const resetButton = {
    name: RESET_ID,
    async execute(interaction, client) {
        if (!canManage(interaction)) return denyAccess(interaction);
        const payouts = await getGuildJobPayouts(client, interaction.guildId);
        await interaction.update(buildPayoutPanel(payouts, {
            notice: '⚠️ This sets **every** job back to the default payouts. Are you sure?',
            confirmReset: true,
        }));
    },
};

const resetConfirmButton = {
    name: RESET_CONFIRM_ID,
    async execute(interaction, client) {
        if (!canManage(interaction)) return denyAccess(interaction);
        const payouts = await resetGuildJobPayouts(client, interaction.guildId);
        logger.info('Job payouts reset to defaults', { guildId: interaction.guildId, userId: interaction.user.id });
        await interaction.update(buildPayoutPanel(payouts, { notice: '✅ All jobs reset to default payouts.' }));
    },
};

const resetCancelButton = {
    name: RESET_CANCEL_ID,
    async execute(interaction, client) {
        const payouts = await getGuildJobPayouts(client, interaction.guildId);
        await interaction.update(buildPayoutPanel(payouts));
    },
};

export const payoutButtons = [resetButton, resetConfirmButton, resetCancelButton];
