#!/bin/bash
# Alerta instantánea en Telegram al iniciar sesión interactiva mediante SSH

if [ -n "$SSH_CLIENT" ]; then
  IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
  FECHA=$(date '+%d/%m/%Y %H:%M:%S')

  /usr/local/bin/telegram-notify "🚨 <b>Acceso SSH Detectado</b>%0AUsuario: <code>$USER</code>%0AIP origen: <code>$IP</code>%0AFecha: $FECHA"
fi
