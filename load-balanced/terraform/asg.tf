# Data source to get latest Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "kamailio" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.kamailio.name
  }

  vpc_security_group_ids = [aws_security_group.kamailio.id]

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"  # Allow both IMDSv1 and IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  user_data = base64encode(templatefile("${path.module}/../scripts/user-data.sh", {
    destination_domain = var.destination_twilio_domain
    # Use NLB Elastic IP for Via header advertising
    elastic_ip         = aws_eip.nlb.public_ip
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_eip.nlb]
}

# Auto Scaling Group
resource "aws_autoscaling_group" "kamailio" {
  name                = "${var.project_name}-asg"
  # Launch instances in private subnet (first AZ only, matching NLB)
  vpc_zone_identifier = [aws_subnet.private[0].id]
  target_group_arns   = [aws_lb_target_group.kamailio.arn]

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_cooldown          = 60

  launch_template {
    id      = aws_launch_template.kamailio.id
    version = "$Latest"
  }

  # Instance refresh strategy for zero-downtime updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  # Tags
  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  depends_on = [aws_lb_target_group.kamailio]
}

# Auto Scaling Policy - Target Tracking (CPU)
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.project_name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.kamailio.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 70.0
  }
}

# Auto Scaling Policy - Target Tracking (Network In)
resource "aws_autoscaling_policy" "network_in_target" {
  name                   = "${var.project_name}-network-in-target"
  autoscaling_group_name = aws_autoscaling_group.kamailio.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageNetworkIn"
    }

    # Target 50 MB/s average network in
    target_value = 52428800.0
  }
}
