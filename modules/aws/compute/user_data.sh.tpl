#!/bin/bash
# modules/compute/user_data.sh.tpl
# Bootstraps Amazon Linux 2023 instances.
# Rendered by Terraform templatefile() — variables in ${ } are substituted.
# Keep this minimal — configuration management belongs in Ansible/SSM, not user_data.

set -euo pipefail

# Update all packages on first boot
dnf update -y

# Install CloudWatch agent and SSM agent (SSM is pre-installed on AL2023 but update it)
dnf install -y amazon-cloudwatch-agent

# Write instance metadata to a file — useful for debugging
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

cat > /etc/instance-info << EOF
PROJECT=${project}
ENVIRONMENT=${environment}
INSTANCE_ID=$INSTANCE_ID
BOOTSTRAP_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# Start CloudWatch agent with a basic config
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c default || true

echo "Bootstrap complete for ${project}-${environment} ($INSTANCE_ID)"
