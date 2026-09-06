#!/bin/bash
TOKEN="<TELEGRAM_BOT_TOKEN>"
CHAT_ID="<TELEGRAM_CHAT_ID>"
MENSAJE="$1"

if [ -n "$MENSAJE" ]; then
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
       -d "chat_id=${CHAT_ID}" \
       -d "text=${MENSAJE}" \
       -d "parse_mode=HTML" > /dev/null
fi
