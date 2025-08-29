#!/bin/bash

# Kubernetes Cluster Deployment Script with Ansible
# Based on the original kubeadm bash script conversion

set -e

# Function to show help
show_help() {
    cat << 'EOF'
Kubernetes Cluster Deployment Script

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    --check                     Run in dry-run mode (no changes applied)
    --tags TAG1,TAG2           Execute only tasks with specified tags
    --skip-tags TAG1,TAG2      Skip tasks with specified tags
    --limit HOST_PATTERN       Execute only on hosts matching the pattern
    -i, --inventory FILE       Use specific inventory (overrides INVENTORY_FILE)
    -v, -vv, -vvv             Verbose mode (1-3 levels)
    -y, --yes                  Auto-confirm (skip confirmation prompt)
    --help, -h                 Show this help

AVAILABLE TAGS:
    prep, preparation, system   - System preparation and packages
    master-init, init          - First master initialization
    master-join, masters       - Additional masters join
    worker-join, workers       - Workers join
    join                       - All joins (masters + workers)
    post-config, config        - Post-installation configuration
    finalize                   - Finalization

EXAMPLES:
    # Complete dry-run
    ./deploy.sh --check

    # Use inventory
    ./deploy.sh -i inventory/hosts-no-workers.yml

    # System preparation only
    ./deploy.sh -i inventory/hosts-no-workers.yml --tags prep

    # Phase-based deployment (recommended for first use):
    ./deploy.sh --check --tags prep     # 1. Verify preparation
    ./deploy.sh --tags prep             # 2. Apply preparation
    ./deploy.sh --tags master-init      # 3. Initialize cluster
    ./deploy.sh --tags master-join      # 4. Add masters
    ./deploy.sh --tags worker-join      # 5. Add workers
    ./deploy.sh --tags post-config      # 6. Final configuration

    # Skip confirmation
    ./deploy.sh --yes

INVENTORIES:
    inventory/hosts.yml                 - Current configuration
    inventory/hosts-no-workers.yml      - Masters only (no workers)
    inventory/hosts-with-workers.yml    - Masters + workers

EOF
}

