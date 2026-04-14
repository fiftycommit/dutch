"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const server_1 = require("./server");
void (0, server_1.startServer)().catch((error) => {
    console.error('Fatal server startup error:', error);
    process.exit(1);
});
//# sourceMappingURL=index.js.map