import * as admin from 'firebase-admin';

// ─── Singleton Firebase Admin ───────────────────────────────────────────────
// Centralise l'initialisation pour éviter les doublons
// (PushNotificationService, socketAuthMiddleware, etc.)

let initialized = false;

function initFirebase(): void {
    if (initialized || admin.apps.length > 0) {
        initialized = true;
        return;
    }

    // 1. Variable d'environnement (Production — injectée par PM2/GitHub Actions)
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
        try {
            const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
            admin.initializeApp({
                credential: admin.credential.cert(serviceAccount),
            });
            initialized = true;
            console.log('🔥 Firebase Admin initialisé (via ENV)');
            return;
        } catch (e) {
            console.error('❌ Erreur parsing FIREBASE_SERVICE_ACCOUNT_JSON:', e);
        }
    }

    // 2. Fichier local (Dev)
    const path = require('node:path');
    const fs = require('node:fs');
    const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS
        || path.join(process.cwd(), 'data/firebase-service-account.json');

    if (fs.existsSync(serviceAccountPath)) {
        const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf-8'));
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
        });
        initialized = true;
        console.log('🔥 Firebase Admin initialisé (via FILE)');
        return;
    }

    console.warn('⚠️ Firebase non configuré (ni ENV ni FILE). Auth et Firestore désactivés.');
}

// Initialiser immédiatement à l'import
initFirebase();

export { admin };
export const firestore = admin.apps.length > 0 ? admin.firestore() : null;
export const auth = admin.apps.length > 0 ? admin.auth() : null;
export const messaging = admin.apps.length > 0 ? admin.messaging() : null;
