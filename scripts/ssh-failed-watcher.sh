#!/bin/bash
# Monitor continuo del journal de OpenSSH para alertar intentos fallidos a Telegram

journalctl -u ssh -f -n 0 | while read -r line; do
  if echo "$line" | grep -E -q "Failed password|Invalid user"; then
    IP=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
    USER_TRY=$(echo "$line" | sed -n -e 's/.*Invalid user \([^ ]*\).*/\1/p' -e 's/.*Failed password for \([^ ]*\).*/\1/p')
    FECHA=$(date '+%d/%m/%Y %H:%M:%S')

    /usr/local/bin/telegram-notify "⚠️ <b>Intento SSH Fallido</b>%0AUsuario probado: <code>${USER_TRY:-desconocido}</code>%0AIP origen: <code>$IP</code>%0AFecha: $FECHA"
  fi
done
