# Security Group for Kamailio SIP Proxy
resource "aws_security_group" "kamailio" {
  name        = "${var.project_name}-sg"
  description = "Security group for Kamailio SIP proxy"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# Inbound Rules

# SSH access from your IP (optional - only if your_ip_cidr is provided)
resource "aws_security_group_rule" "ssh" {
  count             = var.your_ip_cidr != null ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.your_ip_cidr]
  security_group_id = aws_security_group.kamailio.id
  description       = "SSH access from admin IP"
}

# SIP UDP from Twilio IPs
resource "aws_security_group_rule" "sip_udp" {
  count             = length(var.twilio_ip_cidrs)
  type              = "ingress"
  from_port         = 5060
  to_port           = 5060
  protocol          = "udp"
  cidr_blocks       = [var.twilio_ip_cidrs[count.index]]
  security_group_id = aws_security_group.kamailio.id
  description       = "SIP UDP from Twilio (${var.twilio_ip_cidrs[count.index]})"
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
