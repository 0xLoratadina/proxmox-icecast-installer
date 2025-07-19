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

# Función para leer contraseñas desde el usuario
function leer_contraseñas() {
  read -rsp $'🔐 Contraseña root del contenedor: \n' PASSWORD_ROOT
  echo
  read -rsp $'🔑 Contraseña admin Icecast: \n' ICECAST_ADMIN
  echo
  read -rsp $'🎙 Contraseña source Icecast: \n' ICECAST_SOURCE
  echo
  read -rsp $'🔁 Contraseña relay Icecast: \n' ICECAST_RELAY
  echo
}

# Función para configurar DEBCONF de manera no interactiva
function configurar_debconf() {
  pct exec "$CTID" -- bash -c "cat > /tmp/icecast-debconf <<EOF
icecast2 icecast2/hostname string $HOSTNAME
icecast2 icecast2/syslog boolean false
icecast2 icecast2/use-syslog boolean false
icecast2 icecast2/admin-user string admin
icecast2 icecast2/admin-password password $ICECAST_ADMIN
icecast2 icecast2/admin-password-again password $ICECAST_ADMIN
icecast2 icecast2/source-password password $ICECAST_SOURCE
icecast2 icecast2/relay-password password $ICECAST_RELAY
icecast2 icecast2/setup boolean true
icecast2 icecast2/start boolean true
EOF"
  
  pct exec "$CTID" -- debconf-set-selections /tmp/icecast-debconf
  pct exec "$CTID" -- rm /tmp/icecast-debconf
  
  # Configurar entorno completamente no interactivo
  pct exec "$CTID" -- bash -c "echo 'export DEBIAN_FRONTEND=noninteractive' >> /etc/environment"
  pct exec "$CTID" -- bash -c "echo 'export DEBIAN_PRIORITY=critical' >> /etc/environment"
  pct exec "$CTID" -- bash -c "echo 'export DEBCONF_NONINTERACTIVE_SEEN=true' >> /etc/environment"
}

# Función para encontrar el próximo CTID disponible
function encontrar_ctid_disponible() {
  local id=$BASE_CTID
  while pct list | awk '{print $1}' | grep -q "^${id}$"; do
    ((id++))
  done
  echo "$id"
}

# Crear CT
function crear_ct() {
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

# Función para instalar Icecast sin diálogos
function instalar_icecast_sin_dialogos() {
  echo -e "${YELLOW}🔧 Configurando entorno no interactivo...${NC}"
  configurar_debconf
  
  echo -e "${YELLOW}🔄 Actualizando paquetes...${NC}"
  pct exec "$CTID" -- env DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical \
    apt-get update -qq
  
  echo -e "${YELLOW}📦 Instalando Icecast2 (modo no interactivo)...${NC}"
  pct exec "$CTID" -- env DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical \
    apt-get install -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    icecast2
    
  # Configuración adicional para evitar futuros diálogos
  pct exec "$CTID" -- bash -c "echo 'icecast2 hold' | dpkg --set-selections"
  
  echo -e "${YELLOW}🔧 Aplicando configuraciones personalizadas...${NC}"
  pct exec "$CTID" -- sed -i "s|<source-password>.*</source-password>|<source-password>$ICECAST_SOURCE</source-password>|" /etc/icecast2/icecast.xml
  pct exec "$CTID" -- sed -i "s|<relay-password>.*</relay-password>|<relay-password>$ICECAST_RELAY</relay-password>|" /etc/icecast2/icecast.xml
  pct exec "$CTID" -- sed -i "s|<admin-password>.*</admin-password>|<admin-password>$ICECAST_ADMIN</admin-password>|" /etc/icecast2/icecast.xml
  
  echo -e "${YELLOW}🚀 Iniciando servicio Icecast...${NC}"
  pct exec "$CTID" -- systemctl enable --now icecast2
}

# Función para mostrar banner informativo
function mostrar_banner() {
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
${CYAN}===================================================
${NC}Para administrar Icecast: http://$ip:8000/admin
Credenciales:
  - Usuario admin: admin
  - Contraseña: ${ICECAST_ADMIN}
${CYAN}===================================================${NC}

EOF
}

# Ejecutar flujo principal
echo -e "${GREEN}🔧 Iniciando instalación y configuración de CT...${NC}"
leer_contraseñas
crear_ct
instalar_icecast_sin_dialogos
mostrar_banner
