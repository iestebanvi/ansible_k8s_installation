#!/bin/bash

# Script para desplegar cluster Kubernetes con Ansible
# Basado en la conversión del script kubeadm original

set -e

# Función para mostrar ayuda
show_help() {
    cat << 'EOF'
Kubernetes Cluster Deployment Script

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    --check                     Ejecutar en modo dry-run (no aplica cambios)
    --tags TAG1,TAG2           Ejecutar solo las tareas con los tags especificados
    --skip-tags TAG1,TAG2      Saltar las tareas con los tags especificados
    --limit HOST_PATTERN       Ejecutar solo en los hosts que coincidan con el patrón
    -v, -vv, -vvv             Modo verbose (1-3 niveles)
    --help, -h                 Mostrar esta ayuda

TAGS DISPONIBLES:
    prep, preparation, system   - Preparación del sistema y paquetes
    master-init, init          - Inicialización del primer master
    master-join, masters       - Join de masters adicionales
    worker-join, workers       - Join de workers
    join                       - Todos los joins (masters + workers)
    post-config, config        - Configuración post-instalación
    finalize                   - Finalización

EJEMPLOS:
    # Dry-run completo
    ./deploy.sh --check

    # Dry-run solo preparación
    ./deploy.sh --check --tags prep

    # Solo preparación del sistema
    ./deploy.sh --tags prep

    # Solo inicializar primer master
    ./deploy.sh --tags master-init

    # Solo hacer join (masters + workers)
    ./deploy.sh --tags join

    # Ejecutar todo excepto preparación
    ./deploy.sh --skip-tags prep

    # Solo en masters con verbose
    ./deploy.sh --limit masters -v

    # Despliegue por fases (recomendado para primer uso):
    ./deploy.sh --check --tags prep     # 1. Verificar preparación
    ./deploy.sh --tags prep             # 2. Aplicar preparación
    ./deploy.sh --tags master-init      # 3. Inicializar cluster
    ./deploy.sh --tags master-join      # 4. Añadir masters
    ./deploy.sh --tags worker-join      # 5. Añadir workers
    ./deploy.sh --tags post-config      # 6. Configuración final

EOF
}

# Verificar si se pide ayuda
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Configurar valores por defecto (ACTUALIZADOS)
: ${AF_USERNAME:="sa_tdi-caas-r"}                # ACTUALIZADO: ahora con -r
: ${KUBE_VERSION:="1.32.2-1.1"}                 # ACTUALIZADO
: ${CRI_TOOLS_VERSION:="1.32.0-1.1"}            # ACTUALIZADO  
: ${KUBE_VIP_VERSION:="v0.6.4"}
: ${CONTAINERD_VERSION:="1.7.13"}
: ${PAUSE_VERSION:="3.10"}                       # ACTUALIZADO
: ${CNI_PLUGIN_VERSION:="v1.4.0"}
: ${DTH_INTERFACE:="ens7"}                       # ACTUALIZADO
: ${HOST_INTERFACE:="ens4"}
: ${ANSIBLE_SSH_USER:="ubuntu"}                  # NUEVO: Usuario SSH por defecto

# Variables que SÍ necesitan ser definidas obligatoriamente
REQUIRED_VARS=(
    "AF_API_TOKEN"
    "K8S_API_IP"
    "APT_PROXY"
    "DTH_INTERFACE"
    "HOST_INTERFACE"
)

# CAAS_SA_AF_TOKEN se establece automáticamente igual que AF_API_TOKEN
: ${CAAS_SA_AF_TOKEN:="$AF_API_TOKEN"}

# Variables opcionales con valores por defecto (para información)
DEFAULT_VARS=(
    "AF_USERNAME"
    "KUBE_VERSION"
    "KUBE_VIP_VERSION"
    "CONTAINERD_VERSION"
    "CRI_TOOLS_VERSION"
    "PAUSE_VERSION"
    "CNI_PLUGIN_VERSION"
    "DTH_INTERFACE"
    "HOST_INTERFACE"
)

# Verificar variables solo si no se están listando los tags o pidiendo ayuda
if [[ ! "$*" =~ --list-tags ]] && [[ ! "$*" =~ --help ]]; then
    missing_vars=()
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo "❌ Error: Las siguientes variables no están definidas:"
        printf "   - %s\n" "${missing_vars[@]}"
        echo ""
        echo "💡 Sugerencia: "
        echo "   1. cp set-vars-example.sh set-vars.sh"
        echo "   2. nano set-vars.sh  # Ajustar valores"
        echo "   3. source set-vars.sh"
        echo "   4. ./deploy.sh"
        echo ""
        echo "Para más información: ./deploy.sh --help"
        exit 1
    fi
fi

# Detectar el tipo de ejecución basado en los argumentos
check_mode=""
tags_info=""
if [[ "$*" =~ --check ]]; then
    check_mode=" (DRY-RUN - NO CHANGES)"
fi

