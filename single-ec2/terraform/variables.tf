variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use (from ~/.aws/credentials)"
  type        = string
  default     = null
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "kamailio-proxy"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "destination_twilio_domain" {
  description = "Destination Twilio SIP domain"
  type        = string
  default     = "your-account.sip.twilio.com"
}

variable "your_ip_cidr" {
  description = "Your IP address in CIDR notation for SSH access (e.g., 1.2.3.4/32). Leave null if using AWS Console access only."
  type        = string
  default     = null
}

variable "twilio_ip_cidrs" {
  description = "List of Twilio IP ranges for SIP access"
  type        = list(string)
  default = [
    # Twilio SIP signaling IPs for us-east-1
    # These cover 54.172.60.0-54.172.61.255 (includes .1, .2, .3 seen in tcpdump)
    "54.172.60.0/23",
    # Other Twilio regions (if needed)
    "54.244.51.0/24",
    "177.71.206.0/23"
  ]
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "availability_zone" {
  description = "Availability zone for resources"
  type        = string
  default     = "us-east-1a"
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 20
}
