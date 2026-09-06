# Homelab Sentinel: Monitorización, Alertas en Tiempo Real y Hardening para Raspberry Pi

## 1. Resumen Ejecutivo y Alcance

Este proyecto documenta el diseño, fortificación (*hardening*) e implementación de un ecosistema de monitorización proactiva y seguridad perimetral para un nodo doméstico basado en **Raspberry Pi 4B**. El propósito central es garantizar la operatividad continua, trazabilidad inmediata de eventos de red y resistencia frente a vectores de ataque por fuerza bruta o accesos no autorizados, permitiendo una gestión desatendida y segura.

El sistema canaliza telemetría crítica e incidentes de seguridad en tiempo real hacia un bot privado de **Telegram**, integrando monitorización pasiva a nivel de kernel/servicios y monitorización activa de conectividad local e Internet mediante contenedores Docker.

---

## 2. Arquitectura del Sistema
```text
              ┌────────────────────────────────────────────────────────┐
              │                 Dispositivos Cliente                   │
              │   (Mac Air / PC Sobremesa / Google Pixel 10 Pro)       │
              └───────────────────────────┬────────────────────────────┘
                                          │ SSH (Claves Ed25519)
                                          ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                             Raspberry Pi 4B                                          │
│                                                                                      │
│  ┌──────────────────────┐  ┌─────────────────────┐  ┌─────────────────┐              │
│  │   ssh-failed-watcher │  │   ssh-login-alert   │  │  systemd boot   │              │
│  │    (journalctl log)  │  │  (/etc/profile.d)   │  │ (systemd unit)  │              │
│  └──────────┬───────────┘  └──────────┬──────────┘  └────────┬────────┘              │
│             │                         │                      │                       │
│             └──────────────────┬──────┴──────────────────────┘                       │
│                                │                                                     │
│  ┌──────────────────────┐      ▼                                                     │
│  │  Fail2ban Intrusion  │──▶ telegram-notify ──┐                                     │
│  │  (iptables jail/ban) │    (/usr/local/bin)  │                                     │
│  └──────────────────────┘                      │                                     │
│                                                │                                     │
│  ┌──────────────────────────────────────────┐  │                                     │
│  │  Docker: Uptime Kuma Engine              │  │                                     │
│  │  - ICMP Ping (PC Sobremesa / Gateway)    │──┼───────────────────────────┐         │
│  │  - DNS Probe (Local Pi-hole port 53)     │  │                           │         │
│  └──────────────────────────────────────────┘  │                           │         │
│                                                │                           │         │
│                                                │                           │         │
│                                                │      HTTPS POST API       │         │
│                                                ▼                           ▼         │
│                                          ┌────────────────────────────────────────┐  │
│                                          │        Telegram Bot API / Chat         │  │
│                                          │         Notificaciones Push            │  │
│                                          └────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────┘
---

## 3. Matriz de Componentes y Stack Tecnológico

| Componente | Rol / Función | Justificación Técnica |
| :--- | :--- | :--- |
| **OpenSSH Server** | Acceso remoto y administración | Cifrado asimétrico `Ed25519`, desactivación total de contraseñas (`PasswordAuthentication no`). |
| **Telegram Bot API** | Canal de alerta omnicanal | Push notifications instantáneas sin dependencia de brokers MQTT o apps de terceros propietarias. |
| **Fail2ban** | Detección y bloqueo reactivo | Monitorización de registros de autenticación y aplicación dinámica de bloqueos en Netfilter/iptables. |
| **Watcher Bash Daemon** | Detección proactiva a nivel evento | Lectura continua en stream (`journalctl -u ssh -f`) de intentos fallidos antes del umbral de ban. |
| **Systemd Services** | Automatización y persistencia | Gestión del ciclo de vida de los scripts vigilantes y alerta tras rearranque o cortes de alimentación. |
| **Docker Engine** | Entorno de virtualización ligera | Aislamiento del monitor de estado sin ensuciar las dependencias base de la distribución. |
| **Uptime Kuma** | Monitorización continua de red | Sondas ICMP/DNS de baja sobrecarga con alertas directas integradas vía webhook Telegram. |

---

## 4. Implementación Técnica Paso a Paso

### 4.1. Hardening Criptográfico SSH (Claves Ed25519)

Se descarta el uso tradicional de contraseñas para erradicar ataques de fuerza bruta y diccionarios automatizados:

1. **Generación de pares de claves asimétricas en clientes:**
   ```bash
   ssh-keygen -t ed25519 -C "alvaro-dispositivo"
   ```
2. **Despliegue de la clave pública en el servidor (`~/.ssh/authorized_keys`):**
   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... alvaro-dispositivo" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```
3. **Bloqueo en `/etc/ssh/sshd_config`:**
   ```ini
   PubkeyAuthentication yes
   PasswordAuthentication no
   PermitEmptyPasswords no
   X11Forwarding no
   ```
4. **Reinicio seguro tras comprobación de sintaxis:**
   ```bash
   sudo sshd -t && sudo systemctl restart ssh
   ```

---

### 4.2. Conector Central de Notificaciones (`telegram-notify`)

Script modular en `/usr/local/bin/telegram-notify` con permisos `755`:

```bash
#!/bin/bash
TOKEN="<TELEGRAM_BOT_TOKEN>"
CHAT_ID="<TELEGRAM_CHAT_ID>"
MENSAJE="$1"

if [ -n "$MENSAJE" ]; then
  curl -s -X POST "[https://api.telegram.org/bot$](https://api.telegram.org/bot$){TOKEN}/sendMessage" \
       -d "chat_id=${CHAT_ID}" \
       -d "text=${MENSAJE}" \
       -d "parse_mode=HTML" > /dev/null
fi
```