if [[ "$*" =~ --tags ]]; then
    # Extraer los tags del comando
    tags_arg=$(echo "$*" | grep -o -- '--tags [^[:space:]]*' | cut -d' ' -f2)
    tags_info=" - Tags: $tags_arg"
fi

if [[ "$*" =~ --skip-tags ]]; then
    # Extraer los tags del comando
    skip_tags_arg=$(echo "$*" | grep -o -- '--skip-tags [^[:space:]]*' | cut -d' ' -f2)
    tags_info="$tags_info - Skip Tags: $skip_tags_arg"
fi

# Mostrar información del despliegue (solo si hay variables)
if [ ${#missing_vars[@]} -eq 0 ]; then
    echo "============================================="
    echo "🚀 Kubernetes Cluster Deployment$check_mode"
    echo "============================================="
    echo "📍 API IP: $K8S_API_IP"
    echo "🔌 DTH Interface: $DTH_INTERFACE"
    echo "🖥️  Host Interface: $HOST_INTERFACE"
    echo "📦 Kubernetes: $KUBE_VERSION"
    echo "🐳 ContainerD: $CONTAINERD_VERSION"
    echo "🔧 Kube-VIP: $KUBE_VIP_VERSION"
    echo "👤 SSH User: $ANSIBLE_SSH_USER"
    echo "🏢 Artifactory User: $AF_USERNAME"
    echo "🌐 APT Proxy: $APT_PROXY"
    if [[ -n "$tags_info" ]]; then
        echo "🏷️ Ejecución$tags_info"
    fi
    echo "============================================="
    echo ""
fi

# Verificar conectividad a los hosts antes de empezar (solo en ejecuciones reales)
if [[ ! "$*" =~ --check ]] && [[ ! "$*" =~ --tags.*(prep|preparation) ]] || [[ "$*" =~ --tags.*prep.* ]]; then
    echo "🔍 Verificando conectividad a los hosts..."
    if ! ansible all -i inventory/hosts.yml -m ping --one-line >/dev/null 2>&1; then
        echo "⚠️  Advertencia: Algunos hosts no son accesibles"
        echo "   Verifica el inventory y la conectividad SSH"
        echo ""
    else
        echo "✅ Conectividad OK"
        echo ""
    fi
fi

# Ejecutar playbook con todas las variables
echo "▶️  Ejecutando ansible-playbook..."
echo ""

ansible-playbook -i inventory/hosts.yml k8s-cluster.yml \
  -e af_username="$AF_USERNAME" \
  -e af_api_token="$AF_API_TOKEN" \
  -e caas_sa_af_token="$CAAS_SA_AF_TOKEN" \
  -e kube_version="$KUBE_VERSION" \
  -e kube_vip_version="$KUBE_VIP_VERSION" \
  -e k8s_api_ip="$K8S_API_IP" \
  -e dth_interface="$DTH_INTERFACE" \
  -e host_interface="$HOST_INTERFACE" \
  -e apt_proxy="$APT_PROXY" \
  -e containerd_version="$CONTAINERD_VERSION" \
  -e cri_tools_version="$CRI_TOOLS_VERSION" \
  -e pause_version="$PAUSE_VERSION" \
  -e cni_plugin_version="$CNI_PLUGIN_VERSION" \
  -e ansible_ssh_user="$ANSIBLE_SSH_USER" \
  "$@"

echo ""
if [[ "$*" =~ --check ]]; then
    echo "============================================="
    echo "✅ Dry-run completado!"
    echo "============================================="
    echo "💡 Los cambios mostrados arriba serían aplicados"
    echo "   en una ejecución real (sin --check)"
    echo ""
else
    echo "============================================="
    echo "🎉 Despliegue completado!"
    echo "============================================="
    echo ""
    
    # Mostrar próximos pasos según lo que se ejecutó
    if [[ "$*" =~ --tags.*prep ]] || [[ -z "$tags_info" ]]; then
        echo "📋 Próximos pasos recomendados:"
        if [[ "$*" =~ --tags.*prep ]]; then
            echo "   ./deploy.sh --tags master-init    # Inicializar cluster"
        elif [[ -z "$tags_info" ]]; then
            echo "   ssh caas-master-1 'kubectl get nodes'  # Verificar cluster"
            echo "   # Instalar CNI plugin (cluster quedará NotReady sin él)"
        fi
        echo ""
    fi
    
    echo "⚠️  IMPORTANTE: Eliminar credenciales sa_tdi-caas después:"
    echo "   - Variables de entorno (unset AF_* CAAS_*)"
    echo "   - /etc/containerd/config.toml en todos los nodos"
    echo ""
    
    if [[ ! "$*" =~ --tags ]] || [[ "$*" =~ --tags.*(config|finalize) ]]; then
        echo "🔍 Para verificar el cluster:"
        echo "   kubectl get nodes"
        echo "   kubectl get pods -A"
        echo ""
    fi
fi