# Kubernetes Cluster Deployment with Ansible

Este playbook automatiza la instalación de un cluster Kubernetes con alta disponibilidad usando kubeadm, basado en el script bash original.

## Características

- **3 Masters en HA** con kube-vip para failover del API server
- **Workers opcionales** o uso de masters como workers (sin taint)
- **Generación dinámica de tokens** - no necesitas pre-generar tokens manualmente
- **Configuración completa** incluyendo containerd, registries privados, proxy APT
- **Idempotente** - puede ejecutarse múltiples veces de forma segura

## Estructura del Proyecto

```
k8s-playbook/
├── k8s-cluster.yml              # Playbook principal
├── deploy.sh                    # Script para ejecutar el despliegue
├── set-vars-example.sh          # Ejemplo de variables de entorno
├── inventory/
│   └── hosts.yml               # Inventario de hosts
└── roles/
    ├── k8s-prep/               # Preparación del sistema y paquetes
    ├── k8s-master-init/        # Inicialización del primer master
    ├── k8s-master-join/        # Join de masters adicionales
    ├── k8s-worker-join/        # Join de workers
    └── k8s-post-config/        # Configuración post-instalación
```

## Configuración Previa

### 1. Ajustar el Inventory

Edita `inventory/hosts.yml` con las IPs reales de tus nodos:

```yaml
masters:
  hosts:
    caas-master-1:
      ansible_host: TU_IP_MASTER_1
    caas-master-2:
      ansible_host: TU_IP_MASTER_2
    caas-master-3:
      ansible_host: TU_IP_MASTER_3
workers:
  hosts:
    caas-worker-1:
      ansible_host: TU_IP_WORKER_1
    caas-worker-2:
      ansible_host: TU_IP_WORKER_2
```

### 2. Configurar Variables

```bash
# Copia y ajusta las variables
cp set-vars-example.sh set-vars.sh
nano set-vars.sh

# Carga las variables
source set-vars.sh
```

### Variables requeridas:

```bash
# Credenciales (eliminar después)
AF_USERNAME="sa_tdi-caas"
AF_API_TOKEN="password"
CAAS_SA_AF_TOKEN="token"

# Versiones
KUBE_VERSION="1.27.5-00"
CONTAINERD_VERSION="1.7.13"
KUBE_VIP_VERSION="v0.6.4"

# Red e infraestructura
K8S_API_IP="10.0.1.100"       # IP virtual del API server
DTH_INTERFACE="ens8"          # Interface para kube-vip
HOST_INTERFACE="ens4"         # Interface principal
APT_PROXY="10.0.1.50"         # Servidor proxy
```

## Uso

### Despliegue Completo (3 masters + 2 workers)

```bash
source set-vars.sh
./deploy.sh
```

### Solo Masters (sin workers)

1. Edita `inventory/hosts.yml` y deja vacío el grupo `workers`
2. Los masters funcionarán también como workers automáticamente

```bash
source set-vars.sh
./deploy.sh
```

### Opciones avanzadas

```bash
# Ejecutar solo hasta cierto punto
./deploy.sh --tags "prep"

# Modo debug
./deploy.sh -vvv

# Solo ciertos hosts
./deploy.sh --limit masters
```

## Post-Instalación

### 1. Verificar el cluster

```bash
# Conectar al primer master
ssh caas-master-1

# Verificar nodos
kubectl get nodes

# Verificar pods del sistema
kubectl get pods -A
```

### 2. **IMPORTANTE: Limpiar credenciales**

Después de la instalación exitosa, elimina las credenciales:

```bash
# En cada nodo, editar el archivo containerd
sudo nano /etc/containerd/config.toml
# Eliminar o comentar las líneas de username/password

# Reiniciar containerd
sudo systemctl restart containerd
```

### 3. Instalar CNI

El cluster quedará en estado `NotReady` hasta que instales un CNI:

```bash
# Ejemplo con Calico
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

### 4. (Opcional) Remover taint de masters

Si no tienes workers dedicados:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

## Troubleshooting

### Los nodos están en NotReady
- Verificar que containerd esté ejecutándose: `systemctl status containerd`
- Instalar un CNI plugin
- Revisar logs: `journalctl -u kubelet -f`

### Error de tokens
- Los tokens se generan automáticamente
- Si hay problemas, revisar logs del primer master: `journalctl -u kubeadm`

### Problemas de conectividad
- Verificar que el proxy APT esté accesible
- Verificar conectividad a Artifactory
- Revisar configuración de interfaces de red

### Kube-vip no funciona
- Verificar que la IP virtual esté disponible
- Verificar que el interface DTH_INTERFACE exista
- Revisar logs: `crictl logs <kube-vip-pod>`

## Arquitectura

### Flujo de Ejecución

1. **Preparación** (todos los nodos):
   - Configurar kernel modules y sysctl
   - Instalar containerd desde Artifactory
   - Instalar paquetes Kubernetes
   - Configurar kube-vip (solo masters)

2. **Inicialización** (primer master):
   - Ejecutar `kubeadm init` con configuración HA
   - Generar tokens automáticamente
   - Configurar kube-vip para admin.conf

3. **Join Masters** (masters adicionales):
   - Obtener tokens del primer master vía hostvars
   - Ejecutar `kubeadm join` con `--control-plane`

4. **Join Workers** (si existen):
   - Obtener tokens del primer master
   - Ejecutar `kubeadm join` sin `--control-plane`

5. **Post-configuración** (todos):
   - Configurar kubelet con node-ip específica
   - Ajustar límites de archivos del sistema

### Componentes Clave

- **kube-vip**: Proporciona HA para el API server con IP virtual
- **containerd**: Runtime de contenedores con registry privado
- **kubeadm**: Herramienta de bootstrap del cluster
- **Tokens dinámicos**: Generación automática sin intervención manual

## Customización

### Cambiar versión de Kubernetes

```bash
export KUBE_VERSION="1.28.0-00"
```

### Usar diferentes registries

Edita los templates y tasks para cambiar:
- `artifactory.devops.telekom.de` por tu registry
- Ajustar autenticación según tu entorno

### Modificar configuración de red

Edita `roles/k8s-master-init/templates/kubeadm-config.yaml.j2`:

```yaml
networking:
  podSubnet: "10.244.0.0/16"  # Cambiar subnet de pods
```

## Contribuir

Para mejorar este playbook:

1. Fork del repositorio
2. Crear feature branch
3. Testear cambios
4. Crear pull request

## Licencia

Este proyecto está basado en scripts internos y se proporciona tal como está para uso interno.
