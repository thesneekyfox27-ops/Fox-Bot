import { PermissionFlagsBits } from 'discord.js';
import { getGuildConfig, updateGuildConfig } from './guildConfig.js';
import { WarningService } from './warningService.js';
import { logModerationAction } from '../utils/moderation.js';
import { logger } from '../utils/logger.js';
import { createMatcher, findBlockedWords, maskWord } from '../utils/profanityFilter.js';

export const WORD_FILTER_ACTIONS = ['delete', 'warn', 'timeout'];

export const WORD_FILTER_DEFAULTS = {
  enabled: false,
  action: 'delete',
  timeoutMinutes: 10,
  customWords: [],
  allowedWords: [],
  ignoredChannels: [],
  ignoredRoles: []
};

const NOTICE_DELETE_AFTER_MS = 6000;
const MAX_LOGGED_CONTENT_LENGTH = 300;

const matcherCache = new Map();

export async function getWordFilterConfig(client, guildId) {
  const guildConfig = await getGuildConfig(client, guildId);
  return { ...WORD_FILTER_DEFAULTS, ...(guildConfig.wordFilter || {}) };
}

export async function updateWordFilterConfig(client, guildId, updates) {
  const current = await getWordFilterConfig(client, guildId);
  const wordFilter = { ...current, ...updates };
  await updateGuildConfig(client, guildId, { wordFilter });
  matcherCache.delete(guildId);
  return wordFilter;
}

export function getMatcher(guildId, config) {
  const key = JSON.stringify([config.customWords, config.allowedWords]);
  const cached = matcherCache.get(guildId);
  if (cached?.key === key) return cached.matcher;

  const matcher = createMatcher({
    customWords: config.customWords,
    allowedWords: config.allowedWords
  });
  matcherCache.set(guildId, { key, matcher });
  return matcher;
}

function isExempt(message, member, config) {
  const channelIds = [message.channel.id, message.channel.parentId].filter(Boolean);
  if (channelIds.some((id) => config.ignoredChannels.includes(id))) return true;

  if (!member) return false;
  if (member.permissions?.has(PermissionFlagsBits.Administrator)) return true;
  return member.roles.cache.some((role) => config.ignoredRoles.includes(role.id));
}

function truncate(text, length) {
  return text.length > length ? `${text.substring(0, length - 3)}...` : text;
}

/**
 * Checks a message against the server's word filter and takes action on a hit.
 * Returns true when the message was blocked.
 */
export async function handleFilteredMessage(message, client) {
  try {
    if (!message.guild || message.author?.bot || !message.content) return false;

    const config = await getWordFilterConfig(client, message.guild.id);
    if (!config.enabled) return false;

    const member = message.member
      || await message.guild.members.fetch(message.author.id).catch(() => null);
    if (isExempt(message, member, config)) return false;

    const found = findBlockedWords(message.content, getMatcher(message.guild.id, config));
    if (found.length === 0) return false;

    await message.delete().catch((error) => {
      logger.warn(`Word filter could not delete message ${message.id} in guild ${message.guild.id}: ${error.message}`);
    });

    const masked = found.map(maskWord).join(', ');
    const reason = `Word filter: blocked word (${masked})`;
    let outcome = 'Message deleted';

    if (config.action === 'warn' || config.action === 'timeout') {
      await WarningService.addWarning({
        guildId: message.guild.id,
        userId: message.author.id,
        moderatorId: client.user.id,
        reason
      }).catch((error) => logger.error('Word filter failed to add warning:', error));
      outcome = 'Message deleted + warning';
    }

    if (config.action === 'timeout' && member?.moderatable) {
      const minutes = Math.max(1, Math.min(config.timeoutMinutes || 10, 40320));
      await member.timeout(minutes * 60 * 1000, reason)
        .then(() => { outcome = `Message deleted + warning + ${minutes}m timeout`; })
        .catch((error) => logger.warn(`Word filter could not time out ${message.author.id}: ${error.message}`));
    }

    const notice = await message.channel.send({
      content: `${message.author}, your message was removed because it contained a blocked word.`,
      allowedMentions: { users: [message.author.id] }
    }).catch(() => null);
    if (notice) {
      setTimeout(() => notice.delete().catch(() => {}), NOTICE_DELETE_AFTER_MS);
    }

    await logModerationAction({
      client,
      guild: message.guild,
      event: {
        action: 'Message Filtered',
        target: `${message.author.tag} (${message.author.id})`,
        executor: `${client.user.tag} (${client.user.id})`,
        reason,
        metadata: {
          userId: message.author.id,
          moderatorId: client.user.id,
          channel: `${message.channel}`,
          outcome,
          content: `||${truncate(message.content.replace(/\|/g, ''), MAX_LOGGED_CONTENT_LENGTH)}||`
        }
      }
    }).catch((error) => logger.error('Word filter failed to log action:', error));

    return true;
  } catch (error) {
    logger.error('Error in word filter:', error);
    return false;
  }
}
