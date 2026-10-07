// Word filter for FiveM - blocks slurs in chat and player names.
// Settings live in config.json. You should not need to edit this file.

// Built-in blocked words for the server word filter.
//
// This list is intentionally limited to the most severe slurs. General swearing
// is left to each server to add with `/wordfilter add`.
//
// Words are written in plain lowercase letters. The filter takes care of
// look-alike characters, leetspeak, repeated letters, spacing, and invisible
// characters, so variants do not need to be listed here.
//
// `token`     - matched as a whole word (plus common endings like -s, -z, -ed).
// `substring` - long, distinctive slurs that are also matched inside other
//               words ("xxniggerxx").
// `crossWord` - substring words that are also matched when split across
//               spaces ("nig ger"). Words that are a normal phrase when split
//               (like "wet back") are left out of this list.

const SEVERE_SUBSTRING_WORDS = [
  'nigger',
  'nigga',
  'niggah',
  'nigguh',
  'faggot',
  'wetback',
  'raghead',
  'towelhead',
  'jigaboo',
  'porchmonkey',
  'sandnigger'
];

const CROSS_WORD_WORDS = [
  'nigger',
  'nigga',
  'niggah',
  'nigguh',
  'faggot',
  'jigaboo',
  'sandnigger'
];

const SEVERE_TOKEN_WORDS = [
  'nig',
  'nigs',
  'niglet',
  'fag',
  'fagg',
  'faggit',
  'fagot',
  'dyke',
  'tranny',
  'trannie',
  'shemale',
  'kike',
  'kyke',
  'chink',
  'spic',
  'spick',
  'gook',
  'coon',
  'beaner',
  'paki',
  'retard',
  'golliwog',
  'gollywog',
  'zipperhead',
  'kneegrow'
];

// Innocent words that contain a blocked word. These are skipped before matching.
const DEFAULT_ALLOWED_WORDS = [
  'snigger',
  'sniggers',
  'sniggered',
  'sniggering',
  'niger',
  'nigeria',
  'nigerian',
  'nigerien',
  'niggard',
  'niggardly',
  'niggle',
  'niggling',
  'raccoon',
  'cocoon',
  'tycoon',
  'retardant',
  'spice',
  'spicy',
  // normal words that the look-alike letters (k/c, l/i, ph/f) and endings
  // (-s, -ed, -er) turn into a blocked word. Found by testing against a
  // 370,000-word English dictionary.
  'spices', 'spiced', 'spicer', 'spicers', 'spicing',
  'spike', 'spikes', 'spiked', 'spiker', 'spikers', 'spiky', 'spiking',
  'splice', 'splices', 'spliced', 'splicer', 'splicers', 'splicing',
  'phage', 'phages', 'packly', 'kickee', 'kylikes',
  'cilice', 'cilices', 'cylices',
  'niggards', 'niggarded', 'niggarding', 'niggardise', 'niggardised', 'niggardising',
  'niggardize', 'niggardized', 'niggardizing', 'niggardliness', 'niggardling', 'niggardness',
  'unniggard', 'unniggardly', 'sniggerer', 'sniggeringly'
];

// Detection engine for the server word filter.
//
// Messages are normalized before matching so the usual evasion tricks still hit:
//   - look-alike letters from other scripts (Cyrillic "нигга", Greek, Armenian)
//   - fancy fonts and styled text (𝐧𝐢𝐠, ｆａｇ, ⓝⓘⓖ, 🅽🅸🅶, ᴛʀᴀɴɴʏ, upside-down text)
//   - regional indicator emoji (🇳 🇮 🇬)
//   - accents and "zalgo" stacked marks (ñíggér)
//   - invisible / zero-width characters
//   - leetspeak (n1gg3r, f@g, $pic)
//   - repeated letters (niiiiggerrrr)
//   - separators and spacing (n.i.g.g.e.r, n i g g e r, nig ger, ||fag||)

const INVISIBLE_CHARS = /[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ]|\uDB40[\uDC00-\uDFFF]/g;

