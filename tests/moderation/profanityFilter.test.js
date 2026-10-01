import test from 'node:test';
import assert from 'node:assert/strict';

import { createMatcher, findBlockedWords, maskWord } from '../../src/utils/profanityFilter.js';

const matcher = createMatcher();

function assertBlocked(text) {
  assert.ok(findBlockedWords(text, matcher).length > 0, `expected "${text}" to be blocked`);
}

function assertClean(text, m = matcher) {
  assert.deepEqual(findBlockedWords(text, m), [], `expected "${text}" to be clean`);
}

test('catches slurs written in plain text', () => {
  assertBlocked('you are a nigger');
  assertBlocked('FAGGOT');
  assertBlocked('what a retard');
});

test('catches leetspeak, repeated letters, and separators', () => {
  for (const text of ['n1gg3r', 'f@g!', '$pic', 'niiiiggggerrrr', 'n.i.g.g.e.r', 'n i g g e r', 'nig ger', '||fag||', 'phaggot']) {
    assertBlocked(text);
  }
});

test('catches look-alike letters from other scripts and styled fonts', () => {
  for (const text of [
    'ниггер',            // Cyrillic, read by sound
    'nіggеr',            // Cyrillic і and е mixed into Latin
    '𝐧𝐢𝐠𝐠𝐚',             // mathematical bold
    'ｆａｇｇｏｔ',          // fullwidth
    'ⓕⓐⓖ',               // circled
    '🅵🅰🅶',              // negative squared
    '🇳 🇮 🇬 🇬 🇦',        // regional indicators
    'ᴛʀᴀɴɴʏ',            // small caps
    'ñíggér',            // accents
    'ɹǝƃƃᴉu'             // upside down
  ]) {
    assertBlocked(text);
  }
});

test('catches hidden characters and emoji names', () => {
  assertBlocked('n​i‍gger');
  assertBlocked('n̶i̶g̶g̶e̶r');
  assertBlocked('<:nigger:123456789>');
});

test('does not flag innocent words that contain a blocked word', () => {
  for (const text of [
    'hello there', 'I snigger at that', 'Niger is a country in Africa', 'a niggardly sum',
    'look at that raccoon', 'my back is wet back from the rain', 'Scunthorpe United',
    'that dish needs spice', 'a tycoon in a cocoon', 'go to a gig', 'my knee grows'
  ]) {
    assertClean(text);
  }
});

test('supports custom blocked words and wildcards', () => {
  const custom = createMatcher({ customWords: ['badword', '*worse*'] });
  assert.deepEqual(findBlockedWords('b@dw0rd', custom), ['badword']);
  assert.deepEqual(findBlockedWords('superworsething', custom), ['worse']);
  assertClean('notbadword and badwordsmith', createMatcher({ includeDefaults: false, customWords: ['badword'] }));
});

test('allowed words override matches', () => {
  const custom = createMatcher({ allowedWords: ['retard'] });
  assertClean('fire retard', custom);
});

test('masks words for logs', () => {
  assert.equal(maskWord('example'), 'e*****e');
  assert.equal(maskWord('ab'), '**');
});
