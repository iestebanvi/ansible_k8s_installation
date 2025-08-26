#!/bin/bash

# Script para desplegar cluster Kubernetes con Ansible
# Basado en la conversión del script kubeadm original

set -e

# Verificar variables requeridas
REQUIRED_VARS=(
    "AF_USERNAME"
    "AF_API_TOKEN"
    "CAAS_SA_AF_TOKEN"
    "KUBE_VERSION"
    "KUBE_VIP_VERSION"
    "K8S_API_IP"
    "DTH_INTERFACE"
    "HOST_INTERFACE"
    "APT_PROXY"
    "CONTAINERD_VERSION"
    "CRI_TOOLS_VERSION"
    "PAUSE_VERSION"
    "CNI_PLUGIN_VERSION"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Variable $var no está definida"
        exit 1
    fi
done

echo "==========================================="
echo "Iniciando despliegue de Kubernetes cluster"
echo "==========================================="
echo "- API IP: $K8S_API_IP"
echo "- Interface: $DTH_INTERFACE"
echo "- Kube Version: $KUBE_VERSION"
echo "- ContainerD Version: $CONTAINERD_VERSION"
echo "- Kube-VIP Version: $KUBE_VIP_VERSION"
echo "==========================================="

# Ejecutar playbook con todas las variables
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
  "$@"

echo ""
echo "==========================================="
echo "Despliegue completado!"
echo "==========================================="
echo ""
echo "IMPORTANTE: Recuerda eliminar las credenciales sa_tdi-caas después de la instalación:"
echo "- De las variables de entorno"
echo "- Del archivo /etc/containerd/config.toml en todos los nodos"
echo ""
echo "Para verificar el estado del cluster:"
echo "kubectl get nodes"
echo "kubectl get pods -A"
