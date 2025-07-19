#!/usr/bin/env bash
set -euo pipefail

# Colores
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'

# Configuración
CTID=1000
HOSTNAME="radio-server"
MEMORY=4096
STORAGE="local"  # cambia a local-lvm si usas ese
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
PASSWORD_ROOT=""
ICECAST_ADMIN=""
ICECAST_SOURCE=""
ICECAST_RELAY=""

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
  echo -e "${YELLOW}📥 Verificando plantilla Debian 12...${NC}"
  pveam update
  if [ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ]; then
    echo -e "${YELLOW}⬇️ Descargando plantilla $TEMPLATE...${NC}"
    pveam download "$STORAGE" "debian-12-standard"
  fi

  echo -e "${YELLOW}📦 Creando contenedor LXC...${NC}"
  pct create "$CTID" "local:vztmpl/$TEMPLATE" \
    -hostname "$HOSTNAME" \
    -memory "$MEMORY" \
    -net0 name=eth0,bridge=vmbr0,ip=dhcp \
    -ostype debian \
    -password "$PASSWORD_ROOT" \
    -unprivileged 1 \
    -tags "radio,cloud,ip" \
    -features nesting=1

  echo -e "${GREEN}⚡ Iniciando CT...${NC}"
  pct start "$CTID"
}

# Instalar Icecast en el CT
instalar_icecast() {
  echo -e "${YELLOW}📦 Instalando Icecast2...${NC}"
  pct exec "$CTID" -- apt update
  pct exec "$CTID" -- apt install -y icecast2

  echo -e "${YELLOW}🔧 Configurando Icecast...${NC}"
  CONFIG="/etc/icecast2/icecast.xml"

  pct exec "$CTID" -- bash -c "sed -i 's|<source-password>.*</source-password>|<source-password>$ICECAST_SOURCE</source-password>|' $CONFIG"
  pct exec "$CTID" -- bash -c "sed -i 's|<relay-password>.*</relay-password>|<relay-password>$ICECAST_RELAY</relay-password>|' $CONFIG"
  pct exec "$CTID" -- bash -c "sed -i 's|<admin-password>.*</admin-password>|<admin-password>$ICECAST_ADMIN</admin-password>|' $CONFIG"

  pct exec "$CTID" -- systemctl enable icecast2
  pct exec "$CTID" -- systemctl restart icecast2

  echo -e "${GREEN}✅ Icecast instalado y disponible en: http://$(pct exec "$CTID" -- hostname -I | awk '{print $1}'):8000${NC}"
}

# Ejecutar flujo
echo -e "${GREEN}🔧 Iniciando instalación y configuración de CT...${NC}"
leer_contraseñas
crear_ct
instalar_icecast
