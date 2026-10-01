import {
  SEVERE_SUBSTRING_WORDS,
  SEVERE_TOKEN_WORDS,
  CROSS_WORD_WORDS,
  DEFAULT_ALLOWED_WORDS
} from '../config/wordFilter/wordlist.js';

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
export function foldText(text, { phonetic = false } = {}) {
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
export function tokenize(text) {
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
export function createMatcher({ customWords = [], allowedWords = [], includeDefaults = true } = {}) {
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
export function findBlockedWords(text, matcher) {
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
export function maskWord(word) {
  if (!word || word.length <= 2) return '*'.repeat(word?.length || 0);
  return `${word[0]}${'*'.repeat(word.length - 2)}${word[word.length - 1]}`;
}