const CONFUSABLES = {
  // Cyrillic
  'а': 'a', 'б': 'b', 'в': 'b', 'г': 'r', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'x',
  'з': 'e', 'и': 'n', 'й': 'n', 'к': 'k', 'л': 'n', 'м': 'm', 'н': 'h', 'о': 'o',
  'п': 'n', 'р': 'p', 'с': 'c', 'т': 't', 'у': 'y', 'ф': 'f', 'х': 'x', 'ц': 'u',
  'ч': 'y', 'ш': 'w', 'щ': 'w', 'ъ': 'b', 'ы': 'bi', 'ь': 'b', 'э': 'e', 'ю': 'io',
  'я': 'r', 'є': 'e', 'ѕ': 's', 'і': 'i', 'ї': 'i', 'ј': 'j', 'һ': 'h', 'ԁ': 'd',
  'ԛ': 'q', 'ԝ': 'w', 'ґ': 'r', 'ү': 'y', 'ұ': 'y', 'қ': 'k', 'ң': 'h', 'ҝ': 'k',
  'ӏ': 'i', 'ɡ': 'g',
  // Greek
  'α': 'a', 'β': 'b', 'γ': 'y', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'n', 'θ': 'o',
  'ι': 'i', 'κ': 'k', 'λ': 'a', 'μ': 'u', 'ν': 'v', 'ξ': 'e', 'ο': 'o', 'π': 'n',
  'ρ': 'p', 'σ': 'o', 'ς': 's', 'τ': 't', 'υ': 'u', 'φ': 'f', 'χ': 'x', 'ψ': 'w',
  'ω': 'w',
  // Armenian
  'ա': 'w', 'գ': 'q', 'զ': 'q', 'հ': 'h', 'ո': 'n', 'ռ': 'n', 'ս': 'u', 'ց': 'g',
  'ւ': 'i', 'օ': 'o', 'ք': 'p',
  // Latin extras and small caps
  'ı': 'i', 'ȷ': 'j', 'ł': 'l', 'ø': 'o', 'đ': 'd', 'ð': 'd', 'ħ': 'h', 'ŧ': 't',
  'ß': 'ss', 'æ': 'ae', 'œ': 'oe', 'ŋ': 'n', 'ƒ': 'f', 'ɢ': 'g', 'ɪ': 'i', 'ɴ': 'n',
  'ʀ': 'r', 'ʏ': 'y', 'ʜ': 'h', 'ʟ': 'l', 'ᴀ': 'a', 'ʙ': 'b', 'ᴄ': 'c', 'ᴅ': 'd',
  'ᴇ': 'e', 'ꜰ': 'f', 'ᴊ': 'j', 'ᴋ': 'k', 'ᴍ': 'm', 'ᴏ': 'o', 'ᴘ': 'p', 'ǫ': 'q',
  'ꜱ': 's', 'ᴛ': 't', 'ᴜ': 'u', 'ᴠ': 'v', 'ᴡ': 'w', 'ᴢ': 'z',
  // Upside-down text
  'ɐ': 'a', 'ɔ': 'c', 'ǝ': 'e', 'ə': 'e', 'ɟ': 'f', 'ƃ': 'g', 'ɥ': 'h', 'ᴉ': 'i',
  'ɾ': 'r', 'ʞ': 'k', 'ɯ': 'm', 'ɹ': 'r', 'ʇ': 't', 'ʌ': 'v', 'ʍ': 'w', 'ʎ': 'y'
};

// Cyrillic read by sound rather than by shape, so "ниггер" is caught as well as
// look-alike spellings such as "nіggеr" with Cyrillic і and е.
const CYRILLIC_PHONETIC = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'zh',
  'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o',
  'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'ts',
  'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu',
  'я': 'ya', 'є': 'e', 'і': 'i', 'ї': 'i', 'ґ': 'g'
};
const HAS_CYRILLIC = /[\u0400-\u04FF]/;

// Upside-down text is also written backwards, so it gets checked reversed.
const UPSIDE_DOWN = /[ɐɔǝəɟƃɥᴉɾʞɯɹʇʌʍʎ]/;
// Plain letters that turn into each other when flipped ("n" upside down is "u").
const FLIP_PAIRS = { n: 'u', u: 'n', p: 'd', d: 'p', b: 'q', q: 'b' };

