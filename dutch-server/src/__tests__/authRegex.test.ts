import { describe, it } from 'node:test';
import assert from 'node:assert';

// Test the bounded email regex used in authRoutes.ts
const emailRegex = /^[^\s@]{1,64}@[^\s@]{1,253}\.[^\s@]{1,63}$/;

describe('Auth email regex (bounded, ReDoS-safe)', () => {
  it('accepts valid emails', () => {
    assert.ok(emailRegex.test('user@example.com'));
    assert.ok(emailRegex.test('a@b.co'));
    assert.ok(emailRegex.test('test.user+tag@gmail.com'));
  });

  it('rejects emails without @', () => {
    assert.strictEqual(emailRegex.test('userexample.com'), false);
  });

  it('rejects emails without domain', () => {
    assert.strictEqual(emailRegex.test('user@'), false);
  });

  it('rejects emails without TLD', () => {
    assert.strictEqual(emailRegex.test('user@example'), false);
  });

  it('rejects local part > 64 chars', () => {
    assert.strictEqual(emailRegex.test('a'.repeat(65) + '@example.com'), false);
  });

  it('rejects domain > 253 chars', () => {
    assert.strictEqual(emailRegex.test('user@' + 'a'.repeat(254) + '.com'), false);
  });

  it('rejects TLD > 63 chars', () => {
    assert.strictEqual(emailRegex.test('user@example.' + 'a'.repeat(64)), false);
  });

  it('accepts max valid lengths', () => {
    assert.ok(emailRegex.test('a'.repeat(64) + '@' + 'b'.repeat(253) + '.' + 'c'.repeat(63)));
  });

  it('does not hang on adversarial input (ReDoS protection)', () => {
    const start = Date.now();
    // Long string without @ — should fail fast with bounded quantifiers
    emailRegex.test('a'.repeat(10000));
    const elapsed = Date.now() - start;
    assert.ok(elapsed < 100, `Regex took ${elapsed}ms — possible ReDoS`);
  });
});
