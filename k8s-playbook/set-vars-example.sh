#!/bin/bash

# Ejemplo de variables para el despliegue de Kubernetes
# Copia este archivo como set-vars.sh y ajusta los valores

# Credenciales Artifactory (ELIMINAR DESPUÉS DE LA INSTALACIÓN)
export AF_USERNAME="sa_tdi-caas"
export AF_API_TOKEN="REPLACE_WITH_PASSWORD"
export CAAS_SA_AF_TOKEN="REPLACE_WITH_TOKEN"

# Versiones específicas
export KUBE_VERSION="1.27.5-00"
export KUBE_VIP_VERSION="v0.6.4"
export CONTAINERD_VERSION="1.7.13"
export CRI_TOOLS_VERSION="1.26.0-00"
export PAUSE_VERSION="3.9"
export CNI_PLUGIN_VERSION="v1.4.0"

# Configuración de infraestructura
export K8S_API_IP="10.0.1.100"           # IP virtual para el API server
export DTH_INTERFACE="ens8"              # Interface para kube-vip
export HOST_INTERFACE="ens4"             # Interface principal del host
export APT_PROXY="10.0.1.50"            # Servidor proxy APT

# Uso:
# 1. Copia este archivo: cp set-vars-example.sh set-vars.sh
# 2. Ajusta los valores en set-vars.sh
# 3. Ejecuta: source set-vars.sh
# 4. Ejecuta: ./deploy.sh

echo "Variables configuradas para el despliegue de Kubernetes"
echo "API IP: $K8S_API_IP"
echo "Interface: $DTH_INTERFACE"
echo "Versión K8s: $KUBE_VERSION"
