import { describe, it } from 'node:test';
import assert from 'node:assert';
import type { Request } from 'express';
import { AuthAbuseService } from '../services/AuthAbuseService';

function makeRequest(
  path: string,
  {
    ip = '203.0.113.10',
    userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/135.0 Safari/537.36',
  }: {
    ip?: string;
    userAgent?: string;
  } = {},
): Request {
  return {
    path,
    ip,
    headers: {
      'user-agent': userAgent,
      'x-forwarded-for': ip,
    },
    socket: {
      remoteAddress: ip,
    },
  } as unknown as Request;
}

describe('AuthAbuseService', () => {
  it('bloque immédiatement un user-agent manifestement automatisé', () => {
    const service = new AuthAbuseService(() => 1_000);
    const req = makeRequest('/resolve-login', {
      userAgent: 'python-requests/2.32.0',
    });

    const decision = service.assess(req, 'login_resolve');

    assert.equal(decision.blocked, true);
    assert.ok(decision.score >= 80);
    assert.ok(decision.reasons.some((reason) => reason.includes('user-agent automatisé')));
  });

  it('tolère un trafic navigateur normal sur resolve-login', () => {
    let now = 10_000;
    const service = new AuthAbuseService(() => now);
    const req = makeRequest('/resolve-login');

    for (let i = 0; i < 5; i += 1) {
      now += 1_000;
      const decision = service.assess(req, 'login_resolve');
      assert.equal(decision.blocked, false);
    }
  });

  it('bloque une rafale massive de resolve-login depuis la même IP', () => {
    let now = 50_000;
    const service = new AuthAbuseService(() => now);
    const req = makeRequest('/resolve-login');
    let decision = service.assess(req, 'login_resolve');
    let blockedAtLeastOnce = decision.blocked;

    for (let i = 0; i < 35; i += 1) {
      now += 250;
      decision = service.assess(req, 'login_resolve');
      blockedAtLeastOnce ||= decision.blocked;
    }

    assert.equal(blockedAtLeastOnce, true);
    assert.equal(decision.blocked, true);
    assert.ok((decision.retryAfterSeconds ?? 0) > 0);
  });

  it('bloque après plusieurs créations de profil depuis la même IP', () => {
    let now = 100_000;
    const service = new AuthAbuseService(() => now);
    const req = makeRequest('/profile');

    for (let i = 0; i < 4; i += 1) {
      service.noteProfileCreated(req, `uid-${i}`);
      now += 5_000;
    }

    const decision = service.assess(req, 'profile_create');

    assert.equal(decision.blocked, true);
    assert.ok(decision.reasons.some((reason) => reason.includes('trop de comptes créés récemment')));
  });
});
