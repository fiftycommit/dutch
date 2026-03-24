export class ValidationService {
  private static readonly USERNAME_REGEX = /^[a-zA-Z0-9._-]{3,20}$/;
  private static readonly ROOM_CODE_REGEX = /^[A-Z0-9]{4,8}$/;
  private static readonly EMAIL_REGEX = /^[^\s@]{1,64}@[^\s@]{1,253}\.[^\s@]{1,63}$/;

  static sanitizePlayerName(name: unknown): string {
    if (typeof name !== 'string') return 'Joueur';
    return name.replaceAll(/<[^>]{0,500}>/g, '').trim().slice(0, 24) || 'Joueur';
  }

  static sanitizeChatMessage(msg: unknown): string {
    if (typeof msg !== 'string') return '';
    return msg.replaceAll(/<[^>]{0,500}>/g, '').trim().slice(0, 200);
  }

  static isValidRoomCode(code: unknown): code is string {
    return typeof code === 'string' && this.ROOM_CODE_REGEX.test(code);
  }

  static isValidUsername(username: unknown): username is string {
    return typeof username === 'string' && this.USERNAME_REGEX.test(username);
  }

  static isValidPassword(password: unknown): password is string {
    return typeof password === 'string' && password.length >= 6 && password.length <= 100;
  }

  static isValidDisplayName(name: unknown): name is string {
    if (typeof name !== 'string') return false;
    const trimmed = name.trim();
    return trimmed.length >= 1 && trimmed.length <= 24;
  }

  static sanitizeDisplayName(name: unknown): string {
    if (typeof name !== 'string') return 'Joueur';
    return name.replaceAll(/<[^>]{0,500}>/g, '').trim().slice(0, 24) || 'Joueur';
  }

  static isValidEmail(email: unknown): email is string {
    return typeof email === 'string' && this.EMAIL_REGEX.test(email.trim());
  }
}
