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

# Función robusta para leer credenciales
leer_credenciales() {
  echo -e "${YELLOW}Por favor ingrese las siguientes credenciales:${NC}"
  
  declare -g PASSWORD_ROOT ICECAST_ADMIN ICECAST_SOURCE ICECAST_RELAY
  
  while [ -z "$PASSWORD_ROOT" ]; do
    read -rsp "🔐 Contraseña root del contenedor: " PASSWORD_ROOT
    echo
    [ -z "$PASSWORD_ROOT" ] && echo -e "${RED}Error: La contraseña no puede estar vacía${NC}"
  done
  
  while [ -z "$ICECAST_ADMIN" ]; do
    read -rsp "🔑 Contraseña admin Icecast: " ICECAST_ADMIN
    echo
    [ -z "$ICECAST_ADMIN" ] && echo -e "${RED}Error: La contraseña no puede estar vacía${NC}"
  done
  
  while [ -z "$ICECAST_SOURCE" ]; do
    read -rsp "🎙 Contraseña source Icecast: " ICECAST_SOURCE
    echo
    [ -z "$ICECAST_SOURCE" ] && echo -e "${RED}Error: La contraseña no puede estar vacía${NC}"
  done
  
  while [ -z "$ICECAST_RELAY" ]; do
    read -rsp "🔁 Contraseña relay Icecast: " ICECAST_RELAY
    echo
    [ -z "$ICECAST_RELAY" ] && echo -e "${RED}Error: La contraseña no puede estar vacía${NC}"
  done
}

# [Aquí irían todas las demás funciones necesarias...]

# Flujo principal
main() {
  echo -e "${GREEN}🔧 Iniciando instalación y configuración de CT...${NC}"
  leer_credenciales
  
  # Verificar comandos necesarios
  for cmd in pveam pct; do
    if ! command -v $cmd &>/dev/null; then
      echo -e "${RED}Error: El comando $cmd no está disponible${NC}"
      exit 1
    fi
  done
  
  # Continuar con la instalación...
  # [Aquí irían las llamadas a las demás funciones]
}

# Ejecutar solo si se invoca directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
