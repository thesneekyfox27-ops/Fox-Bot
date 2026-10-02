import { MessageFlags, PermissionFlagsBits, SlashCommandBuilder } from 'discord.js';
import { withErrorHandling } from '../../utils/errorHandler.js';
import { InteractionHelper } from '../../utils/interactionHelper.js';
import { getGuildJobPayouts } from '../../services/jobPayouts.js';
import { buildPayoutPanel } from '../../handlers/payoutPanel.js';

export default {
    data: new SlashCommandBuilder()
        .setName('payout')
        .setDescription('View and change the payouts for every job in this server')
        .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild),

    execute: withErrorHandling(async (interaction, config, client) => {
        const deferred = await InteractionHelper.safeDefer(interaction, { flags: MessageFlags.Ephemeral });
        if (!deferred) return;

        const payouts = await getGuildJobPayouts(client, interaction.guildId);
        await InteractionHelper.safeEditReply(interaction, buildPayoutPanel(payouts));
    }),
};
