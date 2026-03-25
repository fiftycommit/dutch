import { describe, it } from 'node:test';
import assert from 'node:assert';
import { ValidationService } from '../services/ValidationService';

describe('ValidationService', () => {
  describe('sanitizePlayerName', () => {
    it('returns "Joueur" for non-string input', () => {
      assert.strictEqual(ValidationService.sanitizePlayerName(42), 'Joueur');
      assert.strictEqual(ValidationService.sanitizePlayerName(null), 'Joueur');
      assert.strictEqual(ValidationService.sanitizePlayerName(undefined), 'Joueur');
    });

    it('strips HTML tags using bounded regex', () => {
      assert.strictEqual(ValidationService.sanitizePlayerName('<b>Alice</b>'), 'Alice');
      assert.strictEqual(ValidationService.sanitizePlayerName('<script>alert(1)</script>'), 'alert(1)');
    });

    it('trims and truncates to 24 chars', () => {
      assert.strictEqual(ValidationService.sanitizePlayerName('  Alice  '), 'Alice');
      const long = 'A'.repeat(30);
      assert.strictEqual(ValidationService.sanitizePlayerName(long).length, 24);
    });

    it('returns "Joueur" for empty string after sanitization', () => {
      assert.strictEqual(ValidationService.sanitizePlayerName('<b></b>'), 'Joueur');
      assert.strictEqual(ValidationService.sanitizePlayerName('   '), 'Joueur');
    });
  });

  describe('sanitizeChatMessage', () => {
    it('returns empty string for non-string input', () => {
      assert.strictEqual(ValidationService.sanitizeChatMessage(123), '');
      assert.strictEqual(ValidationService.sanitizeChatMessage(null), '');
    });

    it('strips HTML tags using bounded regex', () => {
      assert.strictEqual(ValidationService.sanitizeChatMessage('<em>hello</em>'), 'hello');
    });

    it('trims and truncates to 200 chars', () => {
      const long = 'x'.repeat(250);
      assert.strictEqual(ValidationService.sanitizeChatMessage(long).length, 200);
    });

    it('returns empty string for whitespace-only after strip', () => {
      assert.strictEqual(ValidationService.sanitizeChatMessage('   '), '');
    });
  });

  describe('sanitizeDisplayName', () => {
    it('returns "Joueur" for non-string input', () => {
      assert.strictEqual(ValidationService.sanitizeDisplayName(false), 'Joueur');
    });

    it('strips HTML tags using bounded regex', () => {
      assert.strictEqual(ValidationService.sanitizeDisplayName('<i>Max</i>'), 'Max');
    });

    it('returns "Joueur" when result is empty', () => {
      assert.strictEqual(ValidationService.sanitizeDisplayName('<div></div>'), 'Joueur');
    });

    it('truncates to 24 chars', () => {
      assert.strictEqual(ValidationService.sanitizeDisplayName('B'.repeat(30)).length, 24);
    });
  });

  describe('isValidEmail', () => {
    it('accepts a standard email', () => {
      assert.strictEqual(ValidationService.isValidEmail('user@example.com'), true);
    });

    it('rejects non-string', () => {
      assert.strictEqual(ValidationService.isValidEmail(42), false);
    });

    it('rejects email with local part exceeding 64 chars', () => {
      const longLocal = 'a'.repeat(65) + '@example.com';
      assert.strictEqual(ValidationService.isValidEmail(longLocal), false);
    });

    it('rejects email with domain exceeding 253 chars', () => {
      const longDomain = 'user@' + 'a'.repeat(254) + '.com';
      assert.strictEqual(ValidationService.isValidEmail(longDomain), false);
    });

    it('rejects email with TLD exceeding 63 chars', () => {
      const longTld = 'user@example.' + 'a'.repeat(64);
      assert.strictEqual(ValidationService.isValidEmail(longTld), false);
    });

    it('accepts email with max valid lengths', () => {
      const email = 'a'.repeat(64) + '@' + 'b'.repeat(253) + '.' + 'c'.repeat(63);
      assert.strictEqual(ValidationService.isValidEmail(email), true);
    });

    it('trims whitespace before validation', () => {
      assert.strictEqual(ValidationService.isValidEmail('  user@example.com  '), true);
    });
  });

  describe('isValidRoomCode', () => {
    it('accepts valid codes', () => {
      assert.strictEqual(ValidationService.isValidRoomCode('ABCD'), true);
      assert.strictEqual(ValidationService.isValidRoomCode('AB12CD78'), true);
    });

    it('rejects non-string', () => {
      assert.strictEqual(ValidationService.isValidRoomCode(123), false);
    });

    it('rejects too short or too long', () => {
      assert.strictEqual(ValidationService.isValidRoomCode('ABC'), false);
      assert.strictEqual(ValidationService.isValidRoomCode('ABCDEFGHI'), false);
    });

    it('rejects lowercase', () => {
      assert.strictEqual(ValidationService.isValidRoomCode('abcd'), false);
    });
  });

  describe('isValidUsername', () => {
    it('accepts valid usernames', () => {
      assert.strictEqual(ValidationService.isValidUsername('alice_01'), true);
      assert.strictEqual(ValidationService.isValidUsername('bob.test-user'), true);
    });

    it('rejects non-string', () => {
      assert.strictEqual(ValidationService.isValidUsername(null), false);
    });

    it('rejects too short or too long', () => {
      assert.strictEqual(ValidationService.isValidUsername('ab'), false);
      assert.strictEqual(ValidationService.isValidUsername('a'.repeat(21)), false);
    });

    it('rejects special characters', () => {
      assert.strictEqual(ValidationService.isValidUsername('user@name'), false);
    });
  });

  describe('isValidPassword', () => {
    it('accepts valid passwords', () => {
      assert.strictEqual(ValidationService.isValidPassword('123456'), true);
      assert.strictEqual(ValidationService.isValidPassword('a'.repeat(100)), true);
    });

    it('rejects non-string', () => {
      assert.strictEqual(ValidationService.isValidPassword(12345), false);
    });

    it('rejects too short or too long', () => {
      assert.strictEqual(ValidationService.isValidPassword('12345'), false);
      assert.strictEqual(ValidationService.isValidPassword('a'.repeat(101)), false);
    });
  });

  describe('isValidDisplayName', () => {
    it('accepts valid display names', () => {
      assert.strictEqual(ValidationService.isValidDisplayName('Alice'), true);
      assert.strictEqual(ValidationService.isValidDisplayName('A'), true);
    });

    it('rejects non-string', () => {
      assert.strictEqual(ValidationService.isValidDisplayName(undefined), false);
    });

    it('rejects empty or whitespace only', () => {
      assert.strictEqual(ValidationService.isValidDisplayName(''), false);
      assert.strictEqual(ValidationService.isValidDisplayName('   '), false);
    });

    it('rejects names longer than 24 chars after trim', () => {
      assert.strictEqual(ValidationService.isValidDisplayName('A'.repeat(25)), false);
    });
  });
});
