output "elastic_ip" {
  description = "Elastic IP address of the Kamailio proxy"
  value       = aws_eip.kamailio.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.kamailio.id
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.kamailio.private_ip
}

output "console_access" {
  description = "How to access the instance"
  value       = "Access via AWS Console → EC2 → Instances → ${aws_instance.kamailio.id} → Connect → Session Manager"
}

output "twilio_twiml" {
  description = "TwiML to use in source Twilio account"
  value       = <<-EOT
    <Response>
      <Dial>
        <Sip>sip:extension@${aws_eip.kamailio.public_ip}:5060</Sip>
      </Dial>
    </Response>
  EOT
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    1. Add ${aws_eip.kamailio.public_ip}/32 to destination Twilio IP ACL
    2. Update source Twilio TwiML to point to this proxy
    3. Access instance via AWS Console → EC2 → ${aws_instance.kamailio.id} → Connect → Session Manager
    4. Check Kamailio status: sudo systemctl status kamailio
    5. View logs: sudo tail -f /var/log/kamailio.log
    6. Test with Twilio call
  EOT
}
