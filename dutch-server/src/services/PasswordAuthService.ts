import { auth as firebaseAuth } from './FirebaseAdmin';
import { firestoreService, FirestoreUser } from './FirestoreService';
import { ValidationService } from './ValidationService';

const FIREBASE_PASSWORD_SIGN_IN_URL =
  'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
const EMAIL_REGEX = /^[^\s@]{1,64}@[^\s@]{1,253}\.[^\s@]{1,63}$/;

interface FirebaseUserRecordLike {
  uid: string;
}

interface AdminAuthLike {
  createUser(data: {
    email: string;
    password: string;
    displayName?: string;
  }): Promise<FirebaseUserRecordLike>;
  deleteUser(uid: string): Promise<void>;
  createCustomToken(uid: string): Promise<string>;
}

interface FirestoreServiceLike {
  isUsernameAvailable(username: string, exceptUid?: string): Promise<boolean>;
  getUserByUsername(
    username: string,
  ): Promise<{ uid: string; data: FirestoreUser } | null>;
  getUser(uid: string): Promise<FirestoreUser | null>;
  createUser(uid: string, data: Partial<FirestoreUser>): Promise<FirestoreUser>;
}

interface PasswordSignInResponse {
  localId?: string;
  email?: string;
}

interface PasswordAuthServiceDeps {
  adminAuth?: AdminAuthLike | null;
  firestore?: FirestoreServiceLike;
  fetchImpl?: typeof fetch;
  apiKey?: string;
}

export interface RegisterWithPasswordInput {
  username: string;
  displayName: string;
  email: string;
  password: string;
}

export interface RegisterWithPasswordResult {
  customToken: string;
  uid: string;
  email: string;
  username: string;
  displayName: string;
}

export interface LoginWithPasswordInput {
  identifier: string;
  password: string;
  appCheckToken?: string;
}

export interface LoginWithPasswordResult {
  customToken: string;
  uid: string;
  email: string;
}

export class PasswordAuthService {
  private readonly adminAuth: AdminAuthLike | null;
  private readonly firestore: FirestoreServiceLike;
  private readonly fetchImpl: typeof fetch;
  private readonly apiKey: string;

  constructor({
    adminAuth = firebaseAuth,
    firestore = firestoreService,
    fetchImpl = fetch,
    apiKey = process.env.FIREBASE_WEB_API_KEY || '',
  }: PasswordAuthServiceDeps = {}) {
    this.adminAuth = adminAuth;
    this.firestore = firestore;
    this.fetchImpl = fetchImpl;
    this.apiKey = apiKey.trim();
  }

  async registerWithPassword(
    input: RegisterWithPasswordInput,
  ): Promise<RegisterWithPasswordResult> {
    this.ensureConfigured();

    const username = this.normalizeUsername(input.username);
    const displayName = ValidationService.sanitizeDisplayName(input.displayName);
    const email = input.email.trim().toLowerCase();
    const password = input.password;

    if (!ValidationService.isValidUsername(username)) {
      throw new PasswordAuthError(
        'invalid-username',
        'Nom d\'utilisateur invalide (3-20 caractères, lettres/chiffres/._-)',
        400,
      );
    }
    if (!ValidationService.isValidDisplayName(displayName)) {
      throw new PasswordAuthError(
        'invalid-display-name',
        'Pseudo invalide (24 caractères maximum)',
        400,
      );
    }
    if (!ValidationService.isValidEmail(email)) {
      throw new PasswordAuthError('invalid-email', 'Adresse e-mail invalide', 400);
    }
    if (!ValidationService.isValidPassword(password)) {
      throw new PasswordAuthError(
        'invalid-password',
        'Mot de passe trop faible (min 6 caractères)',
        400,
      );
    }

    const usernameAvailable = await this.firestore.isUsernameAvailable(username);
    if (!usernameAvailable) {
      throw new PasswordAuthError(
        'username-taken',
        'Ce nom d\'utilisateur est déjà pris',
        409,
      );
    }

    let createdUid: string | null = null;

    try {
      const createdUser = await this.adminAuth!.createUser({
        email,
        password,
        displayName,
      });
      createdUid = createdUser.uid;

      await this.firestore.createUser(createdUid, {
        username,
        displayName,
        email,
      });

      const customToken = await this.adminAuth!.createCustomToken(createdUid);
      return {
        customToken,
        uid: createdUid,
        email,
        username,
        displayName,
      };
    } catch (error) {
      if (createdUid) {
        try {
          await this.adminAuth!.deleteUser(createdUid);
        } catch (cleanupError) {
          console.error(
            `[SECURITY][AUTH] rollback inscription impossible uid=${createdUid}`,
            cleanupError,
          );
        }
      }

      throw this.mapRegisterError(error);
    }
  }

