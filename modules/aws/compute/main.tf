# modules/compute/main.tf
#
# Creates EC2 instances via a Launch Template.
# Using a Launch Template (not aws_instance directly) is the current best practice —
# it supports versioning, Auto Scaling Groups, and Spot instances when you need them later.

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Launch Template -----------------------------------------------------------

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-${var.environment}-"
  description   = "Launch template for ${var.project} ${var.environment} app instances"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  # IMDSv2 required — IMDSv1 is a well-documented security vulnerability.
  # Do not remove this block.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # enforces IMDSv2
    http_put_response_hop_limit = 1
  }

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = false # instances live in private subnets
    security_groups             = [var.security_group_id]
    delete_on_termination       = true
  }

  # EBS root volume — encrypted at rest, always.
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    project     = var.project
    environment = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.project}-${var.environment}-app"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.common_tags, {
      Name = "${var.project}-${var.environment}-root-vol"
    })
  }

  tags = var.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# --- EC2 Instances -------------------------------------------------------------
# In this project we create standalone instances for simplicity.
# When you're ready to add auto-scaling, replace this with aws_autoscaling_group
# pointing at the launch template above.

resource "aws_instance" "app" {
  count = var.instance_count

  # Use the latest version of the launch template
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  subnet_id = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]

  tags = merge(var.common_tags, {
    Name  = "${var.project}-${var.environment}-app-${count.index + 1}"
    Index = tostring(count.index + 1)
  })
}
