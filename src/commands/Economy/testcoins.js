import { SlashCommandBuilder, PermissionFlagsBits, MessageFlags } from 'discord.js';
import { successEmbed, infoEmbed } from '../../utils/embeds.js';
import { getEconomyData, setEconomyData, TEST_MODE_BALANCE } from '../../utils/economy.js';
import { withErrorHandling, createError, ErrorTypes } from '../../utils/errorHandler.js';
import { logger } from '../../utils/logger.js';
import { InteractionHelper } from '../../utils/interactionHelper.js';
import { BotConfig } from '../../config/bot.js';

// Owner-only test mode: unlimited coins and no cooldowns for the person running it,
// in the server they ran it in. Your real wallet and bank are saved and come back with
// /testcoins off. Only user IDs listed in OWNER_IDS can use it.
function isOwner(userId) {
    return (BotConfig.commands?.owners || []).map(id => id.trim()).includes(userId);
}

export default {
    data: new SlashCommandBuilder()
        .setName('testcoins')
        .setDescription('Bot owner only: unlimited coins and no cooldowns for testing')
        .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
        .addSubcommand(sub => sub
            .setName('on')
            .setDescription('Turn on unlimited coins and no cooldowns for yourself'))
        .addSubcommand(sub => sub
            .setName('off')
            .setDescription('Turn test mode off and get your real balance back'))
        .addSubcommand(sub => sub
            .setName('status')
            .setDescription('Show whether test mode is on for you')),

    execute: withErrorHandling(async (interaction, config, client) => {
        const deferred = await InteractionHelper.safeDefer(interaction, { flags: MessageFlags.Ephemeral });
        if (!deferred) return;

        const userId = interaction.user.id;
        const guildId = interaction.guildId;

        if (!isOwner(userId)) {
            throw createError(
                "testcoins used by non-owner",
                ErrorTypes.PERMISSION,
                "Only the bot owner can use this. Add your Discord user ID to `OWNER_IDS` in the bot's `.env`.",
                { userId }
            );
        }

        const sub = interaction.options.getSubcommand();
        const data = await getEconomyData(client, guildId, userId);

        if (sub === 'status') {
            const msg = data.testMode
                ? `Test mode is **on**. Your wallet is always ${TEST_MODE_BALANCE.toLocaleString()} coins and cooldowns are off.`
                : 'Test mode is **off**.';
            await InteractionHelper.safeEditReply(interaction, { embeds: [infoEmbed(msg, '🧪 Test mode')] });
            return;
        }

        if (sub === 'on') {
            if (data.testMode) {
                await InteractionHelper.safeEditReply(interaction, { embeds: [infoEmbed('Test mode is already on.', '🧪 Test mode')] });
                return;
            }
            data.testSaved = { wallet: data.wallet || 0, bank: data.bank || 0 };
            data.testMode = true;
            await setEconomyData(client, guildId, userId, data);
            logger.info('[ECONOMY] Test mode on', { userId, guildId, saved: data.testSaved });
            await InteractionHelper.safeEditReply(interaction, {
                embeds: [successEmbed(
                    `Your wallet is now always **${TEST_MODE_BALANCE.toLocaleString()} coins** and every cooldown is off, ` +
                    `only for you in this server.\n\n` +
                    `Your real balance (wallet $${data.testSaved.wallet.toLocaleString()}, bank $${data.testSaved.bank.toLocaleString()}) ` +
                    `is saved. \`/testcoins off\` puts it back.\n\n` +
                    `While it's on you can't \`/pay\` or \`/rob\` other people, and you're hidden from the leaderboard.`,
                    '🧪 Test mode on'
                )],
            });
            return;
        }

        // off
        if (!data.testMode) {
            await InteractionHelper.safeEditReply(interaction, { embeds: [infoEmbed('Test mode is already off.', '🧪 Test mode')] });
            return;
        }
        const saved = data.testSaved || { wallet: 0, bank: 0 };
        const { testMode, testSaved, ...rest } = data;
        rest.wallet = saved.wallet;
        rest.bank = saved.bank;
        await setEconomyData(client, guildId, userId, rest);
        logger.info('[ECONOMY] Test mode off', { userId, guildId, restored: saved });
        await InteractionHelper.safeEditReply(interaction, {
            embeds: [successEmbed(
                `Your real balance is back: wallet $${saved.wallet.toLocaleString()}, bank $${saved.bank.toLocaleString()}.\n` +
                `Items you bought while testing stay in your inventory.`,
                '🧪 Test mode off'
            )],
        });
    }),
};
