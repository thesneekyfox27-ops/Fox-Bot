import { SlashCommandBuilder, PermissionFlagsBits, ChannelType, MessageFlags } from 'discord.js';
import { createEmbed, errorEmbed, successEmbed } from '../../utils/embeds.js';
import { logger } from '../../utils/logger.js';
import { handleInteractionError } from '../../utils/errorHandler.js';
import { InteractionHelper } from '../../utils/interactionHelper.js';
import {
    getWordFilterConfig,
    updateWordFilterConfig,
    getMatcher
} from '../../services/wordFilterService.js';
import { findBlockedWords, maskWord } from '../../utils/profanityFilter.js';

const MAX_CUSTOM_WORDS = 200;
const MAX_WORD_LENGTH = 50;

function normalizeEntry(word) {
    return word.trim().toLowerCase();
}

function toggleInList(list, value) {
    return list.includes(value)
        ? { list: list.filter((item) => item !== value), added: false }
        : { list: [...list, value], added: true };
}

export default {
    data: new SlashCommandBuilder()
        .setName("wordfilter")
        .setDescription("Automatically remove slurs and blocked words")
        .addSubcommand((s) => s.setName("enable").setDescription("Turn the word filter on"))
        .addSubcommand((s) => s.setName("disable").setDescription("Turn the word filter off"))
        .addSubcommand((s) => s.setName("status").setDescription("Show the word filter settings"))
        .addSubcommand((s) =>
            s
                .setName("action")
                .setDescription("Choose what happens when a blocked word is sent")
                .addStringOption((o) =>
                    o
                        .setName("type")
                        .setDescription("Action to take")
                        .setRequired(true)
                        .addChoices(
                            { name: "Delete the message", value: "delete" },
                            { name: "Delete + warn the user", value: "warn" },
                            { name: "Delete + warn + timeout", value: "timeout" },
                        ),
                )
                .addIntegerOption((o) =>
                    o
                        .setName("timeout_minutes")
                        .setDescription("Timeout length in minutes (for the timeout action)")
                        .setMinValue(1)
                        .setMaxValue(40320),
                ),
        )
        .addSubcommand((s) =>
            s
                .setName("add")
                .setDescription("Block an extra word (use *word* to also match inside other words)")
                .addStringOption((o) =>
                    o.setName("word").setDescription("Word to block").setRequired(true).setMaxLength(MAX_WORD_LENGTH),
                ),
        )
        .addSubcommand((s) =>
            s
                .setName("remove")
                .setDescription("Remove a word you added")
                .addStringOption((o) =>
                    o.setName("word").setDescription("Word to remove").setRequired(true).setMaxLength(MAX_WORD_LENGTH),
                ),
        )
        .addSubcommand((s) =>
            s
                .setName("allow")
                .setDescription("Add or remove an allowed word (stops false positives)")
                .addStringOption((o) =>
                    o.setName("word").setDescription("Word to allow").setRequired(true).setMaxLength(MAX_WORD_LENGTH),
                ),
        )
        .addSubcommand((s) =>
            s
                .setName("ignore-channel")
                .setDescription("Add or remove a channel the filter skips")
                .addChannelOption((o) =>
                    o
                        .setName("channel")
                        .setDescription("Channel to skip")
                        .setRequired(true)
                        .addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement, ChannelType.GuildForum, ChannelType.GuildVoice),
                ),
        )
        .addSubcommand((s) =>
            s
                .setName("ignore-role")
                .setDescription("Add or remove a role the filter skips")
                .addRoleOption((o) => o.setName("role").setDescription("Role to skip").setRequired(true)),
        )
        .addSubcommand((s) =>
            s
                .setName("test")
                .setDescription("Check whether some text would be blocked (only you see the result)")
                .addStringOption((o) =>
                    o.setName("text").setDescription("Text to check").setRequired(true).setMaxLength(2000),
                ),
        )
        .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild),
    category: "moderation",

    async execute(interaction, config, client) {
        const deferSuccess = await InteractionHelper.safeDefer(interaction, { flags: MessageFlags.Ephemeral });
        if (!deferSuccess) {
            logger.warn(`Wordfilter interaction defer failed`, {
                userId: interaction.user.id,
                guildId: interaction.guildId,
                commandName: 'wordfilter'
            });
            return;
        }

        try {
            if (!interaction.member.permissions.has(PermissionFlagsBits.ManageGuild)) {
                return await InteractionHelper.safeEditReply(interaction, {
                    embeds: [errorEmbed("You need the `Manage Server` permission to configure the word filter.")],
                });
            }

            const guildId = interaction.guildId;
            const subcommand = interaction.options.getSubcommand();
            const filter = await getWordFilterConfig(client, guildId);
            const reply = (embed) => InteractionHelper.safeEditReply(interaction, { embeds: [embed] });

            switch (subcommand) {
                case "enable": {
                    await updateWordFilterConfig(client, guildId, { enabled: true });
                    return await reply(successEmbed(
                        `The word filter is now **on**. Action: **${filter.action}**.\n` +
                        "Members with Administrator are not filtered. Use `/wordfilter test` to try it.",
                    ));
                }

                case "disable": {
                    await updateWordFilterConfig(client, guildId, { enabled: false });
                    return await reply(successEmbed("The word filter is now **off**."));
                }

                case "action": {
                    const action = interaction.options.getString("type");
                    const timeoutMinutes = interaction.options.getInteger("timeout_minutes") ?? filter.timeoutMinutes;
                    await updateWordFilterConfig(client, guildId, { action, timeoutMinutes });
                    const extra = action === "timeout" ? ` (${timeoutMinutes} minute timeout)` : "";
                    return await reply(successEmbed(`Action set to **${action}**${extra}.`));
                }

                case "add": {
                    const word = normalizeEntry(interaction.options.getString("word"));
                    if (!word.replace(/\*/g, "")) {
                        return await reply(errorEmbed("Please enter a word."));
                    }
                    if (filter.customWords.includes(word)) {
                        return await reply(errorEmbed("That word is already blocked."));
                    }
                    if (filter.customWords.length >= MAX_CUSTOM_WORDS) {
                        return await reply(errorEmbed(`You can add up to ${MAX_CUSTOM_WORDS} custom words.`));
                    }
                    await updateWordFilterConfig(client, guildId, { customWords: [...filter.customWords, word] });
                    return await reply(successEmbed(`Added \`${maskWord(word)}\` to the blocked words.`));
                }

                case "remove": {
                    const word = normalizeEntry(interaction.options.getString("word"));
                    if (!filter.customWords.includes(word)) {
                        return await reply(errorEmbed(
                            "That word isn't in your custom list. Built-in words can't be removed, " +
                            "but you can use `/wordfilter allow` to stop a specific word being blocked.",
                        ));
                    }
                    await updateWordFilterConfig(client, guildId, {
                        customWords: filter.customWords.filter((w) => w !== word),
                    });
                    return await reply(successEmbed(`Removed \`${maskWord(word)}\` from the blocked words.`));
                }

                case "allow": {
                    const word = normalizeEntry(interaction.options.getString("word"));
                    const { list, added } = toggleInList(filter.allowedWords, word);
                    await updateWordFilterConfig(client, guildId, { allowedWords: list });
                    return await reply(successEmbed(
                        added ? `\`${word}\` will no longer be blocked.` : `\`${word}\` was removed from the allowed words.`,
                    ));
                }

                case "ignore-channel": {
                    const channel = interaction.options.getChannel("channel");
                    const { list, added } = toggleInList(filter.ignoredChannels, channel.id);
                    await updateWordFilterConfig(client, guildId, { ignoredChannels: list });
                    return await reply(successEmbed(
                        added ? `The filter will now skip ${channel}.` : `The filter will now check ${channel} again.`,
                    ));
                }

                case "ignore-role": {
                    const role = interaction.options.getRole("role");
                    const { list, added } = toggleInList(filter.ignoredRoles, role.id);
                    await updateWordFilterConfig(client, guildId, { ignoredRoles: list });
                    return await reply(successEmbed(
                        added ? `The filter will now skip members with ${role}.` : `The filter will now check members with ${role} again.`,
                    ));
                }

                case "test": {
                    const text = interaction.options.getString("text");
                    const found = findBlockedWords(text, getMatcher(guildId, filter));
                    return await reply(found.length > 0
                        ? errorEmbed(`This would be **blocked**. Matched: ${found.map((w) => `\`${maskWord(w)}\``).join(", ")}`)
                        : successEmbed("This would **not** be blocked."));
                }

                case "status":
                default: {
                    const channels = filter.ignoredChannels.map((id) => `<#${id}>`).join(", ") || "None";
                    const roles = filter.ignoredRoles.map((id) => `<@&${id}>`).join(", ") || "None";
                    const action = filter.action === "timeout"
                        ? `timeout (${filter.timeoutMinutes} min)`
                        : filter.action;

                    return await reply(createEmbed({
                        title: "🛡️ Word Filter",
                        description:
                            "Blocks severe slurs built in, plus any words you add. Catches look-alike " +
                            "letters from other alphabets, fancy fonts, leetspeak, spacing, and hidden characters.",
                        fields: [
                            { name: "Status", value: filter.enabled ? "✅ On" : "❌ Off", inline: true },
                            { name: "Action", value: action, inline: true },
                            { name: "Custom words", value: String(filter.customWords.length), inline: true },
                            { name: "Allowed words", value: filter.allowedWords.map((w) => `\`${w}\``).join(", ").substring(0, 1024) || "None", inline: false },
                            { name: "Ignored channels", value: channels.substring(0, 1024), inline: false },
                            { name: "Ignored roles", value: roles.substring(0, 1024), inline: false },
                        ],
                    }));
                }
            }
        } catch (error) {
            logger.error('Error in wordfilter command:', error);
            await handleInteractionError(interaction, error, { commandName: 'wordfilter', source: 'wordfilter_command' });
        }
    },
};
