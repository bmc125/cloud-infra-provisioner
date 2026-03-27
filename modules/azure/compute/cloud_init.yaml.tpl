#cloud-config
# modules/azure/compute/cloud_init.yaml.tpl
# Cloud-init runs on first boot. Azure injects this via custom_data.
# Equivalent to AWS user_data and GCP startup_script.

package_update: true
package_upgrade: true

packages:
  - curl
  - jq

runcmd:
  - |
    METADATA=$(curl -sf -H "Metadata:true" \
      "http://169.254.169.254/metadata/instance?api-version=2021-02-01")
    VM_NAME=$(echo $METADATA | jq -r '.compute.name')
    LOCATION=$(echo $METADATA | jq -r '.compute.location')

    cat > /etc/instance-info << EOF
    PROJECT=${project}
    ENVIRONMENT=${environment}
    VM_NAME=$VM_NAME
    LOCATION=$LOCATION
    BOOTSTRAP_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    EOF

    echo "Bootstrap complete for ${project}-${environment} ($VM_NAME in $LOCATION)"
