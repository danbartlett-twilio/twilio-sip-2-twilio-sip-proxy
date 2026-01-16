output "nlb_elastic_ip" {
  description = "Elastic IP address of the Network Load Balancer (for inbound traffic from source Twilio)"
  value       = aws_eip.nlb.public_ip
}

output "nat_gateway_ip" {
  description = "NAT Gateway Elastic IP (for outbound traffic to destination Twilio) - WHITELIST THIS IN DESTINATION TWILIO"
  value       = aws_eip.nat.public_ip
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.kamailio.dns_name
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.kamailio.name
}

output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.kamailio.arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "twilio_twiml" {
  description = "TwiML to use in source Twilio account"
  value       = <<-EOT
    <Response>
      <Dial>
        <Sip>sip:extension@${aws_eip.nlb.public_ip}:5060</Sip>
      </Dial>
    </Response>
  EOT
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    IMPORTANT: Whitelist NAT Gateway IP in Destination Twilio IP ACL

    1. Add ${aws_eip.nat.public_ip}/32 to DESTINATION Twilio IP ACL (for outbound traffic)
    2. Update SOURCE Twilio TwiML to point to NLB: ${aws_eip.nlb.public_ip}
    3. Wait ~8-10 minutes for instances to become healthy
    4. Check target health: AWS Console → EC2 → Target Groups → ${aws_lb_target_group.kamailio.name}
    5. Test with Twilio call
    6. Monitor Auto Scaling: AWS Console → EC2 → Auto Scaling Groups → ${aws_autoscaling_group.kamailio.name}
    7. Access instances via Session Manager if needed
  EOT
}

output "monitoring_urls" {
  description = "AWS Console URLs for monitoring"
  value       = <<-EOT
    NLB: https://console.aws.amazon.com/ec2/v2/home?region=${var.aws_region}#LoadBalancers:
    ASG: https://console.aws.amazon.com/ec2/v2/home?region=${var.aws_region}#AutoScalingGroups:
    Target Group: https://console.aws.amazon.com/ec2/v2/home?region=${var.aws_region}#TargetGroups:
  EOT
}
