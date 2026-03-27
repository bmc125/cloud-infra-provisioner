# modules/security/main.tf
#
# Creates security groups for application and bastion tiers.
# Rule: no 0.0.0.0/0 on SSH in non-dev environments.
# The validation script enforces this post-deploy.

# --- Application Security Group ------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.project}-${var.environment}-app-sg"
  description = "Application tier — allows HTTPS inbound, all outbound"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-app-sg"
  })

  # Explicit lifecycle: create before destroy prevents downtime when rules change.
  lifecycle {
    create_before_destroy = true
  }
}

# Ingress rules as separate resources — easier to manage and diff than inline rules.
# Inline rules and separate aws_security_group_rule resources conflict; pick one.

resource "aws_security_group_rule" "app_https_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.app.id
  description       = "HTTPS from allowed CIDRs"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.allowed_ingress_cidrs
}

resource "aws_security_group_rule" "app_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.app.id
  description       = "HTTP — redirect to HTTPS at the app layer"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.allowed_ingress_cidrs
}

resource "aws_security_group_rule" "app_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.app.id
  description       = "All outbound — instances need to reach package repos, APIs"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# --- Bastion Security Group ----------------------------------------------------
# Only created when enable_bastion = true. In prod you should use SSM Session
# Manager instead of a bastion — this exists for dev/learning purposes.

resource "aws_security_group" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name        = "${var.project}-${var.environment}-bastion-sg"
  description = "Bastion host — SSH restricted to known CIDRs only"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-bastion-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "bastion_ssh_inbound" {
  count = var.enable_bastion ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.bastion[0].id
  description       = "SSH from known IPs only — NEVER 0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.bastion_allowed_cidrs
}

resource "aws_security_group_rule" "bastion_all_outbound" {
  count = var.enable_bastion ? 1 : 0

  type              = "egress"
  security_group_id = aws_security_group.bastion[0].id
  description       = "All outbound"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# --- IAM Instance Profile ------------------------------------------------------
# EC2 instances need this to use SSM Session Manager (the preferred access method)
# and to write to CloudWatch Logs.

resource "aws_iam_role" "ec2_instance" {
  name = "${var.project}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_instance.name

  tags = var.common_tags
}