---

### 4.3. Notificación de Sesiones SSH Exitosas

Ubicado en `/etc/profile.d/ssh-telegram-alert.sh` para interceptar toda sesión interactiva abierta:

```bash
if [ -n "$SSH_CLIENT" ]; then
  IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
  FECHA=$(date '+%d/%m/%Y %H:%M:%S')
  /usr/local/bin/telegram-notify "🚨 <b>Acceso SSH Detectado</b>%0AUsuario: <code>$USER</code>%0AIP origen: <code>$IP</code>\%0AFecha:$FECHA"
fi
```

---

### 4.4. Centinela de Intentos de Acceso Fallidos (`ssh-failed-watcher`)

Servicio en streaming para interceptar contraseñas incorrectas o usuarios inexistentes en tiempo real:

* **Script ejecutable (`/usr/local/bin/ssh-failed-watcher.sh`):**
  ```bash
  #!/bin/bash
  journalctl -u ssh -f -n 0 | while read -r line; do
    if echo "$line" | grep -E -q "Failed password|Invalid user"; then
      IP=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
      USER_TRY=$(echo "$line" | sed -n -e 's/.*Invalid user \([^ ]*\).*/\1/p' -e 's/.*Failed password for \([^ ]*\).*/\1/p')
      FECHA=$(date '+%d/%m/%Y %H:%M:%S')

      /usr/local/bin/telegram-notify "⚠️ <b>Intento SSH Fallido</b>%0AUsuario probado: <code>${USER_TRY:-desconocido}</code>%0AIP origen: <code>$IP</code>\%0AFecha:$FECHA"
    fi
  done

---

### 4.5. Alerta de Rearranque del Sistema (Cortes de Luz / Reboots)

Unidad Systemd de tipo oneshot (/etc/systemd/system/telegram-boot.service) disparada tras confirmar enlace de red:
Ini, TOML
[Unit]
Description=Notificación de Arranque de Sistema por Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/telegram-notify "🟢 <b>Raspberry Pi Operativa</b>%0AEl sistema ha completado el arranque y la red está en línea."

[Install]
WantedBy=multi-user.target
```

---

### 4.6. Integración de Fail2ban con Telegram

1. **Acción de bloqueo (`/etc/fail2ban/action.d/telegram.conf`):**
   ```ini
   [Definition]
   actionban = /usr/local/bin/telegram-notify "⛔ <b>Fail2ban: IP Bloqueada</b>%0ASe ha baneado la IP: <code><ip></code> tras reiterados intentos fallidos contra <b><name></b>."
   ```
2. **Jail SSH en `/etc/fail2ban/jail.local`:**
   ```ini
   [DEFAULT]
   bantime  = 1h
   findtime = 10m
   maxretry = 5

   [sshd]
   enabled = true
   port    = ssh
   logpath = %(sshd_log)s
   backend = %(syslog_backend)s
   action  = %(action_)s
             telegram
   ```

---

### 4.7. Monitorización Continua con Uptime Kuma en Docker

Despliegue contenerizado y persistente:

```bash
docker run -d \
  --name uptime-kuma \
  --restart always \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  louislam/uptime-kuma:1
```

* **Sondas configuradas:**
  * **PC Sobremesa:** Monitor ICMP Ping cada 60 s hacia la IP interna de la LAN.
  * **DNS / Pi-hole:** Sonda DNS hacia `127.0.0.1:53` verificando resolución de dominios en tiempo y forma.
  * **Internet Gateway / WAN:** Monitor ICMP Ping hacia `1.1.1.1` para detección de caídas de fibra o corte de ISP.
* **Canal de alerta:** Webhook nativo a la API de Telegram con el mismo bot y chat ID.

---

## 5. Pruebas de Validación y Verificación

| Escenario de Prueba | Acción Ejecutada | Resultado Esperado en Telegram | Estado |
| :--- | :--- | :--- | :---: |
| **Inicio de Sesión Autorizado** | Conexión SSH con clave Ed25519 desde Mac/PC | Mensaje con usuario, IP origen y timestamp exacto | ✅ Superado |
| **Ataque / Error de Contraseña** | `ssh baduser@<ip_servidor>` con credenciales erróneas | Alerta instantánea reflejando usuario probado e IP | ✅ Superado |
| **Fuerza Bruta Persistente** | 5 intentos erróneos consecutivos | Notificación de ban de Fail2ban + IP aislada en iptables | ✅ Superado |
| **Reinicio / Corte Eléctrico** | Ejecución de `sudo reboot` | Mensaje de arranque en cuanto la red sincroniza | ✅ Superado |
| **Caída de Host / Servicio** | Apagado de equipo sobremesa o desconexión DNS | Notificación Push de caída emitida por Uptime Kuma | ✅ Superado |

---

## 6. Consideraciones de Seguridad y Buenas Prácticas

1. **Gestión de Secretos:** El archivo `/usr/local/bin/telegram-notify` contiene el token del bot; debe pertenecer a `root:root` con permisos `700` o `750` para evitar lecturas por usuarios sin privilegios.
2. **Rotación y Auditoría de Claves:** Para dar de baja un cliente comprometido o extraviado, basta con eliminar su línea en `~/.ssh/authorized_keys`.
3. **Huella Criptográfica:** Cada clave pública autorizada puede ser verificada mediante su huella digital ejecutando:
   ```bash
   ssh-keygen -l -f ~/.ssh/authorized_keys
   ```

---

## 7. Licencia y Autoría

* **Autor:** Proyecto Personal de Seguridad y Administración de Sistemas
* **Licencia:** MIT License
