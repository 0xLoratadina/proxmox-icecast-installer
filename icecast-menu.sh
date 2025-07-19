#!/usr/bin/env bash
set -euo pipefail

# Colores y estilos
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color

# Datos del contenedor
CTID=1000
HOSTNAME="icecastServer"
MEMORY="4096"
CORES="2"
DISK_SIZE="8G"
STORAGE="local-lvm"
TEMPLATE="debian-12-standard_12.2-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"

# Función principal para crear el CT
create_default_ct() {
  echo -e "${YELLOW}🔧 Iniciando instalación y configuración de CT...${NC}"

  # Verificar si el template ya está descargado
  if [[ ! -f "$TEMPLATE_PATH" ]]; then
    echo -e "${YELLOW}📥 Descargando plantilla Debian 12...${NC}"
    pveam update
    pveam download "$STORAGE" "$TEMPLATE"
  fi

  # Solicitar contraseña root para el contenedor
  echo -e ""
  read -s -p "🔐 Contraseña root del contenedor: " ROOT_PWD
  echo ""

  # Crear el contenedor
  echo -e "${YELLOW}🚧 Creando contenedor LXC...${NC}"
  pct create "$CTID" "$TEMPLATE_PATH" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --rootfs "$STORAGE:$DISK_SIZE" \
    --password "$ROOT_PWD" \
    --unprivileged 1 \
    --features nesting=1 \
    --tags "radio,cloud,ip"

  # Iniciar contenedor
  echo -e "${YELLOW}⚡ Iniciando CT...${NC}"
  pct start "$CTID"
  sleep 3

  # Instalar Icecast
  echo -e "${YELLOW}📦 Instalando Icecast2 dentro del contenedor...${NC}"
  pct exec "$CTID" -- apt update
  pct exec "$CTID" -- apt install -y icecast2

  # Solicitar contraseñas para Icecast
  echo -e ""
  read -p "🔑 Contraseña admin Icecast: " ADMIN_PWD
  read -p "🎙 Contraseña source Icecast: " SOURCE_PWD
  read -p "🔁 Contraseña relay Icecast: " RELAY_PWD

  CONFIG_PATH="/etc/icecast2/icecast.xml"
  pct exec "$CTID" -- sed -i "s/<admin-password>.*<\/admin-password>/<admin-password>$ADMIN_PWD<\/admin-password>/g" "$CONFIG_PATH"
  pct exec "$CTID" -- sed -i "s/<source-password>.*<\/source-password>/<source-password>$SOURCE_PWD<\/source-password>/g" "$CONFIG_PATH"
  pct exec "$CTID" -- sed -i "s/<relay-password>.*<\/relay-password>/<relay-password>$RELAY_PWD<\/relay-password>/g" "$CONFIG_PATH"
  pct exec "$CTID" -- systemctl restart icecast2

  IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
  echo ""
  echo -e "${GREEN}✅ Icecast instalado y disponible en: http://${IP}:8000 ${NC}"
}

# Menú interactivo tipo whiptail
show_menu() {
  while true; do
    OPTION=$(whiptail --title "Icecast Installer for Proxmox" --menu "Selecciona una opción:" 15 50 4 \
      "1" "Crear CT con configuración por defecto" \
      "0" "Salir" 3>&1 1>&2 2>&3)

    case $OPTION in
      1) create_default_ct ;;
      0) clear; exit ;;
      *) echo "Opción inválida" ;;
    esac
  done
}

# Verifica si se está ejecutando en Proxmox
if ! command -v pveversion >/dev/null; then
  echo -e "${RED}❌ Este script debe ejecutarse en un nodo Proxmox.${NC}"
  exit 1
fi

# Iniciar menú
show_menu
