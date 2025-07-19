#!/usr/bin/env bash
set -eo pipefail

# Verificar si estamos en Proxmox
if ! command -v pveversion &>/dev/null; then
    echo "Este script debe ejecutarse en un servidor Proxmox VE"
    exit 1
fi

# Instalar whiptail si no está presente
if ! command -v whiptail &>/dev/null; then
    apt-get update && apt-get install -y whiptail
fi

# Configuración inicial
CTID=1000
HOSTNAME="radio-server"
MEMORY=4096
STORAGE="local-lvm"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"

# Obtener credenciales mediante interfaz gráfica
credenciales() {
    PASSWORD_ROOT=$(whiptail --passwordbox "Contraseña root del contenedor:" 8 40 --title "Configuración del Contenedor" 3>&1 1>&2 2>&3)
    ICECAST_ADMIN=$(whiptail --passwordbox "Contraseña admin para Icecast:" 8 40 --title "Configuración de Icecast" 3>&1 1>&2 2>&3)
    ICECAST_SOURCE=$(whiptail --passwordbox "Contraseña source para Icecast:" 8 40 --title "Configuración de Icecast" 3>&1 1>&2 2>&3)
    ICECAST_RELAY=$(whiptail --passwordbox "Contraseña relay para Icecast:" 8 40 --title "Configuración de Icecast" 3>&1 1>&2 2>&3)
    
    # Verificar que se ingresaron todas las contraseñas
    if [[ -z "$PASSWORD_ROOT" || -z "$ICECAST_ADMIN" || -z "$ICECAST_SOURCE" || -z "$ICECAST_RELAY" ]]; then
        whiptail --title "Error" --msgbox "Todas las contraseñas son requeridas" 8 40
        exit 1
    fi
}

# Crear el contenedor
crear_ct() {
    echo "📦 Creando contenedor LXC..."
    pct create $CTID "local:vztmpl/$TEMPLATE" \
        --storage $STORAGE \
        --hostname $HOSTNAME \
        --memory $MEMORY \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --ostype debian \
        --password "$PASSWORD_ROOT" \
        --unprivileged 1 \
        --features nesting=1
    
    echo "⚡ Iniciando contenedor..."
    pct start $CTID
    sleep 5  # Esperar a que el contenedor esté listo
}

# Instalar y configurar Icecast
configurar_icecast() {
    echo "🔧 Configurando Icecast..."
    pct exec $CTID -- bash -c "echo 'icecast2 icecast2/admin-password password $ICECAST_ADMIN' | debconf-set-selections"
    pct exec $CTID -- bash -c "echo 'icecast2 icecast2/source-password password $ICECAST_SOURCE' | debconf-set-selections"
    pct exec $CTID -- bash -c "echo 'icecast2 icecast2/relay-password password $ICECAST_RELAY' | debconf-set-selections"
    
    pct exec $CTID -- apt-get update
    pct exec $CTID -- apt-get install -y icecast2
    
    # Configuración adicional
    pct exec $CTID -- sed -i "s|<source-password>.*</source-password>|<source-password>$ICECAST_SOURCE</source-password>|" /etc/icecast2/icecast.xml
    pct exec $CTID -- sed -i "s|<relay-password>.*</relay-password>|<relay-password>$ICECAST_RELAY</relay-password>|" /etc/icecast2/icecast.xml
    pct exec $CTID -- sed -i "s|<admin-password>.*</admin-password>|<admin-password>$ICECAST_ADMIN</admin-password>|" /etc/icecast2/icecast.xml
    
    pct exec $CTID -- systemctl restart icecast2
}

# Configurar mensaje de inicio en el CT
configurar_motd() {
    echo "🖥️ Configurando mensaje de inicio en el contenedor..."
    pct exec $CTID -- bash -c "cat > /etc/motd <<EOF
=============================================
       SERVIDOR DE RADIO ICECAST
=============================================
Hostname: $(hostname)
IP: \$(hostname -I | awk '{print \$1}')
Puerto Icecast: 8000
URL Admin: http://\$(hostname -I | awk '{print \$1}'):8000/admin
Usuario Admin: admin
=============================================
EOF"
    
    # Mostrar info al hacer login via SSH
    pct exec $CTID -- bash -c "echo 'echo \"\$(cat /etc/motd)\"' >> /etc/profile"
}

# Mostrar resumen final
mostrar_resumen() {
    IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
    clear
    echo "============================================="
    echo "     INSTALACIÓN COMPLETADA EXITOSAMENTE"
    echo "============================================="
    echo "Contenedor ID: $CTID"
    echo "Hostname: $HOSTNAME"
    echo "Dirección IP: $IP"
    echo "Puerto Icecast: 8000"
    echo "URL de acceso: http://$IP:8000"
    echo "Panel admin: http://$IP:8000/admin"
    echo "Credenciales admin:"
    echo "  Usuario: admin"
    echo "  Contraseña: [la que ingresaste]"
    echo "============================================="
    echo "Puedes acceder al contenedor con:"
    echo "pct enter $CTID"
    echo "============================================="
}

# Flujo principal
main() {
    credenciales
    crear_ct
    configurar_icecast
    configurar_motd
    mostrar_resumen
}

main
