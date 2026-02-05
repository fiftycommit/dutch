#!/bin/bash

set -e

SERVER_IP="$1"

if [ -z "$SERVER_IP" ]; then
  echo "Usage: ./scripts/start-trainer-remote.sh <server_ip>"
  exit 1
fi

ssh root@$SERVER_IP "systemctl restart dutch-bot-trainer && systemctl status --no-pager dutch-bot-trainer"
