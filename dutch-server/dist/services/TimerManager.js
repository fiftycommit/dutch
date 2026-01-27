"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TimerManager = void 0;
class TimerManager {
    constructor(roomAccess) {
        this.roomAccess = roomAccess;
        this.timers = new Map();
        this.endTimes = new Map();
        this.lastBroadcastAt = new Map();
        this.graceMs = 200;
    }
    startReactionTimer(roomCode, durationMs) {
        this.clearTimer(roomCode);
        const room = this.roomAccess.getRoom(roomCode);
        if (!room || !room.gameState)
            return;
        const startTime = Date.now();
        const endTime = startTime + durationMs;
        this.endTimes.set(roomCode, endTime);
        this.lastBroadcastAt.set(roomCode, 0);
        room.gameState.reactionTimeRemaining = durationMs;
        room.gameState.reactionStartTime = new Date(startTime);
        const timer = setInterval(() => {
            const currentRoom = this.roomAccess.getRoom(roomCode);
            if (!currentRoom || !currentRoom.gameState) {
                this.clearTimer(roomCode);
                return;
            }
            const end = this.endTimes.get(roomCode);
            if (end === undefined) {
                this.clearTimer(roomCode);
                return;
            }
            const now = Date.now();
            const remaining = Math.max(0, end - now);
            currentRoom.gameState.reactionTimeRemaining = remaining;
            const lastBroadcast = this.lastBroadcastAt.get(roomCode) ?? 0;
            if (now - lastBroadcast >= 200) {
                this.lastBroadcastAt.set(roomCode, now);
                this.roomAccess.broadcastGameState(roomCode, 'TIMER_UPDATE', {
                    reactionTimeRemaining: remaining,
                });
            }
            if (now >= end + this.graceMs) {
                this.endReaction(roomCode);
            }
        }, 50);
        this.timers.set(roomCode, timer);
    }
    clearTimer(roomCode) {
        const timer = this.timers.get(roomCode);
        if (timer) {
            clearInterval(timer);
            this.timers.delete(roomCode);
        }
        this.endTimes.delete(roomCode);
        this.lastBroadcastAt.delete(roomCode);
    }
    endReaction(roomCode) {
        this.clearTimer(roomCode);
        void this.roomAccess.endReactionPhase(roomCode);
    }
}
exports.TimerManager = TimerManager;