# Function to show host information from inventory
show_hosts_info() {
    local inventory_file="$1"
    
    echo ""
    echo "🖥️  ============================================="
    echo "🖥️  MACHINES THAT WILL BE CONFIGURED"
    echo "🖥️  ============================================="
    
    # Try to extract masters information
    echo "📋 MASTERS:"
    if command -v yq >/dev/null 2>&1; then
        # If yq is available, use it for better parsing
        yq eval '.all.children.masters.hosts | to_entries | .[] | "   🔴 " + .key + " -> " + .value.ansible_host' "$inventory_file" 2>/dev/null || {
            # Fallback to grep/awk if yq fails
            grep -A 20 "masters:" "$inventory_file" | grep -E "ansible_host:" | head -10 | while read line; do
                host_name=$(echo "$line" | grep -B1 "ansible_host" "$inventory_file" | grep -v "ansible_host" | tail -1 | sed 's/://g' | sed 's/^ *//g')
                host_ip=$(echo "$line" | awk '{print $2}')
                echo "   🔴 $host_name -> $host_ip"
            done
        }
    else
        # Alternative method without yq
        awk '
        /^[[:space:]]*masters:/ { in_masters=1; next }
        /^[[:space:]]*[a-z-]+:/ && !/^[[:space:]]*hosts:/ && in_masters { in_masters=0 }
        /^[[:space:]]*hosts:/ && in_masters { in_hosts=1; next }
        /^[[:space:]]*[a-z-]+:/ && !/^[[:space:]]*ansible_host:/ && in_hosts && in_masters { 
            gsub(/:/, "", $1); gsub(/^[[:space:]]*/, "", $1); current_host=$1; next 
        }
        /^[[:space:]]*ansible_host:/ && in_hosts && in_masters && current_host { 
            gsub(/^[[:space:]]*ansible_host:[[:space:]]*/, "", $0)
            print "   🔴 " current_host " -> " $0
            current_host=""
        }
        ' "$inventory_file"
    fi
    
    echo ""
    echo "📋 WORKERS:"
    # Check if workers are defined - improved logic for empty workers section
    # Handle different empty worker formats: hosts: {} or empty hosts section
    worker_count=0
    
    # Check if workers section exists and has actual hosts with ansible_host
    if grep -q "workers:" "$inventory_file"; then
        # Look for actual host definitions under workers (not just empty {})
        worker_hosts_section=$(grep -A 50 "workers:" "$inventory_file" | grep -A 30 "hosts:" | head -30)
        
        # Count actual ansible_host entries in workers section
        if echo "$worker_hosts_section" | grep -q "ansible_host:" 2>/dev/null; then
            worker_count=$(echo "$worker_hosts_section" | grep -c "ansible_host:" 2>/dev/null || echo "0")
        fi
        
        # Additional check for empty hosts: {} format
        if echo "$worker_hosts_section" | grep -q "hosts: {}" 2>/dev/null; then
            worker_count=0
        fi
    fi
    
    # Ensure worker_count is a valid integer
    if [[ -z "$worker_count" ]] || [[ ! "$worker_count" =~ ^[0-9]+$ ]]; then
        worker_count=0
    fi
    
    if [ "$worker_count" -gt 0 ]; then
        if command -v yq >/dev/null 2>&1; then
            yq eval '.all.children.workers.hosts | to_entries | .[] | "   🟢 " + .key + " -> " + .value.ansible_host' "$inventory_file" 2>/dev/null || {
                # Fallback for workers
                awk '
                /^[[:space:]]*workers:/ { in_workers=1; next }
                /^[[:space:]]*[a-z-]+:/ && !/^[[:space:]]*hosts:/ && in_workers { in_workers=0 }
                /^[[:space:]]*hosts:/ && in_workers { in_hosts=1; next }
                /^[[:space:]]*[a-z-]+:/ && !/^[[:space:]]*ansible_host:/ && in_hosts && in_workers { 
                    gsub(/:/, "", $1); gsub(/^[[:space:]]*/, "", $1); current_host=$1; next 
                }
                /^[[:space:]]*ansible_host:/ && in_hosts && in_workers && current_host { 
                    gsub(/^[[:space:]]*ansible_host:[[:space:]]*/, "", $0)
                    print "   🟢 " current_host " -> " $0
                    current_host=""
                }
                ' "$inventory_file"
            }
        else
            awk '
            /^[[:space:]]*workers:/ { in_workers=1; next }
            /^[[:space:]]*[a-z-]+:/ && !/^[[:space:]]*hosts:/ && in_workers { in_workers=0 }
            /^[[:space:]]*hosts:/ && in_workers { in_hosts=1; next }
            /^[[:space:]]*[a-z-]+:/ && !/^[[:space:]]*ansible_host:/ && in_hosts && in_workers { 
                gsub(/:/, "", $1); gsub(/^[[:space:]]*/, "", $1); current_host=$1; next 
            }
            /^[[:space:]]*ansible_host:/ && in_hosts && in_workers && current_host { 
                gsub(/^[[:space:]]*ansible_host:[[:space:]]*/, "", $0)
                print "   🟢 " current_host " -> " $0
                current_host=""
            }
            ' "$inventory_file"
        fi
    else
        echo "   ℹ️  No workers defined - masters will function as workers"
    fi
    
    echo "🖥️  ============================================="
    echo ""
}

# Function for deployment confirmation
confirm_deployment() {
    local check_mode="$1"
    
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        echo "⏩ Auto-confirmation enabled, continuing..."
        echo ""
        return 0
    fi
    
    if [[ -n "$check_mode" ]]; then
        echo "❓ Continue with DRY-RUN? (no changes will be applied) [y/N]: "
    else
        echo "⚠️  WARNING! REAL changes will be applied to the machines listed above."
        echo ""
        echo "❓ Continue with deployment? [y/N]: "
    fi
    
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS]|[sS])
            echo "✅ Confirmed. Continuing with deployment..."
            echo ""
            return 0
            ;;
        *)
            echo "❌ Cancelled by user."
            exit 1
            ;;
    esac
}

# Check for help request
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Configure default values (UPDATED)
: ${AF_USERNAME:="sa_tdi-caas-r"}
: ${KUBE_VERSION:="1.32.2-1.1"}
: ${CRI_TOOLS_VERSION:="1.32.0-1.1"}
: ${KUBE_VIP_VERSION:="v0.6.4"}
: ${CONTAINERD_VERSION:="1.7.22"}
: ${PAUSE_VERSION:="3.10"}
: ${CNI_PLUGIN_VERSION:="v1.4.0"}
: ${DTH_INTERFACE:="ens7"}
: ${HOST_INTERFACE:="ens4"}
: ${ANSIBLE_SSH_USER:="ubuntu"}
: ${INVENTORY_FILE:="inventory/test.yml"}

# Variables that MUST be defined
REQUIRED_VARS=(
    "AF_API_TOKEN"
    "K8S_API_IP"
    "APT_PROXY"
    "DTH_INTERFACE"
    "HOST_INTERFACE"
)

