import { admin, firestore } from './FirebaseAdmin';

// ─── Firestore Service ──────────────────────────────────────────────────────
// CRUD pour les données persistantes (profils, stats, historique).
// Le jeu en temps réel reste en RAM (RoomManager).

export interface FirestoreUser {
    username: string;
    displayName: string;
    email: string | null;
    createdAt: admin.firestore.Timestamp;
    updatedAt: admin.firestore.Timestamp;
    lastLoginAt: admin.firestore.Timestamp | null;
    isBanned: boolean;
    stats: {
        gamesPlayed: number;
        gamesWon: number;
        totalScore: number;
    };
}

export interface DeviceToken {
    token: string;
    platform: string;
    updatedAt: admin.firestore.Timestamp;
}

function isFirestoreMissingIndexError(error: unknown): boolean {
    if (typeof error !== 'object' || error === null) return false;
    const code = (error as { code?: string | number }).code;
    const message = String((error as { message?: unknown }).message ?? '').toLowerCase();
    return (
        code === 'failed-precondition' ||
        code === 9 ||
        (message.includes('index') && message.includes('create'))
    );
}

class FirestoreServiceClass {
    private get db() {
        if (!firestore) throw new Error('Firestore non initialisé');
        return firestore;
    }

    // ─── Users ───────────────────────────────────────────────────────────

    async getUser(uid: string): Promise<FirestoreUser | null> {
        const doc = await this.db.collection('users').doc(uid).get();
        return doc.exists ? (doc.data() as FirestoreUser) : null;
    }

    async createUser(uid: string, data: Partial<FirestoreUser>): Promise<FirestoreUser> {
        const now = admin.firestore.FieldValue.serverTimestamp();
        const user: Record<string, unknown> = {
            username: data.username || '',
            displayName: data.displayName || data.username || '',
            email: data.email || null,
            isBanned: false,
            stats: {
                gamesPlayed: 0,
                gamesWon: 0,
                totalScore: 0,
            },
            ...data,
            createdAt: now,
            updatedAt: now,
            lastLoginAt: now,
        };

        await this.db.collection('users').doc(uid).set(user);

        // Retourner une version propre
        const created = await this.getUser(uid);
        return created!;
    }

