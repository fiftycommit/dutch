import tls from 'node:tls';

interface SmtpConfig {
  host: string;
  port: number;
  user: string;
  pass: string;
  from: string;
  secure: boolean;
}

function sanitizeHeaderValue(value: string): string {
  return value.replaceAll(/[\r\n]/g, ' ').trim();
}

function encodeBase64(value: string): string {
  return Buffer.from(value, 'utf8').toString('base64');
}

function dotStuff(text: string): string {
  return text
    .split('\n')
    .map((line) => (line.startsWith('.') ? `.${line}` : line))
    .join('\r\n');
}

async function sendWithSmtp(
  config: SmtpConfig,
  to: string,
  subject: string,
  textBody: string,
  htmlBody: string
): Promise<void> {
  if (!config.secure) {
    throw new Error(
      'SMTP_SECURE=false non supporte pour l instant. Utilise SMTP_SECURE=true (port 465).'
    );
  }

  const socket = tls.connect({
    host: config.host,
    port: config.port,
    servername: config.host,
    rejectUnauthorized:
      (process.env.SMTP_ALLOW_INVALID_CERT || '').toLowerCase() !== 'true',
  });

  socket.setEncoding('utf8');
  socket.setTimeout(20_000);

  const waitForResponse = (
    expectedCodes: string[],
    context: string
  ): Promise<string> => {
    return new Promise((resolve, reject) => {
      let buffer = '';
      const lines: string[] = [];

      const cleanup = () => {
        socket.off('data', onData);
        socket.off('error', onError);
        socket.off('timeout', onTimeout);
      };

      const onError = (error: Error) => {
        cleanup();
        reject(new Error(`SMTP ${context} failed: ${error.message}`));
      };

      const onTimeout = () => {
        cleanup();
        reject(new Error(`SMTP timeout during ${context}`));
      };

      const onData = (chunk: string | Buffer) => {
        buffer += chunk.toString();
        let idx = buffer.indexOf('\r\n');
        while (idx >= 0) {
          const line = buffer.slice(0, idx);
          buffer = buffer.slice(idx + 2);
          lines.push(line);

          const isTerminalLine = /^\d{3}\s/.test(line);
          if (isTerminalLine) {
            cleanup();
            const code = line.slice(0, 3);
            if (!expectedCodes.includes(code)) {
              reject(
                new Error(
                  `SMTP ${context} failed (${code}): ${lines.join(' | ')}`
                )
              );
              return;
            }
            resolve(lines.join('\n'));
            return;
          }

          idx = buffer.indexOf('\r\n');
        }
      };

      socket.on('data', onData);
      socket.on('error', onError);
      socket.on('timeout', onTimeout);
    });
  };

  const writeCommand = async (
    command: string,
    expectedCodes: string[],
    context: string
  ): Promise<void> => {
    socket.write(`${command}\r\n`);
    await waitForResponse(expectedCodes, context);
  };

  try {
    await waitForResponse(['220'], 'greeting');
    await writeCommand('EHLO dutch-game.me', ['250'], 'EHLO');
    await writeCommand('AUTH LOGIN', ['334'], 'AUTH LOGIN');
    await writeCommand(encodeBase64(config.user), ['334'], 'AUTH USER');
    await writeCommand(encodeBase64(config.pass), ['235'], 'AUTH PASS');
    await writeCommand(
      `MAIL FROM:<${sanitizeHeaderValue(config.from)}>`,
      ['250'],
      'MAIL FROM'
    );
    await writeCommand(
      `RCPT TO:<${sanitizeHeaderValue(to)}>`,
      ['250', '251'],
      'RCPT TO'
    );
    await writeCommand('DATA', ['354'], 'DATA');

    const boundary = `dutch-${Date.now().toString(36)}`;
    const headers = [
      `From: ${sanitizeHeaderValue(config.from)}`,
      `To: ${sanitizeHeaderValue(to)}`,
      `Subject: ${sanitizeHeaderValue(subject)}`,
      'MIME-Version: 1.0',
      `Content-Type: multipart/alternative; boundary="${boundary}"`,
      '',
      `--${boundary}`,
      'Content-Type: text/plain; charset="utf-8"',
      'Content-Transfer-Encoding: 8bit',
      '',
      textBody,
      `--${boundary}`,
      'Content-Type: text/html; charset="utf-8"',
      'Content-Transfer-Encoding: 8bit',
      '',
      htmlBody,
      `--${boundary}--`,
      '',
    ].join('\r\n');

    socket.write(`${dotStuff(headers)}\r\n.\r\n`);
    await waitForResponse(['250'], 'message body');
    await writeCommand('QUIT', ['221'], 'QUIT');
  } finally {
    socket.end();
    socket.destroy();
  }
}

export class EmailService {
  private static getBaseUrl(): string {
    const raw = process.env.APP_BASE_URL || 'https://dutch-game.me';
    return raw.endsWith('/') ? raw.slice(0, -1) : raw;
  }

  private static readSmtpConfig(): SmtpConfig | null {
    const host = process.env.SMTP_HOST;
    const user = process.env.SMTP_USER;
    const pass = process.env.SMTP_PASS;
    const from = process.env.SMTP_FROM || process.env.SMTP_USER;
    const portRaw = process.env.SMTP_PORT;

    if (!host || !user || !pass || !from || !portRaw) {
      return null;
    }

    const port = Number.parseInt(portRaw, 10);
    if (Number.isNaN(port)) {
      return null;
    }

    return {
      host,
      port,
      user,
      pass,
      from,
      secure: (process.env.SMTP_SECURE || 'true').toLowerCase() === 'true',
    };
  }

  static async sendPasswordResetEmail(
    toEmail: string,
    token: string
  ): Promise<{ success: boolean; error?: string }> {
    const resetUrl = `${this.getBaseUrl()}/reset-password?token=${encodeURIComponent(
      token
    )}`;

    const smtpConfig = this.readSmtpConfig();
    if (!smtpConfig) {
      console.warn(
        'EmailService: SMTP non configure. Lien de reset loggue en console.'
      );
      console.log(`[DEV PASSWORD RESET] ${toEmail} -> ${resetUrl}`);
      return { success: true };
    }

    try {
      await sendWithSmtp(
        smtpConfig,
        toEmail,
        'Reinitialisation de mot de passe - Dutch Game',
        `Tu as demande une reinitialisation de mot de passe.\n\n` +
          `Lien: ${resetUrl}\n\n` +
          `Ce lien expire dans 1 heure.\n` +
          `Si tu n'es pas a l'origine de cette demande, ignore cet email.`,
        `<p>Tu as demande une reinitialisation de mot de passe.</p>` +
          `<p><a href="${resetUrl}">Reinitialiser mon mot de passe</a></p>` +
          '<p>Ce lien expire dans 1 heure.</p>' +
          "<p>Si tu n'es pas a l'origine de cette demande, ignore cet email.</p>"
      );
      return { success: true };
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Echec envoi email';
      console.error('EmailService: echec envoi reset password:', message);
      return {
        success: false,
        error: 'Impossible d envoyer l email de reinitialisation',
      };
    }
  }
}