# Variables that are OPTIONAL
OPTIONAL_VARS=(
    "OAM_FIP_IP"
)

# CAAS_SA_AF_TOKEN is automatically set equal to AF_API_TOKEN
: ${CAAS_SA_AF_TOKEN:="$AF_API_TOKEN"}

# Process arguments to detect custom inventory and auto-confirm
CUSTOM_INVENTORY=""
ANSIBLE_ARGS=""
AUTO_CONFIRM="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            CUSTOM_INVENTORY="$2"
            shift 2
            ;;
        -y|--yes)
            AUTO_CONFIRM="true"
            shift
            ;;
        *)
            ANSIBLE_ARGS="$ANSIBLE_ARGS $1"
            shift
            ;;
    esac
done

# Determine which inventory to use
if [[ -n "$CUSTOM_INVENTORY" ]]; then
    FINAL_INVENTORY="$CUSTOM_INVENTORY"
else
    FINAL_INVENTORY="$INVENTORY_FILE"
fi

# Verify that inventory exists
if [[ ! -f "$FINAL_INVENTORY" ]]; then
    echo "❌ Error: Inventory file does not exist: $FINAL_INVENTORY"
    echo ""
    echo "💡 Available inventories:"
    find inventory/ -name "*.yml" 2>/dev/null | sed 's/^/   - /' || echo "   - inventory/hosts.yml (create from example)"
    exit 1
fi

# Check variables only if not listing tags or asking for help
if [[ ! "$ANSIBLE_ARGS" =~ --list-tags ]] && [[ ! "$ANSIBLE_ARGS" =~ --help ]]; then
    missing_vars=()
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo "❌ Error: The following variables are not defined:"
        printf "   - %s\n" "${missing_vars[@]}"
        echo ""
        echo "💡 Suggestion: "
        echo "   1. cp set-vars-example.sh set-vars.sh"
        echo "   2. nano set-vars.sh  # Adjust values"
        echo "   3. source set-vars.sh"
        echo "   4. ./deploy.sh"
        echo ""
        echo "For more information: ./deploy.sh --help"
        exit 1
    fi
fi

# Detect execution type based on arguments
check_mode=""
tags_info=""
if [[ "$ANSIBLE_ARGS" =~ --check ]]; then
    check_mode=" (DRY-RUN - NO CHANGES)"
fi

if [[ "$ANSIBLE_ARGS" =~ --tags ]]; then
    # Extract tags from command
    tags_arg=$(echo "$ANSIBLE_ARGS" | grep -o -- '--tags [^[:space:]]*' | cut -d' ' -f2)
    tags_info=" - Tags: $tags_arg"
fi

if [[ "$ANSIBLE_ARGS" =~ --skip-tags ]]; then
    # Extract skip-tags from command
    skip_tags_arg=$(echo "$ANSIBLE_ARGS" | grep -o -- '--skip-tags [^[:space:]]*' | cut -d' ' -f2)
    tags_info="$tags_info - Skip Tags: $skip_tags_arg"
fi

