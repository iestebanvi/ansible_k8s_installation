# Kubernetes Cluster Deployment with Ansible

This playbook automates the installation of a high-availability Kubernetes cluster using kubeadm, based on the original bash script.

## Features

- **3 Masters in HA** with kube-vip for API server failover
- **Optional workers** or use masters as workers (without taint)
- **Dynamic token generation** - no need to pre-generate tokens manually
- **Complete configuration** including containerd, private registries, APT proxy
- **Idempotent** - can be executed multiple times safely
- **Phase-based execution** with tags for granular control
- **Dry-run support** for safe testing
- **Default values** for common variables to simplify configuration

## Project Structure

```
k8s-playbook/
├── k8s-cluster.yml              # Main playbook
├── deploy.sh                    # Deployment script
├── set-vars-example.sh          # Environment variables example
├── inventory/
│   └── hosts.yml               # Host inventory
└── roles/
    ├── k8s-prep/               # System preparation and packages
    ├── k8s-master-init/        # First master initialization
    ├── k8s-master-join/        # Additional masters join
    ├── k8s-worker-join/        # Workers join
    └── k8s-post-config/        # Post-installation configuration
```

## Initial Setup

### 1. Adjust the Inventory

Edit `inventory/hosts.yml` with your real node IPs:

```yaml
masters:
  hosts:   # Order master1, master2, master3 should be preserved!
    caas-master-1:
      ansible_host: YOUR_MASTER_1_IP
    caas-master-2:
      ansible_host: YOUR_MASTER_2_IP
    caas-master-3:
      ansible_host: YOUR_MASTER_3_IP
workers:
  hosts:
    caas-worker-1:
      ansible_host: YOUR_WORKER_1_IP
    caas-worker-2:
      ansible_host: YOUR_WORKER_2_IP
```

### 2. Configure Variables

```bash
# Copy and adjust the variables
cp set-vars-example.sh set-vars.sh
nano set-vars.sh

# Load the variables
source set-vars.sh
```

### Required Variables (must be set):

```bash
# Credentials (delete after installation)
AF_API_TOKEN="password_of_sa_tdi-caas"
CAAS_SA_AF_TOKEN="token_of_sa_tdi-caas"

# Infrastructure
K8S_API_IP="10.0.1.100"       # Virtual IP for API server
APT_PROXY="10.0.1.50"         # Proxy server IP
```

### Variables with Default Values (optional to override):

```bash
# User (default: sa_tdi-caas)
AF_USERNAME="sa_tdi-caas"

# Versions (default: stable versions)
KUBE_VERSION="1.27.5-00"
CONTAINERD_VERSION="1.7.13"
KUBE_VIP_VERSION="v0.6.4"
CRI_TOOLS_VERSION="1.26.0-00"
PAUSE_VERSION="3.9"
CNI_PLUGIN_VERSION="v1.4.0"

# Network interfaces (default: ens8/ens4)
DTH_INTERFACE="ens8"          # Interface for kube-vip
HOST_INTERFACE="ens4"         # Main host interface
```

## Usage

### Quick Start (Recommended)

```bash
# 1. Configure essential variables only
source set-vars.sh

# 2. Test what would be done
./deploy.sh --check

# 3. Deploy step by step
./deploy.sh --tags prep        # Prepare systems
./deploy.sh --tags master-init # Initialize cluster
./deploy.sh --tags join        # Join all nodes

# 4. Or deploy everything at once
./deploy.sh
```

### Phase-based Deployment (Recommended for first use)

```bash
# 1. Verify system preparation
./deploy.sh --check --tags prep

# 2. Apply system preparation
./deploy.sh --tags prep

# 3. Verify cluster initialization
./deploy.sh --check --tags master-init

# 4. Initialize the cluster
./deploy.sh --tags master-init

# 5. Join additional masters
./deploy.sh --tags master-join

# 6. Join workers (if any)
./deploy.sh --tags worker-join

# 7. Final configuration
./deploy.sh --tags post-config
```

### Available Tags

| Tag | Description |
|-----|-------------|
| `prep`, `preparation`, `system` | System preparation and packages |
| `master-init`, `init`, `cluster-init` | Cluster initialization |
| `master-join`, `masters` | Join additional masters |
| `worker-join`, `workers` | Join workers |
| `join` | All joins (masters + workers) |
| `post-config`, `config`, `finalize` | Final configuration |

### Advanced Options

```bash
# Help and available options
./deploy.sh --help

# Dry-run (no changes applied)
./deploy.sh --check

# Dry-run specific phase
./deploy.sh --check --tags prep

# Skip certain phases
./deploy.sh --skip-tags prep

# Execute only on specific hosts
./deploy.sh --limit masters

# Verbose mode
./deploy.sh -v    # or -vv, -vvv for more detail

# Combine options
./deploy.sh --check --tags join --limit masters -v
```

### Deployment Scenarios

#### Full Deployment (3 masters + 2 workers)
```bash
source set-vars.sh
./deploy.sh
```

#### Masters Only (no workers)
1. Edit `inventory/hosts.yml` and leave `workers` group empty
2. Masters will automatically function as workers

