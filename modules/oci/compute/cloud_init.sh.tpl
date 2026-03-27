#!/bin/bash
# modules/oci/compute/cloud_init.sh.tpl
# OCI cloud-init script. Rendered by Terraform templatefile().
# Oracle Linux 8 base.

set -euo pipefail

dnf update -y

# OCI instance metadata endpoint — note different path from AWS
INSTANCE_ID=$(curl -sf http://169.254.169.254/opc/v2/instance/ \
  -H "Authorization: Bearer Oracle" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
DISPLAY_NAME=$(curl -sf http://169.254.169.254/opc/v2/instance/ \
  -H "Authorization: Bearer Oracle" | python3 -c "import sys,json; print(json.load(sys.stdin)['displayName'])")
REGION=$(curl -sf http://169.254.169.254/opc/v2/instance/ \
  -H "Authorization: Bearer Oracle" | python3 -c "import sys,json; print(json.load(sys.stdin)['region'])")

cat > /etc/instance-info << EOF
PROJECT=${project}
ENVIRONMENT=${environment}
INSTANCE_ID=$INSTANCE_ID
DISPLAY_NAME=$DISPLAY_NAME
REGION=$REGION
BOOTSTRAP_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Bootstrap complete for ${project}-${environment} ($DISPLAY_NAME)"
