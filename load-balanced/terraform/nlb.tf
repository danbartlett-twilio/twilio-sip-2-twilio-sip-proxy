# Elastic IP for NLB
resource "aws_eip" "nlb" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nlb-eip"
  }
}

# Network Load Balancer
resource "aws_lb" "kamailio" {
  name               = "${var.project_name}-nlb"
  internal           = false
  load_balancer_type = "network"

  # Single subnet (us-east-1a) with single Elastic IP
  subnet_mapping {
    subnet_id     = aws_subnet.public[0].id
    allocation_id = aws_eip.nlb.id
  }

  enable_cross_zone_load_balancing = var.nlb_cross_zone_enabled
  enable_deletion_protection       = var.nlb_deletion_protection

  tags = {
    Name = "${var.project_name}-nlb"
  }
}

# Target Group for Kamailio instances
resource "aws_lb_target_group" "kamailio" {
  name     = "${var.project_name}-tg"
  port     = 5060
  protocol = "UDP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    interval            = var.health_check_interval
    port                = 5060
    protocol            = "TCP"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  # Sticky sessions based on source IP (for SIP dialog continuity)
  stickiness {
    enabled = true
    type    = "source_ip"
  }

  # Deregistration delay
  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# NLB Listener for SIP (UDP 5060)
resource "aws_lb_listener" "sip_udp" {
  load_balancer_arn = aws_lb.kamailio.arn
  port              = "5060"
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kamailio.arn
  }
}
