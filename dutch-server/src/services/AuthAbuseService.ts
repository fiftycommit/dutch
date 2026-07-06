import type { Request, Response } from 'express';

export type AuthAbuseAction =
  | 'username_check'
  | 'login_resolve'
  | 'password_login'
  | 'password_register'
  | 'profile_create'
  | 'profile_update';

interface AbuseDecision {
  blocked: boolean;
  score: number;
  reasons: string[];
  retryAfterSeconds?: number;
}

interface BlockState {
  until: number;
  reason: string;
}

const SUSPICIOUS_USER_AGENT_PATTERNS: RegExp[] = [
  /curl/i,
  /wget/i,
  /python/i,
  /requests/i,
  /axios/i,
  /node-fetch/i,
  /go-http-client/i,
  /java\//i,
  /libwww-perl/i,
  /postmanruntime/i,
  /insomnia/i,
  /headless/i,
  /phantomjs/i,
  /selenium/i,
  /playwright/i,
  /puppeteer/i,
];

function windowMs(minutes: number): number {
  return minutes * 60 * 1000;
}

function summarizeUserAgent(userAgent: string): string {
  const trimmed = userAgent.trim();
  if (trimmed.length <= 120) {
    return trimmed;
  }
  return `${trimmed.slice(0, 117)}...`;
}

export class AuthAbuseService {
  private readonly nowProvider: () => number;
  private readonly activity = new Map<string, number[]>();
  private readonly accountCreations = new Map<string, number[]>();
  private readonly blockedIps = new Map<string, BlockState>();
  private readonly blockedFingerprints = new Map<string, BlockState>();

  constructor(nowProvider: () => number = () => Date.now()) {
    this.nowProvider = nowProvider;
  }

  assess(req: Request, action: AuthAbuseAction): AbuseDecision {
    // Bypass explicite pour le dev/test local (émulateurs) : sinon deux clients
    // qui s'inscrivent/se connectent en rafale se font bloquer. N'affecte ni la
    // prod ni les tests unitaires (variable posée seulement par le lancement dev).
    if (process.env.AUTH_ABUSE_DISABLED === '1') {
      return { blocked: false, score: 0, reasons: [] };
    }

    const now = this.nowProvider();
    const ip = this.getClientIp(req);
    const userAgent = this.getUserAgent(req);
    const fingerprint = this.getFingerprint(ip, userAgent);

    this.cleanupExpiredBlocks(now);
    this.recordActivity(this.keyFor(ip, action), now);
    this.recordActivity(this.keyFor(fingerprint, action), now);
    this.recordActivity(this.keyFor(ip, 'all'), now);

    const existingBlock = this.findExistingBlock(ip, fingerprint, now);
    if (existingBlock) {
      this.logBlockedRequest(req, action, ip, userAgent, 100, [existingBlock.reason]);
      return {
        blocked: true,
        score: 100,
        reasons: [existingBlock.reason],
        retryAfterSeconds: Math.max(1, Math.ceil((existingBlock.until - now) / 1000)),
      };
    }

    let score = 0;
    const reasons: string[] = [];

    score += this.scoreUserAgent(userAgent, reasons);
    score += this.scoreAuthVolume(ip, fingerprint, action, now, reasons);
    score += this.scoreRecentAccountCreations(ip, fingerprint, now, reasons);

    if (score >= 40) {
      this.logSuspiciousRequest(req, action, ip, userAgent, score, reasons);
    }

    if (score < this.blockThreshold(action)) {
      return { blocked: false, score, reasons };
    }

    const blockDurationMs = this.blockDurationMs(action, score);
    const blockReason = `score=${score} action=${action}`;
    this.blockedIps.set(ip, { until: now + blockDurationMs, reason: blockReason });
    if (this.looksLikeAutomation(userAgent)) {
      this.blockedFingerprints.set(fingerprint, {
        until: now + blockDurationMs,
        reason: `${blockReason} ua_suspect`,
      });
    }

    this.logBlockedRequest(req, action, ip, userAgent, score, reasons);
    return {
      blocked: true,
      score,
      reasons,
      retryAfterSeconds: Math.max(1, Math.ceil(blockDurationMs / 1000)),
    };
  }