    async getOrCreateUser(uid: string, defaults: Partial<FirestoreUser>): Promise<FirestoreUser> {
        const existing = await this.getUser(uid);
        if (existing) {
            // Mettre à jour lastLoginAt
            await this.db.collection('users').doc(uid).update({
                lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return existing;
        }
        return this.createUser(uid, defaults);
    }

    async updateUser(uid: string, data: Partial<FirestoreUser>): Promise<void> {
        await this.db.collection('users').doc(uid).update({
            ...data,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    async deleteUser(uid: string): Promise<void> {
        const batch = this.db.batch();

        // Supprimer le document utilisateur
        batch.delete(this.db.collection('users').doc(uid));

        // Supprimer les sous-collections potentielles
        const friends = await this.db.collection('users').doc(uid).collection('friends').get();
        friends.docs.forEach((doc: FirebaseFirestore.QueryDocumentSnapshot) => batch.delete(doc.ref));

        const devices = await this.db.collection('users').doc(uid).collection('deviceTokens').get();
        devices.docs.forEach((doc: FirebaseFirestore.QueryDocumentSnapshot) => batch.delete(doc.ref));

        await batch.commit();
    }

    async setUserBanned(uid: string, banned: boolean): Promise<void> {
        await this.db.collection('users').doc(uid).update({
            isBanned: banned,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    async isUserBanned(uid: string): Promise<boolean> {
        const user = await this.getUser(uid);
        return user?.isBanned ?? false;
    }

    // ─── User Lookup ─────────────────────────────────────────────────────

    async getUserByUsername(username: string): Promise<{ uid: string; data: FirestoreUser } | null> {
        const snap = await this.db.collection('users')
            .where('username', '==', username.toLowerCase())
            .limit(1)
            .get();

        if (snap.empty) return null;
        const doc = snap.docs[0];
        return { uid: doc.id, data: doc.data() as FirestoreUser };
    }

    async isUsernameAvailable(username: string, exceptUid?: string): Promise<boolean> {
        const result = await this.getUserByUsername(username);
        if (!result) return true;
        return exceptUid ? result.uid === exceptUid : false;
    }

    // ─── Device Tokens ───────────────────────────────────────────────────

    async registerDeviceToken(uid: string, token: string, platform: string): Promise<void> {
        const col = this.db.collection('users').doc(uid).collection('deviceTokens');
        // Supprimer les anciens tokens de la même plateforme (évite les doublons de notif)
        const oldSnap = await col.where('platform', '==', platform).get();
        const deletions = oldSnap.docs
            .filter((d: FirebaseFirestore.QueryDocumentSnapshot) => d.id !== token)
            .map((d: FirebaseFirestore.QueryDocumentSnapshot) => d.ref.delete());
        await Promise.all(deletions);
        await col.doc(token).set({
            token,
            platform,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    async removeDeviceToken(uid: string, token: string): Promise<void> {
        await this.db.collection('users').doc(uid)
            .collection('deviceTokens').doc(token).delete();
    }

    async getDeviceTokens(uid: string): Promise<string[]> {
        const snap = await this.db.collection('users').doc(uid)
            .collection('deviceTokens').get();
        return snap.docs.map((d: FirebaseFirestore.QueryDocumentSnapshot) => d.id);
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    async getAllUsers(options: {
        search?: string;
        page?: number;
        limit?: number;
    } = {}): Promise<{ users: Array<{ uid: string } & FirestoreUser>; total: number }> {
        const limit = Math.min(options.limit || 50, 100);
        const query: FirebaseFirestore.Query = this.db.collection('users')
            .orderBy('createdAt', 'desc')
            .limit(limit);

        const snap = await query.get();
        const users = snap.docs.map((doc: FirebaseFirestore.QueryDocumentSnapshot) => ({
            uid: doc.id,
            ...(doc.data() as FirestoreUser),
        }));

        return { users, total: users.length };
    }

    // ─── Friends ─────────────────────────────────────────────────────────

    async getFriends(uid: string): Promise<string[]> {
        const snap = await this.db.collection('users').doc(uid)
            .collection('friends').get();
        return snap.docs.map((d: FirebaseFirestore.QueryDocumentSnapshot) => d.id);
    }

    async addFriend(uid: string, friendUid: string): Promise<void> {
        const batch = this.db.batch();
        const now = admin.firestore.FieldValue.serverTimestamp();

        // Relation bidirectionnelle
        batch.set(this.db.collection('users').doc(uid).collection('friends').doc(friendUid), {
            addedAt: now,
        });
        batch.set(this.db.collection('users').doc(friendUid).collection('friends').doc(uid), {
            addedAt: now,
        });

        await batch.commit();
    }

    async removeFriend(uid: string, friendUid: string): Promise<void> {
        const batch = this.db.batch();

        batch.delete(this.db.collection('users').doc(uid).collection('friends').doc(friendUid));
        batch.delete(this.db.collection('users').doc(friendUid).collection('friends').doc(uid));

        await batch.commit();
    }

    // ─── Friend Requests ─────────────────────────────────────────────────

    async sendFriendRequest(fromUid: string, toUid: string): Promise<string> {
        const ref = await this.db.collection('friendRequests').add({
            fromUid,
            toUid,
            status: 'pending',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return ref.id;
    }

    async getPendingRequestsTo(uid: string): Promise<Array<{ id: string; fromUid: string; createdAt: admin.firestore.Timestamp }>> {
        const baseQuery = this.db.collection('friendRequests')
            .where('toUid', '==', uid)
            .where('status', '==', 'pending');

        let snap: FirebaseFirestore.QuerySnapshot;
        try {
            snap = await baseQuery.orderBy('createdAt', 'desc').get();
        } catch (error) {
            if (!isFirestoreMissingIndexError(error)) throw error;
            snap = await baseQuery.get();
        }

        const requests = snap.docs.map((d: FirebaseFirestore.QueryDocumentSnapshot) => ({
            id: d.id,
            fromUid: d.data().fromUid as string,
            createdAt:
                (d.data().createdAt as admin.firestore.Timestamp | undefined)
                ?? admin.firestore.Timestamp.fromMillis(0),
        }));

        requests.sort((a, b) => b.createdAt.toMillis() - a.createdAt.toMillis());
        return requests;
    }

    async getPendingRequestsFrom(uid: string): Promise<Array<{ id: string; toUid: string; createdAt: admin.firestore.Timestamp }>> {
        const baseQuery = this.db.collection('friendRequests')
            .where('fromUid', '==', uid)
            .where('status', '==', 'pending');

        let snap: FirebaseFirestore.QuerySnapshot;
        try {
            snap = await baseQuery.orderBy('createdAt', 'desc').get();
        } catch (error) {
            if (!isFirestoreMissingIndexError(error)) throw error;
            snap = await baseQuery.get();
        }

        const requests = snap.docs.map((d: FirebaseFirestore.QueryDocumentSnapshot) => ({
            id: d.id,
            toUid: d.data().toUid as string,
            createdAt:
                (d.data().createdAt as admin.firestore.Timestamp | undefined)
                ?? admin.firestore.Timestamp.fromMillis(0),
        }));

        requests.sort((a, b) => b.createdAt.toMillis() - a.createdAt.toMillis());
        return requests;
    }

    async acceptFriendRequest(requestId: string): Promise<{ fromUid: string; toUid: string } | null> {
        const ref = this.db.collection('friendRequests').doc(requestId);
        const doc = await ref.get();
        if (!doc.exists || doc.data()?.status !== 'pending') return null;

        const { fromUid, toUid } = doc.data()!;

        // Accepter la demande + ajouter en ami + supprimer la request
        await this.addFriend(fromUid, toUid);
        await ref.delete();

        return { fromUid, toUid };
    }

    async rejectFriendRequest(requestId: string): Promise<boolean> {
        const ref = this.db.collection('friendRequests').doc(requestId);
        const doc = await ref.get();
        if (!doc.exists || doc.data()?.status !== 'pending') return false;

        await ref.delete();
        return true;
    }

    async cancelFriendRequest(requestId: string, fromUid: string): Promise<boolean> {
        const ref = this.db.collection('friendRequests').doc(requestId);
        const doc = await ref.get();
        if (!doc.exists || doc.data()?.fromUid !== fromUid || doc.data()?.status !== 'pending') return false;

        await ref.delete();
        return true;
    }

    // ─── Blocked Users ───────────────────────────────────────────────────

    async blockUser(uid: string, targetUid: string): Promise<void> {
        const batch = this.db.batch();

        // Bloquer
        batch.set(this.db.collection('users').doc(uid).collection('blocked').doc(targetUid), {
            blockedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Supprimer l'amitié si elle existe
        batch.delete(this.db.collection('users').doc(uid).collection('friends').doc(targetUid));
        batch.delete(this.db.collection('users').doc(targetUid).collection('friends').doc(uid));

        await batch.commit();

        // Supprimer les friend requests en attente entre les deux
        const pendingFromMe = await this.db.collection('friendRequests')
            .where('fromUid', '==', uid)
            .where('toUid', '==', targetUid)
            .where('status', '==', 'pending')
            .get();
        const pendingToMe = await this.db.collection('friendRequests')
            .where('fromUid', '==', targetUid)
            .where('toUid', '==', uid)
            .where('status', '==', 'pending')
            .get();

        const deleteBatch = this.db.batch();
        pendingFromMe.docs.forEach((d: FirebaseFirestore.QueryDocumentSnapshot) => deleteBatch.delete(d.ref));
        pendingToMe.docs.forEach((d: FirebaseFirestore.QueryDocumentSnapshot) => deleteBatch.delete(d.ref));
        await deleteBatch.commit();
    }

    async unblockUser(uid: string, targetUid: string): Promise<void> {
        await this.db.collection('users').doc(uid).collection('blocked').doc(targetUid).delete();
    }

    async getBlockedUsers(uid: string): Promise<string[]> {
        const snap = await this.db.collection('users').doc(uid).collection('blocked').get();
        return snap.docs.map((d: FirebaseFirestore.QueryDocumentSnapshot) => d.id);
    }

    async isBlocked(uid: string, targetUid: string): Promise<boolean> {
        const doc = await this.db.collection('users').doc(uid).collection('blocked').doc(targetUid).get();
        return doc.exists;
    }

}

export const firestoreService = new FirestoreServiceClass();