// Characters that stand in for letters. These are mapped in one variant of the
// text and dropped in another, so "f@g" and "fag!" both resolve to "fag".
const LEET = {
  '0': 'o', '1': 'i', '2': 'z', '3': 'e', '4': 'a', '5': 's', '6': 'g', '7': 't',
  '8': 'b', '9': 'g', '@': 'a', '$': 's', '!': 'i', '|': 'i', '+': 't', '(': 'c',
  '<': 'c', '[': 'c', '{': 'c', '€': 'e', '£': 'e', '¥': 'y', '©': 'c', '®': 'r',
  '¡': 'i', '¢': 'c', '∑': 'e', '#': 'h', '%': 'x', '&': 'e'
};
const LEET_DIGITS = new Set(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']);

// Leading/trailing characters on a word that are almost always punctuation.
const EDGE_PUNCTUATION = /^[!?.,;:'"()[\]{}<>*_~`|\-]+|[!?.,;:'"()[\]{}<>*_~`|\-]+$/g;

// Letters that are commonly swapped for each other when dodging filters.
const LETTER_CLASSES = {
  c: '[ck]',
  k: '[kc]',
  s: '[sz]',
  z: '[zs]',
  i: '[iyl]',
  l: '[li]',
  f: '(?:f|ph)'
};

const TOKEN_SUFFIX = '(?:s|z|es|ez|ed|er|ers|erz|ing|y|ie|ies|ish)?';

function mapChar(ch, phonetic) {
  const cp = ch.codePointAt(0);
  // Regional indicator symbols 🇦-🇿
  if (cp >= 0x1F1E6 && cp <= 0x1F1FF) return String.fromCharCode(97 + cp - 0x1F1E6);
  // Squared, negative circled, and negative squared Latin capitals 🄰 🅐 🅰
  if (cp >= 0x1F130 && cp <= 0x1F149) return String.fromCharCode(97 + cp - 0x1F130);
  if (cp >= 0x1F150 && cp <= 0x1F169) return String.fromCharCode(97 + cp - 0x1F150);
  if (cp >= 0x1F170 && cp <= 0x1F189) return String.fromCharCode(97 + cp - 0x1F170);
  if (phonetic && CYRILLIC_PHONETIC[ch] !== undefined) return CYRILLIC_PHONETIC[ch];
  return CONFUSABLES[ch] ?? ch;
}

/**
 * Folds styled, accented, and look-alike characters down to plain lowercase
 * text. Whitespace is preserved so words can still be told apart.
 */
function foldText(text, { phonetic = false } = {}) {
  if (typeof text !== 'string' || text.length === 0) return '';

  const withoutDiscordMarkup = text
    // Custom emoji <:name:id> - keep the name, it can contain a slur too
    .replace(/<a?:([A-Za-z0-9_~]+):\d+>/g, ' $1 ')
    // User, role, and channel mentions
    .replace(/<(?:@[!&]?|#)\d+>/g, ' ');

  const decomposed = withoutDiscordMarkup
    .replace(INVISIBLE_CHARS, '')
    .normalize('NFKD')
    // Accents and zalgo
    .replace(/\p{M}/gu, '')
    .toLowerCase();

  let folded = '';
  for (const ch of decomposed) {
    folded += mapChar(ch, phonetic);
  }
  return folded;
}

function toLetters(word, leetMode) {
  let source = word;
  if (leetMode === 'map') {
    source = source.replace(EDGE_PUNCTUATION, '');
  }

  let out = '';
  for (const ch of source) {
    const leet = LEET[ch];
    if (leet && (leetMode === 'map' || LEET_DIGITS.has(ch))) {
      out += leet;
    } else if (/\p{L}/u.test(ch)) {
      out += ch;
    }
  }
  return out;
}

function foldVariants(text) {
  const variants = [foldText(text)];
  if (HAS_CYRILLIC.test(text)) {
    variants.push(foldText(text, { phonetic: true }));
  }
  if (UPSIDE_DOWN.test(text)) {
    const unflipped = [...text.toLowerCase()].map((ch) => FLIP_PAIRS[ch] ?? ch).reverse().join('');
    variants.push(foldText(unflipped));
  }
  return variants;
}

/**
 * Splits a message into lists of letter-only words. Several readings are
 * returned: symbols like @ $ ! read as letters or dropped, Cyrillic read by
 * shape or by sound, and upside-down text read in reverse.
 */
function tokenize(text) {
  const readings = [];
  for (const folded of foldVariants(text)) {
    const words = folded.split(/\s+/).filter(Boolean);
    for (const mode of ['map', 'drop']) {
      readings.push(words.map((word) => toLetters(word, mode)).filter(Boolean));
    }
  }
  return readings;
}

function escapeRegex(ch) {
  return ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildPattern(word) {
  return [...word]
    .map((ch) => `(?:${LETTER_CLASSES[ch] ?? escapeRegex(ch)})+`)
    .join('');
}

function cleanWord(raw) {
  return toLetters(foldText(String(raw)).replace(/\s+/g, ''), 'drop');
}

/**
 * Builds a matcher from the built-in list plus a server's custom words.
 *
 * Custom words match as whole words. Put `*` at either end (e.g. `*badword*`)
 * to also match it inside other words.
 */
function createMatcher({ customWords = [], allowedWords = [], includeDefaults = true } = {}) {
  const substringWords = includeDefaults ? [...SEVERE_SUBSTRING_WORDS] : [];
  const crossWords = new Set(includeDefaults ? CROSS_WORD_WORDS : []);
  const tokenWords = includeDefaults ? [...SEVERE_TOKEN_WORDS] : [];

  for (const raw of customWords) {
    const isWildcard = /^\*|\*$/.test(String(raw).trim());
    const word = cleanWord(raw);
    if (!word) continue;
    (isWildcard ? substringWords : tokenWords).push(word);
    if (isWildcard) crossWords.add(word);
  }

  const allowed = new Set(
    [...(includeDefaults ? DEFAULT_ALLOWED_WORDS : []), ...allowedWords]
      .map(cleanWord)
      .filter(Boolean)
  );

  const rules = [
    ...[...new Set(substringWords)].map((word) => ({
      word,
      regex: new RegExp(buildPattern(word), 'u'),
      anywhere: true,
      crossWord: crossWords.has(word)
    })),
    ...[...new Set(tokenWords)].map((word) => ({
      word,
      regex: new RegExp(`^${buildPattern(word)}${TOKEN_SUFFIX}$`, 'u'),
      anywhere: false,
      crossWord: false
    }))
  ];

  return { rules, allowed };
}

function checkWord(candidate, matcher, hits, { crossWordOnly = false } = {}) {
  for (const rule of matcher.rules) {
    if (crossWordOnly && !rule.crossWord) continue;
    if (rule.regex.test(candidate)) hits.add(rule.word);
  }
}

/**
 * Returns the blocked words found in `text` (an empty array when it is clean).
 */
function findBlockedWords(text, matcher) {
  const hits = new Set();
  if (!text || !matcher || matcher.rules.length === 0) return [];

  for (const words of tokenize(text)) {
    const kept = words.filter((word) => !matcher.allowed.has(word));

    // 1. Each word on its own: "n1gg3r", "f.a.g", "ｆａｇｓ"
    for (const word of kept) {
      checkWord(word, matcher, hits);
    }

    // 2. Runs of short pieces glued back together: "n i g g e r", "fa g"
    let run = [];
    const flushRun = () => {
      if (run.length >= 2) checkWord(run.join(''), matcher, hits);
      run = [];
    };
    for (const word of kept) {
      if (word.length <= 2) {
        run.push(word);
      } else {
        flushRun();
      }
    }
    flushRun();

    // 3. Whole message squashed together, long distinctive slurs only: "nig ger"
    checkWord(kept.join(''), matcher, hits, { crossWordOnly: true });
  }

  // Report "nigger" rather than both "nigger" and "nig"
  const found = [...hits];
  return found.filter((word) => !found.some((other) => other !== word && other.includes(word)));
}

/**
 * Masks a word for logs, e.g. "example" -> "e*****e".
 */
function maskWord(word) {
  if (!word || word.length <= 2) return '*'.repeat(word?.length || 0);
  return `${word[0]}${'*'.repeat(word.length - 2)}${word[word.length - 1]}`;
}

// ---------------------------------------------------------------------------
// FiveM hooks
// ---------------------------------------------------------------------------

const RESOURCE_NAME = GetCurrentResourceName();
const CONFIG_DEFAULTS = {
  blockChat: true,
  checkPlayerNames: true,
  kickAfterStrikes: 3,
  warningMessage: 'Your message was blocked because it contained a blocked word.',
  kickMessage: 'You were kicked for repeatedly using blocked words.',
  banOnKick: true,
  banDurationHours: 0,
  appealLink: '',
  banMessage: 'You are banned for using blocked words. Ban ID: {banId}. Open a ticket to appeal: {appealLink}',
  nameKickMessage: 'Your name contains a blocked word. Please change it and reconnect.',
  bypassAce: 'wordfilter.bypass',
  discordWebhook: '',
  customWords: [],
  allowedWords: []
};

function loadConfig() {
  const raw = LoadResourceFile(RESOURCE_NAME, 'config.json');
  if (!raw) {
    console.log(`^3[${RESOURCE_NAME}] config.json not found, using defaults^7`);
    return { ...CONFIG_DEFAULTS };
  }
  try {
    return { ...CONFIG_DEFAULTS, ...JSON.parse(raw) };
  } catch (error) {
    console.log(`^1[${RESOURCE_NAME}] config.json is not valid JSON (${error.message}), using defaults^7`);
    return { ...CONFIG_DEFAULTS };
  }
}

// ---------------------------------------------------------------------------
// Bans (saved to bans.json so they survive restarts)
// ---------------------------------------------------------------------------

const BANS_FILE = 'bans.json';

// GetPlayerIdentifiers() only exists in Lua, so read them one by one
function getIdentifiers(src) {
  const player = String(src);
  const count = GetNumPlayerIdentifiers(player) || 0;
  const ids = [];
  for (let i = 0; i < count; i++) {
    const id = GetPlayerIdentifier(player, i);
    if (id) ids.push(id);
  }
  return ids;
}

function loadBans() {
  const raw = LoadResourceFile(RESOURCE_NAME, BANS_FILE);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.log(`^1[${RESOURCE_NAME}] bans.json is not valid JSON (${error.message}), starting with no bans^7`);
    return [];
  }
}

function saveBans() {
  SaveResourceFile(RESOURCE_NAME, BANS_FILE, JSON.stringify(bans, null, 2), -1);
}

function newBanId() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let id;
  do {
    id = 'WF-' + Array.from({ length: 5 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
  } while (bans.some((ban) => ban.banId === id));
  return id;
}

// IP addresses are left out so people sharing a connection are not banned too
function banIdentifiers(src) {
  return getIdentifiers(src).filter((id) => !id.startsWith('ip:'));
}

function removeExpiredBans() {
  const now = Date.now();
  const before = bans.length;
  bans = bans.filter((ban) => !ban.expiresAt || ban.expiresAt > now);
  if (bans.length !== before) saveBans();
}

function findBan(identifiers) {
  removeExpiredBans();
  return bans.find((ban) => ban.identifiers.some((id) => identifiers.includes(id)));
}

function banMessageFor(ban) {
  let message = config.banMessage
    .replace(/\{banId\}/g, ban.banId)
    .replace(/\{appealLink\}/g, config.appealLink || 'ask staff');
  if (ban.expiresAt) {
    message += ` (expires ${new Date(ban.expiresAt).toUTCString()})`;
  }
  return message;
}

function banPlayer(src, name, matched) {
  const hours = Number(config.banDurationHours) || 0;
  const ban = {
    banId: newBanId(),
    name,
    identifiers: banIdentifiers(src),
    reason: 'Repeatedly used blocked words',
    matched,
    bannedAt: Date.now(),
    expiresAt: hours > 0 ? Date.now() + hours * 60 * 60 * 1000 : null
  };
  bans.push(ban);
  saveBans();
  return ban;
}

let bans = loadBans();
let config = loadConfig();
let matcher = createMatcher({ customWords: config.customWords, allowedWords: config.allowedWords });
const strikes = new Map();

function playerKey(src) {
  const ids = getIdentifiers(src);
  return ids.find((id) => id.startsWith('license:')) || ids[0] || `src:${src}`;
}

// Admins who turned on /wordfilter_testmode: their messages are filtered even
// if they have the bypass permission, but they never get strikes or bans.
const testMode = new Set();

function canBypass(src) {
  if (testMode.has(Number(src))) return false;
  return Boolean(config.bypassAce) && IsPlayerAceAllowed(String(src), config.bypassAce);
}

function tellPlayer(src, message, color = [80, 200, 120]) {
  TriggerClientEvent('chat:addMessage', src, { color, args: ['Word Filter', message] });
}

// console -> server log, player -> their chat
function replyTo(src, message, color) {
  if (Number(src) === 0) console.log(`[${RESOURCE_NAME}] ${message}`);
  else tellPlayer(src, message, color);
}

function sendToDiscord(title, description) {
  if (!config.discordWebhook) return;
  const body = JSON.stringify({
    username: 'Word Filter',
    embeds: [{ title, description: description.substring(0, 4000), color: 15158332, timestamp: new Date().toISOString() }]
  });
  // PerformHttpRequest() only exists in Lua, so post with Node instead
  try {
    const url = new URL(config.discordWebhook);
    const request = require('https').request({
      hostname: url.hostname,
      path: url.pathname + url.search,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
    }, (response) => {
      if (response.statusCode >= 400) {
        console.log(`^3[${RESOURCE_NAME}] Discord webhook returned ${response.statusCode}^7`);
      }
      response.resume();
    });
    request.on('error', (error) => console.log(`^3[${RESOURCE_NAME}] Discord webhook failed: ${error.message}^7`));
    request.end(body);
  } catch (error) {
    console.log(`^3[${RESOURCE_NAME}] Discord webhook URL is invalid: ${error.message}^7`);
  }
}

function logHit(kind, src, name, text, found) {
  const masked = found.map(maskWord).join(', ');
  console.log(`^1[${RESOURCE_NAME}] Blocked ${kind} from ${name} (id ${src}): ${masked}^7`);
  sendToDiscord(
    `Blocked ${kind}`,
    `**Player:** ${name} (id ${src})\n**Identifier:** ${playerKey(src)}\n**Matched:** ${masked}\n**Text:** ||${String(text).replace(/\|/g, '').substring(0, 500)}||`
  );
}

// Checks a player's message and punishes them if it has a blocked word.
// Returns true when the message should be blocked.
function checkPlayerMessage(src, name, message, kind) {
  src = Number(src);
  if (!src || !message) return false;
  if (canBypass(src)) {
    if (debugChat) console.log(`[${RESOURCE_NAME}] debug: id ${src} has the "${config.bypassAce}" permission - not filtered`);
    return false;
  }

  const found = findBlockedWords(String(message), matcher);
  if (found.length === 0) return false;

  if (testMode.has(src)) {
    tellPlayer(src, `TEST MODE: this would be blocked (${found.map(maskWord).join(', ')}). No strike given.`, [255, 180, 60]);
    return true;
  }

  logHit(kind, src, name, message, found);

  tellPlayer(src, config.warningMessage, [255, 80, 80]);

  if (config.kickAfterStrikes > 0) {
    const key = playerKey(src);
    const count = (strikes.get(key) || 0) + 1;
    strikes.set(key, count);
    if (count >= config.kickAfterStrikes) {
      strikes.delete(key);
      const masked = found.map(maskWord).join(', ');
      if (config.banOnKick) {
        const ban = banPlayer(src, name, masked);
        DropPlayer(String(src), banMessageFor(ban));
        console.log(`^1[${RESOURCE_NAME}] Banned ${name} (${ban.banId}) after ${count} strikes^7`);
        sendToDiscord(
          'Player banned',
          `**Player:** ${name} (id ${src})\n**Ban ID:** ${ban.banId}\n**Strikes:** ${count}\n**Last matched:** ${masked}\n` +
          `**Length:** ${ban.expiresAt ? `${config.banDurationHours} hours` : 'until appealed'}\n` +
          `**Identifiers:** ${ban.identifiers.join(', ')}\n\nUnban with: \`wordfilter_unban ${ban.banId}\``
        );
      } else {
        DropPlayer(String(src), config.kickMessage);
        sendToDiscord('Player kicked', `**Player:** ${name} (id ${src}) reached ${count} strikes.`);
      }
    }
  }

  return true;
}

// Plain chat messages from the default cfx "chat" resource
// Chat is caught two ways, so it works with the standard chat and its forks:
//  1. the chat resource's message hook (runs before the message is sent)
//  2. the classic "chatMessage" event
// The same message seen by both only counts once.
let debugChat = false;
const recent = new Map();   // src -> { text, at, blocked }

function handleChat(src, name, message, via) {
  src = Number(src);
  if (debugChat) console.log(`[${RESOURCE_NAME}] debug: chat from ${name} (id ${src}) via ${via}: ${String(message).length} chars`);
  if (!config.blockChat || !message) return false;
  const last = recent.get(src);
  if (last && last.text === message && Date.now() - last.at < 2000) return last.blocked;
  const blocked = checkPlayerMessage(src, name, message, 'chat message');
  recent.set(src, { text: message, at: Date.now(), blocked });
  return blocked;
}

on('chatMessage', (src, name, message) => {
  if (handleChat(src, name, message, 'chatMessage event')) CancelEvent();
});

let hookedChat = null;
function hookChatResource() {
  for (const res of ['chat', ...(config.chatResources || [])]) {
    if (GetResourceState(res) !== 'started') continue;
    try {
      exports[res].registerMessageHook((src, outMessage, hookRef) => {
        const args = (outMessage && outMessage.args) || [];
        const message = args[args.length - 1];
        if (typeof message !== 'string') return;
        const name = GetPlayerName(String(src)) || `id ${src}`;
        if (handleChat(src, name, message, `${res} message hook`)) hookRef.cancel();
      });
      hookedChat = res;
      return true;
    } catch (error) {
      console.log(`^3[${RESOURCE_NAME}] Couldn't hook "${res}" (${error.message}) - using the chatMessage event only.^7`);
    }
  }
  return false;
}

on('onServerResourceStart', (res) => {
  if (!hookedChat && (res === 'chat' || (config.chatResources || []).includes(res))) hookChatResource();
});
on('playerDropped', () => { recent.delete(Number(global.source)); });

// For other scripts' chat commands (/ooc, /me, /twt ...). From Lua:
//   if exports['wordfilter']:checkMessage(source, message) then return end
exports('checkMessage', (src, message) => {
  try {
    if (Array.isArray(message)) message = message.join(' ');
    return checkPlayerMessage(src, GetPlayerName(String(src)) || `id ${src}`, message, 'command message');
  } catch (error) {
    console.log(`^1[${RESOURCE_NAME}] checkMessage failed: ${error.message}^7`);
    return false;
  }
});

// Player names when they join
on('playerConnecting', (name, setKickReason, deferrals) => {
  const src = global.source;

  const ban = findBan(banIdentifiers(src));
  if (ban) {
    console.log(`^3[${RESOURCE_NAME}] Blocked banned player ${name} (${ban.banId}) from joining^7`);
    setKickReason(banMessageFor(ban));
    CancelEvent();
    return;
  }

  if (!config.checkPlayerNames || canBypass(src)) return;

  const found = findBlockedWords(name, matcher);
  if (found.length === 0) return;

  logHit('player name', src, name, name, found);
  setKickReason(config.nameKickMessage);
  CancelEvent();
});

// wordfilter_test <text>: says if the text would be blocked. Console, or in game
// for anyone with command.wordfilter_test (e.g. add_ace group.admin command allow).
RegisterCommand('wordfilter_test', (src, args) => {
  const text = args.join(' ');
  if (!text) return replyTo(src, 'Usage: wordfilter_test <text to check>');
  const found = findBlockedWords(text, matcher);
  if (found.length > 0) replyTo(src, `BLOCKED: ${found.map(maskWord).join(', ')}`, [255, 80, 80]);
  else replyTo(src, 'Not blocked');
}, true);

// /wordfilter_testmode: test the real chat on yourself. Your messages are
// filtered like a normal player's (even if you have the bypass), but you never
// get a strike or a ban. Run it again to turn it off.
RegisterCommand('wordfilter_testmode', (src) => {
  if (Number(src) === 0) return console.log(`[${RESOURCE_NAME}] Run /wordfilter_testmode in game.`);
  src = Number(src);
  if (testMode.has(src)) {
    testMode.delete(src);
    tellPlayer(src, 'Test mode OFF.');
  } else {
    testMode.add(src);
    tellPlayer(src, 'Test mode ON: type in chat (and /ooc etc.) - blocked messages are stopped, but you get no strikes. Run the command again to turn it off.', [255, 180, 60]);
  }
}, true);

on('playerDropped', () => { testMode.delete(Number(global.source)); });

// wordfilter_selftest: runs the built-in words through common disguises
RegisterCommand('wordfilter_selftest', (src) => {
  const words = [...new Set([...SEVERE_SUBSTRING_WORDS, ...SEVERE_TOKEN_WORDS])];
  const LEET_OUT = { a: '4', e: '3', i: '1', o: '0', s: '5' };
  const disguises = [
    (w) => w, (w) => w.toUpperCase(), (w) => `you are a ${w}!!`, (w) => `${w}s`,
    (w) => [...w].map((c) => LEET_OUT[c] || c).join(''), (w) => [...w].join(' '), (w) => [...w].join('.'),
    (w) => [...w].join('\u200B'), (w) => [...w].map((c) => String.fromCodePoint(c.codePointAt(0) + 0xFEE0)).join('')
  ];
  let caught = 0;
  let total = 0;
  for (const w of words) for (const d of disguises) { total++; if (findBlockedWords(d(w), matcher).length) caught++; }
  const normal = ['hello there', 'the spikes are sharp', 'nice spicy taco', 'he is from nigeria', 'a raccoon', 'good game'];
  const wrongly = normal.filter((t) => findBlockedWords(t, matcher).length);
  replyTo(src, `Self-test: caught ${caught}/${total} disguised slurs, ${wrongly.length} of ${normal.length} normal sentences wrongly blocked.`,
    caught === total && wrongly.length === 0 ? [80, 200, 120] : [255, 180, 60]);
}, true);

// Unban by ban ID or identifier. Works in the console, or in game for anyone
// with the command.wordfilter_unban permission.
RegisterCommand('wordfilter_unban', (src, args) => {
  const reply = (message) => {
    if (src === 0) {
      console.log(`[${RESOURCE_NAME}] ${message}`);
    } else {
      TriggerClientEvent('chat:addMessage', src, { color: [80, 200, 120], args: ['Word Filter', message] });
    }
  };

  const target = (args[0] || '').trim();
  if (!target) return reply('Usage: wordfilter_unban <ban ID or identifier>');

  const ban = bans.find((b) => b.banId.toUpperCase() === target.toUpperCase() || b.identifiers.includes(target));
  if (!ban) return reply(`No ban found for ${target}`);

  bans = bans.filter((b) => b !== ban);
  saveBans();
  const by = src === 0 ? 'console' : `${GetPlayerName(String(src))} (id ${src})`;
  reply(`Unbanned ${ban.name} (${ban.banId})`);
  sendToDiscord('Player unbanned', `**Player:** ${ban.name}\n**Ban ID:** ${ban.banId}\n**Unbanned by:** ${by}`);
}, true);

RegisterCommand('wordfilter_bans', (src) => {
  if (src !== 0) return;
  removeExpiredBans();
  if (bans.length === 0) return console.log(`[${RESOURCE_NAME}] No active bans`);
  for (const ban of bans) {
    const until = ban.expiresAt ? new Date(ban.expiresAt).toUTCString() : 'until appealed';
    console.log(`[${RESOURCE_NAME}] ${ban.banId}  ${ban.name}  banned ${new Date(ban.bannedAt).toUTCString()}  (${until})`);
  }
}, true);

RegisterCommand('wordfilter_reload', (src) => {
  if (src !== 0) return;
  config = loadConfig();
  matcher = createMatcher({ customWords: config.customWords, allowedWords: config.allowedWords });
  console.log(`^2[${RESOURCE_NAME}] Config reloaded^7`);
}, true);

console.log(`^2[${RESOURCE_NAME}] Word filter loaded (${matcher.rules.length} rules, ${bans.length} bans)^7`);
// Start-up report: what the filter is hooked into and who can skip it
setTimeout(() => {
  if (!hookedChat) hookChatResource();
  console.log(`[${RESOURCE_NAME}] Chat: ${hookedChat ? `hooked into "${hookedChat}"` : 'no chat resource hook - listening for the chatMessage event only'}.` +
    ` Filtering chat: ${config.blockChat ? 'ON' : 'OFF (blockChat is false in config.json)'}.`);
  console.log(`[${RESOURCE_NAME}] Bypass: ${config.bypassAce ? `players with the "${config.bypassAce}" permission are NOT filtered` : 'nobody (admins are filtered too)'}.`);
  console.log(`[${RESOURCE_NAME}] Not working? Type  wordfilter_debug  here, then send a chat message in game.`);
}, 3000);

// wordfilter_debug: log every chat message the filter receives (no message text)
RegisterCommand('wordfilter_debug', (src) => {
  debugChat = !debugChat;
  replyTo(src, `Debug ${debugChat ? 'ON - every chat message the filter sees is logged in the server console' : 'OFF'}.`);
  if (debugChat) {
    replyTo(src, `Chat hook: ${hookedChat || 'none'}. Bypass permission: ${config.bypassAce || 'none'}.`);
  }
}, true);
