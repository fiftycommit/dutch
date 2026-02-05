#!/bin/bash

set -e

SERVER_IP="$1"

if [ -z "$SERVER_IP" ]; then
  echo "Usage: ./scripts/stop-trainer-remote.sh <server_ip>"
  exit 1
fi

ssh root@$SERVER_IP "systemctl stop dutch-bot-trainer && systemctl status --no-pager dutch-bot-trainer"
