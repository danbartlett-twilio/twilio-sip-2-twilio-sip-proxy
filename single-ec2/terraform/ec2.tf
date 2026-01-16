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

# Elastic IP
resource "aws_eip" "kamailio" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

# EIP Association
resource "aws_eip_association" "kamailio" {
  instance_id   = aws_instance.kamailio.id
  allocation_id = aws_eip.kamailio.id
}

# EC2 Instance
resource "aws_instance" "kamailio" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids = [aws_security_group.kamailio.id]
  iam_instance_profile   = aws_iam_instance_profile.kamailio.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/../scripts/user-data.sh", {
    destination_domain = var.destination_twilio_domain
    elastic_ip         = aws_eip.kamailio.public_ip
  })

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"  # Allow both IMDSv1 and IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  tags = {
    Name = "${var.project_name}-instance"
  }

  depends_on = [aws_eip.kamailio]
}
