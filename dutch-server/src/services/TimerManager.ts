import { Room } from '../models/Room';

export interface TimerRoomAccess {
  getRoom(roomCode: string): Room | undefined;
  broadcastGameState(roomCode: string, updateType: string, data?: any): void;
  endReactionPhase(roomCode: string): Promise<void>;
}

export class TimerManager {
  private timers: Map<string, NodeJS.Timeout> = new Map();
  private endTimes: Map<string, number> = new Map();
  private lastBroadcastAt: Map<string, number> = new Map();
  private readonly graceMs = 200;

  constructor(private roomAccess: TimerRoomAccess) {}

  startReactionTimer(roomCode: string, durationMs: number) {
    this.clearTimer(roomCode);

    const room = this.roomAccess.getRoom(roomCode);
    if (!room || !room.gameState) return;

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

  clearTimer(roomCode: string) {
    const timer = this.timers.get(roomCode);
    if (timer) {
      clearInterval(timer);
      this.timers.delete(roomCode);
    }
    this.endTimes.delete(roomCode);
    this.lastBroadcastAt.delete(roomCode);
  }

  private endReaction(roomCode: string) {
    this.clearTimer(roomCode);
    void this.roomAccess.endReactionPhase(roomCode);
  }
}
