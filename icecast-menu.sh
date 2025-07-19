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

# Función para configurar debconf completamente no interactivo
configurar_debconf_no_interactivo() {
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/hostname string $HOSTNAME' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/syslog boolean false' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/use-syslog boolean false' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/admin-user string admin' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/admin-password password $ICECAST_ADMIN' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/admin-password-again password $ICECAST_ADMIN' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/source-password password $ICECAST_SOURCE' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/relay-password password $ICECAST_RELAY' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/setup boolean true' | debconf-set-selections"
  pct exec "$CTID" -- bash -c "echo 'icecast2 icecast2/start boolean true' | debconf-set-selections"
  
  # Configurar entorno para evitar diálogos
  pct exec "$CTID" -- bash -c "echo 'export DEBIAN_FRONTEND=noninteractive' >> /root/.bashrc"
  pct exec "$CTID" -- bash -c "echo 'export DEBIAN_FRONTEND=noninteractive' >> /etc/profile"
}

# Función para instalar icecast de forma completamente no interactiva
instalar_icecast_no_interactivo() {
  echo -e "${YELLOW}🔧 Configurando entorno no interactivo...${NC}"
  configurar_debconf_no_interactivo
  
  echo -e "${YELLOW}🔄 Actualizando paquetes...${NC}"
  pct exec "$CTID" -- env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  
  echo -e "${YELLOW}📦 Instalando Icecast2...${NC}"
  pct exec "$CTID" -- env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    icecast2
    
  echo -e "${YELLOW}🔧 Aplicando configuraciones...${NC}"
  pct exec "$CTID" -- sed -i "s|<source-password>.*</source-password>|<source-password>$ICECAST_SOURCE</source-password>|" /etc/icecast2/icecast.xml
  pct exec "$CTID" -- sed -i "s|<relay-password>.*</relay-password>|<relay-password>$ICECAST_RELAY</relay-password>|" /etc/icecast2/icecast.xml
  pct exec "$CTID" -- sed -i "s|<admin-password>.*</admin-password>|<admin-password>$ICECAST_ADMIN</admin-password>|" /etc/icecast2/icecast.xml
  
  echo -e "${YELLOW}🚀 Reiniciando Icecast...${NC}"
  pct exec "$CTID" -- systemctl restart icecast2
}

# [Resto de las funciones permanecen igual...]

# Ejecutar flujo
echo -e "${GREEN}🔧 Iniciando instalación y configuración de CT...${NC}"
leer_contraseñas
crear_ct
instalar_icecast_no_interactivo  # Cambiamos a la nueva función
mostrar_banner
