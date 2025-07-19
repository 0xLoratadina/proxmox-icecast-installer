#!/usr/bin/env bash
set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuración
BASE_CTID=1000
HOSTNAME="radio-server"
MEMORY=4096
STORAGE="local-lvm"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
PASSWORD_ROOT=""
ICECAST_ADMIN=""
ICECAST_SOURCE=""
ICECAST_RELAY=""

# Función para configurar debconf no interactivo
configurar_debconf() {
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/admin-password password $ICECAST_ADMIN' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/admin-password-again password $ICECAST_ADMIN' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/source-password password $ICECAST_SOURCE' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/relay-password password $ICECAST_RELAY' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/hostname string $HOSTNAME' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/syslog boolean false' | debconf-set-selections"
}

# Función para mostrar banner informativo
mostrar_banner() {
  local ip=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
  cat <<EOF

${CYAN}===================================================
               SERVIDOR DE RADIO ICECAST
===================================================
${GREEN}Nombre del servidor:${NC} $HOSTNAME
${GREEN}Dirección IP:${NC}       $ip
${GREEN}Puerto:${NC}            8000
${GREEN}URL de acceso:${NC}     http://$ip:8000
${GREEN}Estado Icecast:${NC}    $(pct exec "$CTID" -- systemctl is-active icecast2)
${GREEN}Uso memoria:${NC}      $(pct exec "$CTID" -- free -m | awk '/Mem/{print $3"MB de "$2"MB"}')
${GREEN}Uso almacenamiento:${NC} $(pct exec "$CTID" -- df -h / | awk 'NR==2{print $3" de "$2}')
${CYAN}===================================================
${NC}Para administrar Icecast: http://$ip:8000/admin
Credenciales:
  - Usuario admin: admin
  - Contraseña: ${ICECAST_ADMIN}
${CYAN}===================================================${NC}

EOF
}

# Función para configurar el mensaje de inicio
configurar_motd() {
  pct exec "$CTID" -- bash -c "cat > /etc/update-motd.d/01-icecast-info <<'EOL'
#!/bin/sh
echo \"\"
echo \"===================================================\"
echo \"             SERVIDOR DE RADIO ICECAST\"
echo \"===================================================\"
echo \"Nombre del servidor: \$(hostname)\"
echo \"Dirección IP:       \$(hostname -I | awk '{print \$1}')\"
echo \"Puerto:             8000\"
echo \"URL de acceso:     http://\$(hostname -I | awk '{print \$1}'):8000\"
echo \"Estado Icecast:    \$(systemctl is-active icecast2)\"
echo \"Uso memoria:      \$(free -m | awk '/Mem/{print \$3\"MB de \"\$2\"MB\"}')\"
echo \"Uso almacenamiento: \$(df -h / | awk 'NR==2{print \$3\" de \"\$2}')\"
echo \"===================================================\"
echo \"Para administrar Icecast: http://\$(hostname -I | awk '{print \$1}'):8000/admin\"
echo \"===================================================\"
echo \"\"
EOL"
  
  pct exec "$CTID" -- chmod +x /etc/update-motd.d/01-icecast-info
  pct exec "$CTID" -- bash -c "echo '[[ -f /etc/update-motd.d/01-icecast-info ]] && /etc/update-motd.d/01-icecast-info' >> /root/.bashrc"
  pct exec "$CTID" -- bash -c "echo '[[ -f /etc/update-motd.d/01-icecast-info ]] && /etc/update-motd.d/01-icecast-info' >> /etc/skel/.bashrc"
  
  # Deshabilitar mensajes de locale
  pct exec "$CTID" -- bash -c "echo 'export LC_ALL=C' >> /etc/profile"
  pct exec "$CTID" -- bash -c "echo 'export LANG=C' >> /etc/profile"
}

# Función para encontrar el próximo CTID disponible
encontrar_ctid_disponible() {
  local id=$BASE_CTID
  while pct list | awk '{print $1}' | grep -q "^${id}$"; do
    ((id++))
  done
  echo "$id"
}

