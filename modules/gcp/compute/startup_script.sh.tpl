#!/bin/bash
# modules/gcp/compute/startup_script.sh.tpl
# GCP startup script — runs on first boot and on each restart.
# Keep idempotent: running this twice must not break anything.

set -euo pipefail

# Update packages
apt-get update -y && apt-get upgrade -y || true

# Write instance metadata
INSTANCE_NAME=$(curl -sf -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/name)
ZONE=$(curl -sf -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')

cat > /etc/instance-info << EOF
PROJECT=${project}
ENVIRONMENT=${environment}
INSTANCE_NAME=$INSTANCE_NAME
ZONE=$ZONE
BOOTSTRAP_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Startup complete for ${project}-${environment} ($INSTANCE_NAME in $ZONE)"
