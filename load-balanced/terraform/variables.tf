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
  default     = "kamailio-lb"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
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

variable "twilio_ip_cidrs" {
  description = "List of Twilio IP ranges for SIP access"
  type        = list(string)
  default = [
    # Twilio SIP signaling IPs for us-east-1
    # These cover 54.172.60.0-54.172.61.255
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

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ) - for NLB and NAT Gateway"
  type        = list(string)
  default = [
    "10.0.0.0/24",  # us-east-1a
    "10.0.1.0/24",  # us-east-1b
    "10.0.2.0/24"   # us-east-1c
  ]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ) - for instances"
  type        = list(string)
  default = [
    "10.0.10.0/24",  # us-east-1a
    "10.0.11.0/24",  # us-east-1b
    "10.0.12.0/24"   # us-east-1c
  ]
}

variable "availability_zones" {
  description = "Availability zones for deployment"
  type        = list(string)
  default = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c"
  ]
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 20
}

# Auto Scaling parameters
variable "asg_min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 10
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
}

# Health check parameters
variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive health checks successes required"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive health check failures required"
  type        = number
  default     = 2
}

# NLB parameters
variable "nlb_cross_zone_enabled" {
  description = "Enable cross-zone load balancing for NLB"
  type        = bool
  default     = true
}

variable "nlb_deletion_protection" {
  description = "Enable deletion protection for NLB"
  type        = bool
  default     = false
}
