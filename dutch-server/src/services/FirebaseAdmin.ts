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

    // 0. Émulateurs Firebase (dev/test local uniquement). Détectés via les
    //    variables d'env standard posées par `firebase emulators:exec/start`
    //    (FIREBASE_AUTH_EMULATOR_HOST / FIRESTORE_EMULATOR_HOST). Le SDK Admin
    //    route alors Auth/Firestore vers les émulateurs et n'exige AUCUNE vraie
    //    clé de service. Ne concerne jamais la prod (ces vars n'y sont pas).
    if (process.env.FIREBASE_AUTH_EMULATOR_HOST
        || process.env.FIRESTORE_EMULATOR_HOST) {
        admin.initializeApp({
            projectId: process.env.GCLOUD_PROJECT
                || process.env.FIREBASE_PROJECT_ID
                || 'dutch-game-1dd01',
        });
        initialized = true;
        console.log('🧪 Firebase Admin initialisé (ÉMULATEURS locaux)');
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