  reject(res: Response, decision: AbuseDecision): void {
    if (decision.retryAfterSeconds) {
      res.setHeader('Retry-After', decision.retryAfterSeconds.toString());
    }

    res.status(429).json({
      success: false,
      error: 'Activité temporairement limitée. Réessayez plus tard.',
      code: 'AUTH_ABUSE_PROTECTION',
    });
  }

  noteProfileCreated(req: Request, uid: string): void {
    const now = this.nowProvider();
    const ip = this.getClientIp(req);
    const userAgent = this.getUserAgent(req);
    const fingerprint = this.getFingerprint(ip, userAgent);

    this.recordAccountCreation(ip, now);
    this.recordAccountCreation(fingerprint, now);

    const countLastHour = this.getCountWithinWindow(this.accountCreations.get(ip), now, windowMs(60));
    if (countLastHour >= 3) {
      console.warn(
        `[SECURITY][AUTH_ABUSE] créations multiples depuis IP ${ip} — uid=${uid} count_1h=${countLastHour} ua="${summarizeUserAgent(userAgent)}"`,
      );
    }
  }

  resetForTesting(): void {
    this.activity.clear();
    this.accountCreations.clear();
    this.blockedIps.clear();
    this.blockedFingerprints.clear();
  }

  private scoreUserAgent(userAgent: string, reasons: string[]): number {
    if (!userAgent) {
      reasons.push('user-agent absent');
      return 25;
    }

    if (SUSPICIOUS_USER_AGENT_PATTERNS.some((pattern) => pattern.test(userAgent))) {
      reasons.push('user-agent automatisé');
      return 80;
    }

    if (userAgent.length < 16) {
      reasons.push('user-agent très court');
      return 10;
    }

    return 0;
  }

  private scoreAuthVolume(
    ip: string,
    fingerprint: string,
    action: AuthAbuseAction,
    now: number,
    reasons: string[],
  ): number {
    let score = 0;

    const ipActionCount = this.getCountWithinWindow(this.activity.get(this.keyFor(ip, action)), now, this.windowFor(action));
    const fpActionCount = this.getCountWithinWindow(this.activity.get(this.keyFor(fingerprint, action)), now, this.windowFor(action));
    const ipGlobalCount = this.getCountWithinWindow(this.activity.get(this.keyFor(ip, 'all')), now, windowMs(15));

    if (action === 'username_check') {
      if (ipActionCount >= 60 || fpActionCount >= 60) {
        reasons.push('énumération massive de pseudos');
        score += 60;
      } else if (ipActionCount >= 20 || fpActionCount >= 20) {
        reasons.push('beaucoup de vérifications de pseudo');
        score += 25;
      }
    }

    if (action === 'login_resolve' || action === 'password_login') {
      if (ipActionCount >= 30 || fpActionCount >= 30) {
        reasons.push('tentatives de login massives');
        score += 60;
      } else if (ipActionCount >= 12 || fpActionCount >= 12) {
        reasons.push('beaucoup de tentatives de login');
        score += 25;
      }
    }

    if (action === 'profile_create' || action === 'password_register') {
      if (ipActionCount >= 6 || fpActionCount >= 6) {
        reasons.push('créations de compte répétées');
        score += 35;
      }
    }

    if (ipGlobalCount >= 150) {
      reasons.push('rafale globale sur /api/auth');
      score += 40;
    } else if (ipGlobalCount >= 80) {
      reasons.push('fort volume sur /api/auth');
      score += 15;
    }

    return score;
  }

  private scoreRecentAccountCreations(
    ip: string,
    fingerprint: string,
    now: number,
    reasons: string[],
  ): number {
    const countByIp = this.getCountWithinWindow(this.accountCreations.get(ip), now, windowMs(60));
    const countByFingerprint = this.getCountWithinWindow(
      this.accountCreations.get(fingerprint),
      now,
      windowMs(60),
    );
    const maxCount = Math.max(countByIp, countByFingerprint);

    if (maxCount >= 4) {
      reasons.push('trop de comptes créés récemment');
      return 60;
    }

    if (maxCount >= 3) {
      reasons.push('plusieurs comptes créés récemment');
      return 25;
    }

    return 0;
  }

  private blockThreshold(action: AuthAbuseAction): number {
    switch (action) {
      case 'password_register':
      case 'profile_create':
        return 60;
      case 'profile_update':
        return 85;
      case 'username_check':
      case 'login_resolve':
      case 'password_login':
        return 60;
    }
  }

