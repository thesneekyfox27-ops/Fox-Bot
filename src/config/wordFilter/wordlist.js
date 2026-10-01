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

export const SEVERE_SUBSTRING_WORDS = [
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

export const CROSS_WORD_WORDS = [
  'nigger',
  'nigga',
  'niggah',
  'nigguh',
  'faggot',
  'jigaboo',
  'sandnigger'
];

export const SEVERE_TOKEN_WORDS = [
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
export const DEFAULT_ALLOWED_WORDS = [
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
  'spicy'
];
