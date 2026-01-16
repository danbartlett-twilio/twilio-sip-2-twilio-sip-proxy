# Security Group for Kamailio Instances
resource "aws_security_group" "kamailio" {
  name        = "${var.project_name}-kamailio-sg"
  description = "Security group for Kamailio SIP proxy instances"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-kamailio-sg"
  }
}

# Inbound Rules

# SIP UDP from Twilio IPs
resource "aws_security_group_rule" "sip_udp_twilio" {
  count             = length(var.twilio_ip_cidrs)
  type              = "ingress"
  from_port         = 5060
  to_port           = 5060
  protocol          = "udp"
  cidr_blocks       = [var.twilio_ip_cidrs[count.index]]
  security_group_id = aws_security_group.kamailio.id
  description       = "SIP UDP from Twilio (${var.twilio_ip_cidrs[count.index]})"
}

# Health check from NLB (TCP 5060)
resource "aws_security_group_rule" "health_check" {
  type              = "ingress"
  from_port         = 5060
  to_port           = 5060
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.kamailio.id
  description       = "Health check from NLB"
}

# SIP UDP from NLB (for UDP traffic forwarding from NLB in public subnet)
resource "aws_security_group_rule" "sip_udp_nlb" {
  type              = "ingress"
  from_port         = 5060
  to_port           = 5060
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.kamailio.id
  description       = "SIP UDP from NLB subnet"
}

# Outbound Rules

# Allow all outbound traffic
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.kamailio.id
  description       = "Allow all outbound traffic"
}
