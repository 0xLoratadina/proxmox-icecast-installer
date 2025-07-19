#!/usr/bin/env bash
set -eo pipefail

# Verificar Proxmox
if ! command -v pveversion &>/dev/null; then
    echo "Este script debe ejecutarse en un servidor Proxmox VE"
    exit 1
fi

# Instalar dependencias
if ! command -v whiptail &>/dev/null; then
    apt-get update && apt-get install -y whiptail
fi

# Configuración inicial
CTID=1000
HOSTNAME="radio-server"
MEMORY=4096
STORAGE="local-lvm"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TAGS="radio,server,ssl"  # Etiquetas añadidas

# Obtener credenciales y configuración
obtener_configuracion() {
    # Credenciales básicas
    PASSWORD_ROOT=$(whiptail --passwordbox "Contraseña root del contenedor:" 8 40 --title "Configuración" 3>&1 1>&2 2>&3)
    ICECAST_ADMIN=$(whiptail --passwordbox "Contraseña admin para Icecast:" 8 40 --title "Configuración" 3>&1 1>&2 2>&3)
    ICECAST_SOURCE=$(whiptail --passwordbox "Contraseña source para Icecast:" 8 40 --title "Configuración" 3>&1 1>&2 2>&3)
    ICECAST_RELAY=$(whiptail --passwordbox "Contraseña relay para Icecast:" 8 40 --title "Configuración" 3>&1 1>&2 2>&3)
    
    # Configuración SSL
    SSL_CHOICE=$(whiptail --title "Configuración SSL/TLS" --menu "Seleccione tipo de configuración:" 15 50 4 \
    "1" "SSL/TLS Estándar" \
    "2" "SSL/TLS con Showcast" \
    "3" "WebRTC (Certificados revocados)" \
    "4" "Sin SSL (Radio.co)" 3>&1 1>&2 2>&3)
    
    # Configuración de montaje
    MOUNT_POINT=$(whiptail --inputbox "Punto de montaje Icecast (ej: /stream):" 8 40 "/stream" 3>&1 1>&2 2>&3)
    ICECAST_USER=$(whiptail --inputbox "Usuario de Icecast:" 8 40 "admin" 3>&1 1>&2 2>&3)
    
    # Opciones avanzadas
    USE_LEGACY=$(whiptail --title "Opciones avanzadas" --yesno "¿Usar protocolo anticuado Icecast?" 8 40 3>&1 1>&2 2>&3; echo $?)
    SHOW_PASS=$(whiptail --title "Visualización" --yesno "¿Mostrar contraseñas en el resumen?" 8 40 3>&1 1>&2 2>&3; echo $?)
}

# Crear contenedor con etiquetas
crear_contenedor() {
    echo "📦 Creando contenedor LXC con etiquetas: $TAGS"
    pct create $CTID "local:vztmpl/$TEMPLATE" \
        --storage $STORAGE \
        --hostname $HOSTNAME \
        --memory $MEMORY \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --ostype debian \
        --password "$PASSWORD_ROOT" \
        --unprivileged 1 \
        --features nesting=1 \
        --tags "$TAGS"  # Aplicar etiquetas aquí
    
    echo "⚡ Iniciando contenedor..."
    pct start $CTID
    sleep 5
}

# Configurar Icecast con SSL
configurar_icecast_ssl() {
    echo "🔐 Configurando Icecast con SSL..."
    pct exec $CTID -- apt-get update
    pct exec $CTID -- apt-get install -y icecast2
    
    # Aplicar configuración SSL según selección
    case $SSL_CHOICE in
        1)
            echo "🔒 Configurando SSL/TLS Estándar..."
            pct exec $CTID -- sed -i "s|<ssl>0</ssl>|<ssl>1</ssl>|" /etc/icecast2/icecast.xml
            ;;
        2)
            echo "🎧 Configurando para Showcast..."
            pct exec $CTID -- sed -i "s|<!--<ssl-certificate>.*</ssl-certificate>-->|<ssl-certificate>/etc/icecast2/cert.pem</ssl-certificate>|" /etc/icecast2/icecast.xml
            ;;
        3)
            echo "🔓 Configurando WebRTC con certificados revocados..."
            pct exec $CTID -- sed -i "s|<ssl>0</ssl>|<ssl>1</ssl>|" /etc/icecast2/icecast.xml
            pct exec $CTID -- sed -i "s|<ssl-allowed-ciphers>.*</ssl-allowed-ciphers>|<ssl-allowed-ciphers>ALL:!aNULL:!eNULL:!LOW:!EXP:!RC4:!3DES:!MD5:!PSK:@STRENGTH</ssl-allowed-ciphers>|" /etc/icecast2/icecast.xml
            ;;
        4)
            echo "📻 Configurando para Radio.co (sin SSL)..."
            ;;
    esac
    
    # Configuración común
    pct exec $CTID -- sed -i "s|<source-password>.*</source-password>|<source-password>$ICECAST_SOURCE</source-password>|" /etc/icecast2/icecast.xml
    pct exec $CTID -- sed -i "s|<relay-password>.*</relay-password>|<relay-password>$ICECAST_RELAY</relay-password>|" /etc/icecast2/icecast.xml
    pct exec $CTID -- sed -i "s|<admin-password>.*</admin-password>|<admin-password>$ICECAST_ADMIN</admin-password>|" /etc/icecast2/icecast.xml
    pct exec $CTID -- sed -i "s|<mount>/stream</mount>|<mount>$MOUNT_POINT</mount>|" /etc/icecast2/icecast.xml
    
    # Protocolo anticuado
    if [ $USE_LEGACY -eq 0 ]; then
        echo "🔄 Habilitando protocolo anticuado Icecast..."
        pct exec $CTID -- sed -i "s|<protocol>http</protocol>|<protocol>icy</protocol>|" /etc/icecast2/icecast.xml
    fi
    
    pct exec $CTID -- systemctl restart icecast2
}