  async loginWithPassword(
    input: LoginWithPasswordInput,
  ): Promise<LoginWithPasswordResult> {
    this.ensureConfigured();

    const identifier = input.identifier.trim();
    const password = input.password;
    const appCheckToken = input.appCheckToken?.trim();

    if (!identifier) {
      throw new PasswordAuthError(
        'missing-identifier',
        'Email ou pseudo requis',
        400,
      );
    }
    if (!password) {
      throw new PasswordAuthError(
        'missing-password',
        'Mot de passe requis',
        400,
      );
    }

    let expectedUid: string | null = null;
    let loginEmail = identifier.toLowerCase();

    if (!EMAIL_REGEX.test(identifier)) {
      const usernameLookup = await this.firestore.getUserByUsername(
        this.normalizeUsername(identifier),
      );

      if (!usernameLookup || !usernameLookup.data.email) {
        throw new PasswordAuthError(
          'invalid-credentials',
          'Email ou mot de passe incorrect',
          401,
        );
      }

      if (usernameLookup.data.isBanned) {
        throw new PasswordAuthError('account-banned', 'Compte banni', 403);
      }

      expectedUid = usernameLookup.uid;
      loginEmail = usernameLookup.data.email.trim().toLowerCase();
    }

    const passwordLogin = await this.verifyPassword(
      loginEmail,
      password,
      appCheckToken,
    );

    if (expectedUid && passwordLogin.localId !== expectedUid) {
      console.warn(
        `[SECURITY][AUTH] UID inattendu après vérification mot de passe attendu=${expectedUid} reçu=${passwordLogin.localId}`,
      );
      throw new PasswordAuthError(
        'invalid-credentials',
        'Email ou mot de passe incorrect',
        401,
      );
    }

    const firestoreUser = await this.firestore.getUser(passwordLogin.localId);
    if (firestoreUser?.isBanned) {
      throw new PasswordAuthError('account-banned', 'Compte banni', 403);
    }

    const customToken = await this.adminAuth!.createCustomToken(passwordLogin.localId);

    return {
      customToken,
      uid: passwordLogin.localId,
      email: passwordLogin.email,
    };
  }

  private ensureConfigured(): void {
    if (!this.adminAuth) {
      throw new PasswordAuthError(
        'service-unavailable',
        'Authentification indisponible',
        503,
      );
    }

    if (!this.apiKey) {
      throw new PasswordAuthError(
        'service-unavailable',
        'Configuration Firebase incomplète',
        503,
      );
    }
  }

  private normalizeUsername(username: string): string {
    return username.trim().toLowerCase();
  }

  private async verifyPassword(
    email: string,
    password: string,
    appCheckToken?: string,
  ): Promise<{ localId: string; email: string }> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    if (appCheckToken) {
      headers['X-Firebase-AppCheck'] = appCheckToken;
    }

    const response = await this.fetchImpl(
      `${FIREBASE_PASSWORD_SIGN_IN_URL}?key=${encodeURIComponent(this.apiKey)}`,
      {
        method: 'POST',
        headers,
        body: JSON.stringify({
          email,
          password,
          returnSecureToken: true,
        }),
      },
    );

    let payload: PasswordSignInResponse & {
      error?: { message?: string };
    } = {};

    try {
      payload = (await response.json()) as PasswordSignInResponse & {
        error?: { message?: string };
      };
    } catch {
      payload = {};
    }

    if (!response.ok || !payload.localId || !payload.email) {
      const message = payload.error?.message || '';
      if (
        message === 'INVALID_LOGIN_CREDENTIALS' ||
        message === 'INVALID_PASSWORD' ||
        message === 'EMAIL_NOT_FOUND' ||
        message === 'INVALID_EMAIL'
      ) {
        throw new PasswordAuthError(
          'invalid-credentials',
          'Email ou mot de passe incorrect',
          401,
        );
      }
      if (message === 'USER_DISABLED') {
        throw new PasswordAuthError('account-disabled', 'Compte désactivé', 403);
      }
      throw new PasswordAuthError(
        'service-unavailable',
        'Impossible de vérifier les identifiants',
        503,
      );
    }

    return {
      localId: payload.localId,
      email: payload.email.trim().toLowerCase(),
    };
  }

  private mapRegisterError(error: unknown): Error {
    if (error instanceof PasswordAuthError) {
      return error;
    }

    const code = this.extractFirebaseCode(error);

    if (code === 'auth/email-already-exists') {
      return new PasswordAuthError(
        'email-already-exists',
        'Cette adresse e-mail est déjà utilisée',
        409,
      );
    }

    if (code === 'auth/invalid-password') {
      return new PasswordAuthError(
        'invalid-password',
        'Mot de passe trop faible (min 6 caractères)',
        400,
      );
    }

    if (code === 'auth/invalid-email') {
      return new PasswordAuthError('invalid-email', 'Adresse e-mail invalide', 400);
    }

    return new PasswordAuthError(
      'register-failed',
      'Impossible de créer le compte',
      500,
    );
  }

  private extractFirebaseCode(error: unknown): string | null {
    if (typeof error !== 'object' || error === null) {
      return null;
    }

    const code = (error as { code?: string }).code;
    return typeof code === 'string' ? code : null;
  }
}

export class PasswordAuthError extends Error {
  readonly code: string;
  readonly statusCode: number;

  constructor(code: string, message: string, statusCode: number) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
  }
}

export const passwordAuthService = new PasswordAuthService();