  private blockDurationMs(action: AuthAbuseAction, score: number): number {
    if (score >= 90) {
      return windowMs(12);
    }

    if (action === 'profile_create' || action === 'password_register') {
      return windowMs(6);
    }

    return windowMs(30);
  }

  private windowFor(action: AuthAbuseAction): number {
    switch (action) {
      case 'password_register':
      case 'profile_create':
      case 'profile_update':
        return windowMs(60);
      case 'username_check':
        return windowMs(10);
      case 'login_resolve':
      case 'password_login':
        return windowMs(15);
    }
  }

  private getClientIp(req: Request): string {
    const xff = req.headers['x-forwarded-for'];
    if (typeof xff === 'string' && xff.trim().length > 0) {
      return xff.split(',')[0].trim();
    }
    if (Array.isArray(xff) && xff.length > 0 && xff[0]) {
      return xff[0].split(',')[0].trim();
    }
    return req.ip || req.socket.remoteAddress || 'unknown';
  }

  private getUserAgent(req: Request): string {
    const value = req.headers['user-agent'];
    return typeof value === 'string' ? value.trim() : '';
  }

  private getFingerprint(ip: string, userAgent: string): string {
    return `${ip}::${userAgent || 'ua-missing'}`;
  }

  private looksLikeAutomation(userAgent: string): boolean {
    return SUSPICIOUS_USER_AGENT_PATTERNS.some((pattern) => pattern.test(userAgent));
  }

  private keyFor(subject: string, action: AuthAbuseAction | 'all'): string {
    return `${subject}::${action}`;
  }

  private recordActivity(key: string, timestamp: number): void {
    const entries = this.activity.get(key) ?? [];
    entries.push(timestamp);
    this.activity.set(key, this.pruneEntries(entries, timestamp, windowMs(60)));
  }

  private recordAccountCreation(key: string, timestamp: number): void {
    const entries = this.accountCreations.get(key) ?? [];
    entries.push(timestamp);
    this.accountCreations.set(key, this.pruneEntries(entries, timestamp, windowMs(24 * 60)));
  }

  private pruneEntries(entries: number[], now: number, maxAgeMs: number): number[] {
    const cutoff = now - maxAgeMs;
    return entries.filter((value) => value >= cutoff);
  }

  private getCountWithinWindow(entries: number[] | undefined, now: number, durationMs: number): number {
    if (!entries || entries.length === 0) {
      return 0;
    }

    const cutoff = now - durationMs;
    let count = 0;
    for (const value of entries) {
      if (value >= cutoff) {
        count += 1;
      }
    }
    return count;
  }

  private cleanupExpiredBlocks(now: number): void {
    for (const [key, state] of this.blockedIps.entries()) {
      if (state.until <= now) {
        this.blockedIps.delete(key);
      }
    }

    for (const [key, state] of this.blockedFingerprints.entries()) {
      if (state.until <= now) {
        this.blockedFingerprints.delete(key);
      }
    }
  }

  private findExistingBlock(ip: string, fingerprint: string, now: number): BlockState | null {
    const ipBlock = this.blockedIps.get(ip);
    if (ipBlock && ipBlock.until > now) {
      return ipBlock;
    }

    const fingerprintBlock = this.blockedFingerprints.get(fingerprint);
    if (fingerprintBlock && fingerprintBlock.until > now) {
      return fingerprintBlock;
    }

    return null;
  }

  private logSuspiciousRequest(
    req: Request,
    action: AuthAbuseAction,
    ip: string,
    userAgent: string,
    score: number,
    reasons: string[],
  ): void {
    console.warn(
      `[SECURITY][AUTH_ABUSE] suspect action=${action} path=${req.path} ip=${ip} score=${score} reasons="${reasons.join(', ')}" ua="${summarizeUserAgent(userAgent)}"`,
    );
  }

  private logBlockedRequest(
    req: Request,
    action: AuthAbuseAction,
    ip: string,
    userAgent: string,
    score: number,
    reasons: string[],
  ): void {
    console.warn(
      `[SECURITY][AUTH_ABUSE] blocked action=${action} path=${req.path} ip=${ip} score=${score} reasons="${reasons.join(', ')}" ua="${summarizeUserAgent(userAgent)}"`,
    );
  }
}

export const authAbuseService = new AuthAbuseService();