# Configurar visualización en el contenedor
configurar_visualizacion() {
    echo "🖥️ Configurando visualización..."
    pct exec $CTID -- bash -c "cat > /etc/update-motd.d/30-radio-info <<'EOF'
#!/bin/sh
echo \"\"
echo \"================================================\"
echo \"        SERVIDOR DE RADIO - CONFIGURACIÓN       \"
echo \"================================================\"
echo \"🔒 SSL/TLS: $SSL_TYPE\"
echo \"📻 Punto de montaje: $MOUNT_POINT\"
echo \"👤 Usuario: $ICECAST_USER\"
echo \"🔊 Stream: http://\$(hostname -I | awk '{print \$1}'):8000$MOUNT_POINT\"
echo \"🖥️ Admin: http://\$(hostname -I | awk '{print \$1}'):8000/admin\"
echo \"================================================\"
echo \"\"
EOF"
    
    pct exec $CTID -- chmod +x /etc/update-motd.d/30-radio-info
    pct exec $CTID -- bash -c "echo '[[ -f /etc/update-motd.d/30-radio-info ]] && /etc/update-motd.d/30-radio-info' >> /etc/profile"
}

# Mostrar resumen completo
mostrar_resumen() {
    IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
    
    # Determinar tipo SSL
    case $SSL_CHOICE in
        1) SSL_TYPE="SSL/TLS Estándar";;
        2) SSL_TYPE="Showcast (SSL/TLS)";;
        3) SSL_TYPE="WebRTC (Certificados revocados)";;
        4) SSL_TYPE="Sin SSL (Radio.co)";;
    esac
    
    clear
    echo "================================================"
    echo "    INSTALACIÓN COMPLETA - SERVIDOR DE RADIO    "
    echo "================================================"
    echo "🏷️ Etiquetas del contenedor: $TAGS"
    echo "🔢 CTID: $CTID"
    echo "🌐 Hostname: $HOSTNAME"
    echo "📡 IP: $IP"
    echo "🔌 Puerto: 8000"
    echo ""
    echo "🔐 CONFIGURACIÓN SSL:"
    echo " - Tipo: $SSL_TYPE"
    echo ""
    echo "📻 CONFIGURACIÓN RADIO:"
    echo " - Punto de montaje: $MOUNT_POINT"
    echo " - Usuario: $ICECAST_USER"
    echo " - Protocolo: $(if [ $USE_LEGACY -eq 0 ]; then echo "ICY (antiguo)"; else echo "HTTP"; fi)"
    echo ""
    echo "🌍 URLS DE ACCESO:"
    echo " - Stream: http://$IP:8000$MOUNT_POINT"
    echo " - Admin: http://$IP:8000/admin"
    echo ""
    echo "🔑 CREDENCIALES:"
    if [ $SHOW_PASS -eq 0 ]; then
        echo " - Admin: $ICECAST_USER / $ICECAST_ADMIN"
        echo " - Source: $ICECAST_SOURCE"
        echo " - Relay: $ICECAST_RELAY"
    else
        echo " - (Las credenciales fueron configuradas pero no se muestran)"
    fi
    echo "================================================"
    echo "Para acceder al contenedor: pct enter $CTID"
    echo "================================================"
}

# Flujo principal
main() {
    obtener_configuracion
    crear_contenedor
    configurar_icecast_ssl
    configurar_visualizacion
    mostrar_resumen
}

main
