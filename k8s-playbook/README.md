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
- **Multiple inventory support** for different environments

## Project Structure

```
k8s-playbook/
├── k8s-cluster.yml              # Main playbook
├── deploy.sh                    # Deployment script
├── set-vars-example.sh          # Environment variables example
├── inventory/
│   ├── hosts.yml               # Default host inventory
│   ├── hosts-no-workers.yml    # Masters only (no workers)
│   └── hosts-with-workers.yml  # Masters + workers
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

# Infrastructure
K8S_API_IP="10.0.1.100"       # Virtual IP for API server
APT_PROXY="10.0.1.50"         # Proxy server IP
DTH_INTERFACE="ens7"           # Interface for kube-vip (updated default)
HOST_INTERFACE="ens4"          # Main host interface
```

### Variables with Default Values (optional to override):

```bash
# User (updated default)
AF_USERNAME="sa_tdi-caas-r"

# Versions (updated defaults)
KUBE_VERSION="1.32.2-1.1"
CRI_TOOLS_VERSION="1.32.0-1.1"
CONTAINERD_VERSION="1.7.22"
KUBE_VIP_VERSION="v0.6.4"
PAUSE_VERSION="3.10"
CNI_PLUGIN_VERSION="v1.4.0"

# SSH and Inventory
ANSIBLE_SSH_USER="ubuntu"
```

## Usage

### Script Options

The `deploy.sh` script supports the following options:

| Option | Description |
|--------|-------------|
| `--check` | Run in dry-run mode (no changes applied) |
| `--tags TAG1,TAG2` | Execute only tasks with specified tags |
| `--skip-tags TAG1,TAG2` | Skip tasks with specified tags |
| `--limit HOST_PATTERN` | Execute only on hosts matching the pattern |
| `-i, --inventory FILE` | Use specific inventory file |
| `-v, -vv, -vvv` | Verbose mode (1-3 levels of verbosity) |
| `--help, -h` | Show help message |

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

| Tag | Aliases | Description |
|-----|---------|-------------|
| `prep` | `preparation`, `system` | System preparation and packages |
| `master-init` | `init`, `cluster-init` | First master initialization |
| `master-join` | `masters` | Join additional masters |
| `worker-join` | `workers` | Join workers |
| `join` | | All joins (masters + workers) |
| `post-config` | `config`, `finalize` | Post-installation configuration |

### Advanced Usage Examples

```bash
# Help and available options
./deploy.sh --help

# Complete dry-run
./deploy.sh --check

# Dry-run specific phase
./deploy.sh --check --tags prep

# Use specific inventory
./deploy.sh -i inventory/hosts-no-workers.yml

# Skip certain phases
./deploy.sh --skip-tags prep

# Execute only on specific hosts
./deploy.sh --limit masters

# Execute only on masters with verbose output
./deploy.sh --limit masters -v

# Verbose mode (increasing detail levels)
./deploy.sh -v      # Basic verbose
./deploy.sh -vv     # More verbose
./deploy.sh -vvv    # Maximum verbose

# Combine multiple options
./deploy.sh --check --tags join --limit masters -v

# Deploy only preparation phase with custom inventory
./deploy.sh -i inventory/hosts-prod.yml --tags prep

# Deploy everything except preparation
./deploy.sh --skip-tags prep

# Deploy with different verbosity levels for debugging
./deploy.sh --check --tags master-init -vvv
```

### Deployment Scenarios

#### Full Deployment (3 masters + 2 workers)
```bash
source set-vars.sh
./deploy.sh
```

#### Masters Only (no workers)
```bash
# Use the specific inventory or edit hosts.yml to leave workers empty
./deploy.sh -i inventory/hosts-no-workers.yml
# Masters will automatically function as workers
```

#### Add workers to existing cluster
```bash
# Only join workers to existing cluster
./deploy.sh --tags worker-join
```

#### Multi-environment deployments
```bash
# Development environment
./deploy.sh -i inventory/hosts-dev.yml

# Staging environment
./deploy.sh -i inventory/hosts-staging.yml --check

# Production environment
./deploy.sh -i inventory/hosts-prod.yml --tags prep
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


### 2. Install CNI

The cluster will remain `NotReady` until you install a CNI:

```bash
# Example with Calico
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Or with Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### 3. (Optional) Remove master taints

If you don't have dedicated workers:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

## Troubleshooting

### Common Issues and Solutions

#### Variables not found error
```bash
❌ Error: The following variables are not defined:
   - AF_API_TOKEN
   - K8S_API_IP
   - APT_PROXY
```

**Solution**: Make sure to use `source` instead of just executing the script:
```bash
# Wrong way
./set-vars.sh

# Correct way
source ./set-vars.sh
# or
. ./set-vars.sh
```

#### Inventory file not found
```bash
❌ Error: Inventory file does not exist: inventory/hosts-custom.yml
```

**Solution**: Check available inventories:
```bash
ls inventory/*.yml
./deploy.sh --help  # See available inventories
```

#### Nodes are in NotReady state
- Verify containerd is running: `systemctl status containerd`
- Install a CNI plugin
- Check logs: `journalctl -u kubelet -f`

#### Token errors
- Tokens are generated automatically
- If there are issues, check first master logs: `journalctl -u kubeadm`
- You can regenerate tokens: `kubeadm token create --print-join-command`

#### Connectivity issues
- Verify APT proxy is accessible
- Verify Artifactory connectivity
- Check network interface configuration
- Test SSH connectivity: `ansible all -i inventory/hosts.yml -m ping`

#### Kube-vip not working
- Verify virtual IP is available
- Verify DTH_INTERFACE exists: `ip a show ens7`
- Check logs: `crictl logs <kube-vip-pod>`

### General debugging

```bash
# Check what would be done
./deploy.sh --check -v

# Run only preparation to isolate issues
./deploy.sh --tags prep

# Check specific nodes
./deploy.sh --limit caas-master-1 --check

# Maximum verbosity for detailed debugging
./deploy.sh --check --tags master-init -vvv

# Test connectivity before deployment
ansible all -i inventory/hosts.yml -m ping
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
export CRI_TOOLS_VERSION="1.28.0-00"
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
├── hosts-dev.yml        # Development environment
├── hosts-staging.yml    # Staging environment
└── hosts-prod.yml       # Production environment

# Use specific inventory
./deploy.sh -i inventory/hosts-prod.yml
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

# Monitor with verbose output
./deploy.sh -i inventory/hosts-prod.yml --check -v
```

### Version Updates

Current default versions (as of latest update):
- Kubernetes: `1.32.2-1.1`
- CRI Tools: `1.32.0-1.1` 
- ContainerD: `1.7.22`
- Kube-VIP: `v0.6.4`
- Pause: `3.10`
- CNI Plugin: `v1.4.0`

## Contributing

To improve this playbook:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Create a pull request

### Testing Changes
```bash
# Test in development environment
./deploy.sh -i inventory/hosts-dev.yml --check

# Test specific roles
./deploy.sh --tags prep --limit dev-master-1 -v

# Test with maximum verbosity
./deploy.sh -i inventory/hosts-dev.yml --check -vvv
```

## License

This project is based on internal scripts and is provided as-is for internal use.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review Ansible and kubeadm logs
3. Test with `--check` mode first
4. Use verbose mode (`-v`, `-vv`, or `-vvv`) for detailed output
5. Test connectivity with `ansible all -i inventory/hosts.yml -m ping`