# Show deployment information (only if variables are set)
if [ ${#missing_vars[@]} -eq 0 ]; then
    echo "============================================="
    echo "🚀 Kubernetes Cluster Deployment$check_mode"
    echo "============================================="
    echo "📂 Inventory: $FINAL_INVENTORY"
    echo "📍 API IP: $K8S_API_IP"
    echo "🔌 DTH Interface: $DTH_INTERFACE"
    echo "🖥️  Host Interface: $HOST_INTERFACE"
    echo "📦 Kubernetes: $KUBE_VERSION"
    echo "🐳 ContainerD: $CONTAINERD_VERSION"
    echo "🔧 Kube-VIP: $KUBE_VIP_VERSION"
    echo "👤 SSH User: $ANSIBLE_SSH_USER"
    echo "🏢 Artifactory User: $AF_USERNAME"
    echo "🌐 APT Proxy: $APT_PROXY"
    if [[ -n "$OAM_FIP_IP" ]]; then
        echo "🔗 OAM FIP: $OAM_FIP_IP"
    fi
    if [[ -n "$tags_info" ]]; then
        echo "🏷️ Execution$tags_info"
    fi
    echo "============================================="
    
    # Show host information from inventory
    show_hosts_info "$FINAL_INVENTORY"
    
    # Check connectivity to hosts before starting (only for real executions)
    if [[ ! "$ANSIBLE_ARGS" =~ --check ]] && [[ ! "$ANSIBLE_ARGS" =~ --tags.*(prep|preparation) ]] || [[ "$ANSIBLE_ARGS" =~ --tags.*prep.* ]]; then
        echo "🔍 Verifying connectivity to hosts..."
        if ! ansible all -i "$FINAL_INVENTORY" -m ping --one-line >/dev/null 2>&1; then
            echo "⚠️  Warning: Some hosts are not accessible"
            echo "   Check inventory and SSH connectivity"
            echo ""
        else
            echo "✅ Connectivity OK"
            echo ""
        fi
    fi
    
    # CONFIRMATION BEFORE CONTINUING
    if [[ "$ANSIBLE_ARGS" =~ --check ]]; then
        confirm_deployment "dry-run"
    else
        confirm_deployment
    fi
fi

# Prepare extra variables for ansible-playbook
EXTRA_VARS=(
  "-e af_username=$AF_USERNAME"
  "-e af_api_token=$AF_API_TOKEN"
  "-e caas_sa_af_token=$CAAS_SA_AF_TOKEN"
  "-e kube_version=$KUBE_VERSION"
  "-e kube_vip_version=$KUBE_VIP_VERSION"
  "-e k8s_api_ip=$K8S_API_IP"
  "-e dth_interface=$DTH_INTERFACE"
  "-e host_interface=$HOST_INTERFACE"
  "-e apt_proxy=$APT_PROXY"
  "-e containerd_version=$CONTAINERD_VERSION"
  "-e cri_tools_version=$CRI_TOOLS_VERSION"
  "-e pause_version=$PAUSE_VERSION"
  "-e cni_plugin_version=$CNI_PLUGIN_VERSION"
  "-e ansible_ssh_user=$ANSIBLE_SSH_USER"
)

# Add optional variables if they are defined
if [[ -n "$OAM_FIP_IP" ]]; then
    EXTRA_VARS+=("-e oam_fip_ip=$OAM_FIP_IP")
fi

# Execute playbook with all variables
echo "============================================="
echo "▶️  EXECUTING ANSIBLE-PLAYBOOK"
echo "============================================="
echo "📂 Inventory: $FINAL_INVENTORY"
echo "🎯 Command: ansible-playbook -i $FINAL_INVENTORY k8s-cluster.yml"
if [[ -n "$ANSIBLE_ARGS" ]]; then
    echo "⚙️  Additional arguments: $ANSIBLE_ARGS"
fi
echo "============================================="
echo ""

ansible-playbook -i "$FINAL_INVENTORY" k8s-cluster.yml \
  "${EXTRA_VARS[@]}" \
  $ANSIBLE_ARGS

echo ""
if [[ "$ANSIBLE_ARGS" =~ --check ]]; then
    echo "============================================="
    echo "✅ Dry-run completed!"
    echo "============================================="
    echo "💡 The changes shown above would be applied"
    echo "   in a real execution (without --check)"
    echo ""
else
    echo "============================================="
    echo "🎉 Deployment completed!"
    echo "============================================="
    echo ""
    
    # Show next steps based on what was executed
    if [[ "$ANSIBLE_ARGS" =~ --tags.*prep ]] || [[ -z "$tags_info" ]]; then
        echo "📋 Recommended next steps:"
        if [[ "$ANSIBLE_ARGS" =~ --tags.*prep ]]; then
            echo "   ./deploy.sh --tags master-init    # Initialize cluster"
        elif [[ -z "$tags_info" ]]; then
            echo "   ssh $(grep -A1 'caas-master-1:' $FINAL_INVENTORY | grep ansible_host | awk '{print $2}') 'kubectl get nodes'  # Verify cluster"
            echo "   # Install CNI plugin (cluster will remain NotReady without it)"
            if [[ -n "$OAM_FIP_IP" ]]; then
                echo "   # MetalLB OAM configured with IP: $OAM_FIP_IP"
            fi
        fi
        echo ""
    fi
    
    echo "⚠️  IMPORTANT: Remove sa_tdi-caas credentials after installation:"
    echo "   - Environment variables (unset AF_* CAAS_*)"
    echo "   - /etc/containerd/config.toml on all nodes"
    echo ""
    
    if [[ ! "$ANSIBLE_ARGS" =~ --tags ]] || [[ "$ANSIBLE_ARGS" =~ --tags.*(config|finalize) ]]; then
        echo "🔍 To verify the cluster:"
        echo "   kubectl get nodes"
        echo "   kubectl get pods -A"
        if [[ -n "$OAM_FIP_IP" ]]; then
            echo "   kubectl get ipaddresspools -n kube-system"
            echo "   kubectl get l2advertisements -n kube-system"
        fi
        echo ""
    fi
fi