# Función para leer contraseñas desde el usuario
leer_contraseñas() {
  read -rsp $'🔐 Contraseña root del contenedor: \n' PASSWORD_ROOT
  echo
  read -rsp $'🔑 Contraseña admin Icecast: \n' ICECAST_ADMIN
  echo
  read -rsp $'🎙 Contraseña source Icecast: \n' ICECAST_SOURCE
  echo
  read -rsp $'🔁 Contraseña relay Icecast: \n' ICECAST_RELAY
  echo
}

# Crear CT
crear_ct() {
  CTID=$(encontrar_ctid_disponible)
  
  echo -e "${YELLOW}📥 Verificando plantilla Debian 12...${NC}"
  pveam update
  if ! pveam list local | grep -q "$TEMPLATE"; then
    echo -e "${YELLOW}⬇️ Descargando plantilla $TEMPLATE...${NC}"
    pveam download local "$TEMPLATE"
  fi

  echo -e "${YELLOW}📦 Creando contenedor LXC (ID: $CTID)...${NC}"
  pct create "$CTID" "local:vztmpl/$TEMPLATE" \
    --storage "$STORAGE" \
    --hostname "$HOSTNAME" \
    --memory "$MEMORY" \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --ostype debian \
    --password "$PASSWORD_ROOT" \
    --unprivileged 1 \
    --tags "radio,cloud,ip" \
    --features nesting=1

  echo -e "${GREEN}⚡ Iniciando CT...${NC}"
  pct start "$CTID"
  
  # Esperar a que el contenedor esté listo
  echo -e "${YELLOW}⏳ Esperando a que el contenedor esté listo...${NC}"
  while ! pct exec "$CTID" -- true 2>/dev/null; do
    sleep 1
  done
}

# Instalar Icecast en el CT
instalar_icecast() {
  echo -e "${YELLOW}📦 Configurando entorno no interactivo...${NC}"
  configurar_debconf
  
  # Configurar locale para evitar advertencias
  pct exec "$CTID" -- bash -c "echo 'LC_ALL=C' >> /etc/environment"
  pct exec "$CTID" -- bash -c "echo 'LANG=C' >> /etc/environment"
  
  echo -e "${YELLOW}🔄 Actualizando paquetes...${NC}"
  pct exec "$CTID" -- env DEBIAN_FRONTEND=noninteractive apt update -qq
  
  echo -e "${YELLOW}📦 Instalando Icecast2...${NC}"
  pct exec "$CTID" -- env DEBIAN_FRONTEND=noninteractive apt install -y -qq icecast2
  
  echo -e "${YELLOW}🔧 Configurando Icecast...${NC}"
  pct exec "$CTID" -- sed -i "s|<source-password>.*</source-password>|<source-password>$ICECAST_SOURCE</source-password>|" /etc/icecast2/icecast.xml
  pct exec "$CTID" -- sed -i "s|<relay-password>.*</relay-password>|<relay-password>$ICECAST_RELAY</relay-password>|" /etc/icecast2/icecast.xml
  pct exec "$CTID" -- sed -i "s|<admin-password>.*</admin-password>|<admin-password>$ICECAST_ADMIN</admin-password>|" /etc/icecast2/icecast.xml

  echo -e "${YELLOW}🖥️ Configurando mensaje de inicio...${NC}"
  configurar_motd

  echo -e "${YELLOW}🚀 Iniciando servicio Icecast...${NC}"
  pct exec "$CTID" -- systemctl enable icecast2
  pct exec "$CTID" -- systemctl restart icecast2

  echo -e "${GREEN}✅ Icecast instalado correctamente${NC}"
  mostrar_banner
}

# Ejecutar flujo
echo -e "${GREEN}🔧 Iniciando instalación y configuración de CT...${NC}"
leer_contraseñas
crear_ct
instalar_icecast
