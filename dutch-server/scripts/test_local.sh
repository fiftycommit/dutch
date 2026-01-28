#!/bin/bash
echo "Building server..."
npm run build

echo "Starting server in background..."
PORT=3000 node dist/index.js > server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

echo "Waiting for server to start..."
sleep 5

echo "Running tests..."
SERVER_URL=http://localhost:3000 node test-server.js
TEST_EXIT_CODE=$?

echo "Stopping server..."
kill $SERVER_PID

echo "Tests finished with exit code $TEST_EXIT_CODE"
exit $TEST_EXIT_CODE
