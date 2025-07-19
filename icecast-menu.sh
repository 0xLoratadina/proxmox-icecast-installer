#!/bin/bash

# ═══════════════════════════════════════════
#      Proxmox Helper Script - Icecast CT
# ═══════════════════════════════════════════

CTID=1000
HOSTNAME="icecastServer"
MEMORY="4096"
CPUS="2"
DISK_SIZE="8G"
STORAGE="local-lvm"
TEMPLATE="debian-12-standard_12.0-1_amd64.tar.zst"
BRIDGE="vmbr0"
TAGS="radio,cloud,ip"

# Función para instalar Icecast
install_icecast() {
  echo "🔧 Iniciando instalación y configuración de CT..."

  # Descargar plantilla si no existe
  if ! pveam list local | grep -q "$TEMPLATE"; then
    echo "📥 Descargando plantilla Debian 12..."
    pveam update && pveam download local $TEMPLATE
  fi

  # Pedir contraseña para el CT
  read -rsp "🔐 Contraseña root del contenedor: " CT_PASSWORD
  echo

  # Crear CT
  pct create $CTID local:vztmpl/$TEMPLATE \
    --hostname $HOSTNAME \
    --cores $CPUS \
    --memory $MEMORY \
    --rootfs $STORAGE:$DISK_SIZE \
    --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
    --ostype debian \
    --password $CT_PASSWORD \
    --unprivileged 1 \
    --features nesting=1 \
    --tags "$TAGS"

  echo "⚡ Iniciando CT..."
  pct start $CTID
  sleep 5

  echo "📦 Instalando Icecast2..."
  pct exec $CTID -- bash -c "apt update && apt install -y icecast2"

  # Pedir contraseñas para Icecast
  echo
  read -rsp "🔑 Contraseña admin Icecast: " ADMIN_PASS
  echo
  read -rsp "🎙 Contraseña source Icecast: " SOURCE_PASS
  echo
  read -rsp "🔁 Contraseña relay Icecast: " RELAY_PASS
  echo

  # Aplicar configuración en icecast.xml
  pct exec $CTID -- bash -c "
    cp /etc/icecast2/icecast.xml /etc/icecast2/icecast.xml.bak && \
    sed -i \"s|<admin-password>.*</admin-password>|<admin-password>$ADMIN_PASS</admin-password>|\" /etc/icecast2/icecast.xml && \
    sed -i \"s|<source-password>.*</source-password>|<source-password>$SOURCE_PASS</source-password>|\" /etc/icecast2/icecast.xml && \
    sed -i \"s|<relay-password>.*</relay-password>|<relay-password>$RELAY_PASS</relay-password>|\" /etc/icecast2/icecast.xml && \
    systemctl restart icecast2
  "

  # Mostrar IP
  CT_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
  echo -e "\n✅ Icecast instalado y disponible en: http://$CT_IP:8000"
}

# Menú estilo TUI
while true; do
  OPTION=$(whiptail --title "Proxmox Icecast Helper" --menu "Choose an option:" 15 60 4 \
    "1" "Default Settings" \
    "2" "Exit" 3>&1 1>&2 2>&3)

  exitstatus=$?
  if [ $exitstatus != 0 ]; then
    echo -e "\n❌ Menú cancelado. Saliendo del script.\n"
    exit 1
  fi

  case $OPTION in
    1)
      install_icecast
      exit 0
      ;;
    2)
      echo -e "\n👋 Saliendo del script.\n"
      exit 0
      ;;
  esac
done