```bash
source set-vars.sh
./deploy.sh
```

#### Add workers to existing cluster
```bash
# Only join workers to existing cluster
./deploy.sh --tags worker-join
```

## Post-Installation

### 1. Verify the Cluster

```bash
# Connect to first master
ssh caas-master-1

# Check nodes
kubectl get nodes

# Check system pods
kubectl get pods -A
```

### 2. **IMPORTANT: Clean up credentials**

After successful installation, remove credentials:

```bash
# On each node, edit containerd config
sudo nano /etc/containerd/config.toml
# Remove or comment username/password lines

# Restart containerd
sudo systemctl restart containerd

# Also clean environment variables
unset AF_API_TOKEN CAAS_SA_AF_TOKEN
```

### 3. Install CNI

The cluster will remain `NotReady` until you install a CNI:

```bash
# Example with Calico
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Or with Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### 4. (Optional) Remove master taints

If you don't have dedicated workers:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

## Troubleshooting

### Nodes are in NotReady state
- Verify containerd is running: `systemctl status containerd`
- Install a CNI plugin
- Check logs: `journalctl -u kubelet -f`

### Token errors
- Tokens are generated automatically
- If there are issues, check first master logs: `journalctl -u kubeadm`
- You can regenerate tokens: `kubeadm token create --print-join-command`

### Connectivity issues
- Verify APT proxy is accessible
- Verify Artifactory connectivity
- Check network interface configuration
- Test SSH connectivity: `ansible all -i inventory/hosts.yml -m ping`

### Kube-vip not working
- Verify virtual IP is available
- Verify DTH_INTERFACE exists: `ip a show ens8`
- Check logs: `crictl logs <kube-vip-pod>`

### General debugging
```bash
# Check what would be done
./deploy.sh --check -v

# Run only preparation to isolate issues
./deploy.sh --tags prep

# Check specific nodes
./deploy.sh --limit caas-master-1 --check
```

## Architecture

### Execution Flow

1. **Preparation** (all nodes):
   - Configure kernel modules and sysctl
   - Install containerd from Artifactory
   - Install Kubernetes packages
   - Configure kube-vip (masters only)

2. **Initialization** (first master):
   - Execute `kubeadm init` with HA configuration
   - Generate tokens automatically
   - Configure kube-vip for admin.conf

3. **Join Masters** (additional masters):
   - Get tokens from first master via hostvars
   - Execute `kubeadm join` with `--control-plane`

4. **Join Workers** (if they exist):
   - Get tokens from first master
   - Execute `kubeadm join` without `--control-plane`

5. **Post-configuration** (all nodes):
   - Configure kubelet with specific node-ip
   - Adjust system file limits

### Key Components

- **kube-vip**: Provides HA for API server with virtual IP
- **containerd**: Container runtime with private registry
- **kubeadm**: Cluster bootstrap tool
- **Dynamic tokens**: Automatic generation without manual intervention

## Customization

### Change Kubernetes Version

```bash
export KUBE_VERSION="1.28.0-00"
```

### Use Different Registries

Edit templates and tasks to change:
- `artifactory.devops.telekom.de` to your registry
- Adjust authentication according to your environment

### Modify Network Configuration

Edit `roles/k8s-master-init/templates/kubeadm-config.yaml.j2`:

```yaml
networking:
  podSubnet: "10.244.0.0/16"  # Change pod subnet
```

### Add Custom Configuration

You can extend roles or add new ones:

```bash
# Add new role
mkdir -p roles/custom-config/{tasks,templates}

# Reference in main playbook
echo "  - custom-config" >> roles/k8s-prep/meta/main.yml
```

## Security Considerations

### Credentials Management
- **Never commit** real credentials to version control
- Use `ansible-vault` for sensitive data in production:
  ```bash
  ansible-vault encrypt_string 'your-secret' --name 'af_api_token'
  ```
- Clean up credentials immediately after installation

### Network Security
- Ensure virtual IP is properly allocated
- Configure firewall rules for Kubernetes ports
- Use secure network interfaces

### File Permissions
- Kubeconfig files have restricted permissions automatically
- Certificate keys are cleaned up after use

## Production Recommendations

### Multiple Environments
```bash
# Different inventories for different environments
inventory/
├── dev.yml          # Development environment
├── staging.yml      # Staging environment
└── prod.yml         # Production environment

# Use specific inventory
./deploy.sh -i inventory/prod.yml
```

### Backup Strategy
```bash
# Before deployment, backup existing configs
./deploy.sh --tags prep --extra-vars "backup_existing=true"
```

### Monitoring Deployment
```bash
# Monitor deployment progress
watch -n 2 'ansible all -i inventory/hosts.yml -m shell -a "systemctl status kubelet" --one-line'
```

## Contributing

To improve this playbook:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Create a pull request

### Testing Changes
```bash
# Test in development environment
./deploy.sh -i inventory/dev.yml --check

# Test specific roles
./deploy.sh --tags prep --limit dev-master-1
```

## License

This project is based on internal scripts and is provided as-is for internal use.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review Ansible and kubeadm logs
3. Test with `--check` mode first
4. Use verbose mode (`-v`) for detailed output