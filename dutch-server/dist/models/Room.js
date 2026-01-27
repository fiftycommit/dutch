"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RoomStatus = void 0;
exports.createRoom = createRoom;
var RoomStatus;
(function (RoomStatus) {
    RoomStatus["waiting"] = "waiting";
    RoomStatus["playing"] = "playing";
    RoomStatus["ended"] = "ended";
})(RoomStatus || (exports.RoomStatus = RoomStatus = {}));
function createRoom(id, hostPlayerId, settings, expiresAt) {
    return {
        id,
        hostPlayerId,
        settings,
        gameMode: settings.gameMode,
        players: [],
        gameState: null,
        status: RoomStatus.waiting,
        createdAt: new Date(),
        lastActivityAt: Date.now(),
        expiresAt,
        tournamentRound: 1,
    };
}
