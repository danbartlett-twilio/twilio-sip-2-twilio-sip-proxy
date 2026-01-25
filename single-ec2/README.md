# Kamailio SIP Proxy for Twilio-to-Twilio Routing

A stateless SIP proxy built with Kamailio to route calls between two Twilio accounts.

## Architecture

```
Source Twilio Account → Kamailio SIP Proxy → Destination Twilio Account
                         (AWS EC2 + Elastic IP)
```

**Architecture Diagram:**

![Single Instance Architecture](../images/Twilio-SIP-2-Twilio-SIP-Proxy-Single%20Instance.png)

## Features

- **Stateless SIP proxying** - Kamailio handles Via headers and response routing correctly
- **Request-URI rewriting** - Converts IP-based URIs to Twilio FQDN requirements
- **Multi-homed support** - Works with EC2's private IP and Elastic IP configuration
- **Debug logging** - Detailed SIP message logging for troubleshooting
- **Infrastructure as Code** - Complete Terraform deployment

## Prerequisites

1. **AWS Account** with appropriate permissions to create:
   - VPC, Subnets, Internet Gateway
   - EC2 instances, Elastic IPs
   - Security Groups
   - IAM roles and policies

2. **Terraform** installed (v1.0 or later)
   ```bash
   # Install on macOS
   brew install terraform

   # Install on Linux
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
   sudo apt-get update && sudo apt-get install terraform
   ```

3. **AWS CLI** configured with credentials
   ```bash
   # Configure a named profile
   aws configure --profile your-profile-name

   # Or use default profile
   aws configure
   ```

4. **Two Twilio Accounts**:
   - Source account: Where calls originate
   - Destination account: Where calls should be routed

## Project Structure

```
kamailio-proxy/
├── terraform/                    # Terraform infrastructure code
│   ├── main.tf                   # Provider configuration
│   ├── variables.tf              # Input variables
│   ├── vpc.tf                    # VPC and networking
│   ├── security_groups.tf        # Security group rules
│   ├── ec2.tf                    # EC2 instance and Elastic IP
│   ├── iam.tf                    # IAM roles for CloudWatch
│   ├── outputs.tf                # Output values
│   └── terraform.tfvars.example  # Example variables file
├── config/
│   └── kamailio.cfg              # Kamailio configuration template
├── scripts/
│   └── user-data.sh              # EC2 initialization script
├── KAMAILIO_MIGRATION.md         # Background and design decisions
└── README.md                     # This file
```

## Quick Start

### 1. Clone and Configure

```bash
cd kamailio-proxy/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and configure your settings:

```hcl
# AWS profile from ~/.aws/credentials (REQUIRED if not using default)
aws_profile = "your-profile-name"

# Required: enter your Twilio Domain
destination_twilio_domain = "your-account.sip.twilio.com"

# Optional: Your IP for SSH access (only if you need SSH)
# Leave commented out if using AWS Console access (Session Manager)
# your_ip_cidr = "YOUR_IP_HERE/32"

```

### 2. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy (takes 3-5 minutes)
terraform apply
```

### 3. Note the Outputs

After deployment, Terraform will output:

```
elastic_ip = "54.123.45.67"
instance_id = "i-0123456789abcdef"
private_ip = "10.0.1.234"
console_access = "Access via AWS Console → EC2 → Instances → i-0123456789abcdef → Connect → Session Manager"

twilio_twiml = <<EOT
<Response>
  <Dial>
    <Sip>sip:extension@54.123.45.67:5060</Sip>
  </Dial>
</Response>
EOT

next_steps = <<EOT
1. Add 54.123.45.67/32 to destination Twilio IP ACL
2. Update source Twilio TwiML to point to this proxy
3. Access instance via AWS Console → EC2 → i-0123456789abcdef → Connect → Session Manager
4. Check Kamailio status: sudo systemctl status kamailio
5. View logs: sudo tail -f /var/log/kamailio.log
6. Test with Twilio call
EOT
```

### 4. Configure Twilio

#### Destination Twilio Account

1. Go to **Elastic SIP Trunking** → **Your SIP Trunk** → **IP Access Control Lists**
2. Add the Elastic IP from Terraform output (e.g., `54.123.45.67/32`)

#### Source Twilio Account

1. Go to **Phone Numbers** → Select your number
2. Under **Voice & Fax** → **Configure With**, select **TwiML Bin** or **Function**
3. Use the TwiML from Terraform output:

```xml
<Response>
  <Dial>
    <Sip>sip:EXTENSION@YOUR_ELASTIC_IP:5060</Sip>
  </Dial>
</Response>
```

Replace:
- `EXTENSION` with the destination phone number or SIP username
- `YOUR_ELASTIC_IP` with the actual Elastic IP from Terraform

### 5. Verify Deployment

Access the instance via AWS Console:

1. Go to **EC2 Console** → **Instances**
2. Select your instance (use instance ID from Terraform output)
3. Click **Connect** → **Session Manager** → **Connect**

Once connected, run these commands:

```bash
# Check Kamailio is running
sudo systemctl status kamailio

# View recent logs
sudo tail -n 100 /var/log/kamailio.log

# Watch live logs
sudo tail -f /var/log/kamailio.log

# Check listening ports (should see UDP 5060)
sudo netstat -ulnp | grep kamailio

# Use the status script
sudo /usr/local/bin/kamailio-status.sh
```

### 6. Test with Live Call

1. Call your source Twilio number
2. Monitor logs on EC2 instance
3. Expected log flow:

```
===== INCOMING REQUEST =====
Method: INVITE | From: sip:+19494337060@... | To: sip:extension@...
Original R-URI: sip:extension@54.123.45.67:5060
Rewritten R-URI: sip:extension@dantwilio.sip.twilio.com

===== RELAYING REQUEST =====
Final R-URI: sip:extension@dantwilio.sip.twilio.com

===== RESPONSE RECEIVED =====
Status: 100 Trying | From: ... | To: ...

===== RESPONSE RECEIVED =====
Status: 180 Ringing | From: ... | To: ...

===== RESPONSE RECEIVED =====
Status: 200 OK | From: ... | To: ...
```

## Configuration Details

### Kamailio Configuration

Key configuration in `config/kamailio.cfg`:

- **Listen**: Binds to private IP (`10.0.x.x`)
- **Advertise**: Uses Elastic IP in Via headers (for response routing)
- **Multi-homed**: Handles EC2's dual IP configuration
- **Request-URI Rewriting**: Converts incoming SIP URIs to destination Twilio FQDN
- **Record-Route**: Keeps proxy in signaling path for in-dialog requests
- **Debug Logging**: Level 4 for detailed SIP message tracing

### Security Groups

Inbound rules:
- SSH (TCP 22): Optional - only if `your_ip_cidr` is configured
- SIP (UDP 5060): Twilio IP ranges only

Outbound rules:
- All traffic allowed (for destination Twilio communication)

### Instance Access

The instance is configured with AWS Systems Manager (SSM) for console-based access:
- No SSH required - access via AWS Console → Session Manager
- IAM role includes `AmazonSSMManagedInstanceCore` policy
- Supports browser-based shell access to the instance

### Instance Details

- **AMI**: Ubuntu 24.04 LTS (Noble)
- **Instance Type**: t3.small (2 vCPU, 2 GB RAM)
- **Kamailio Version**: 5.7.4 (from Ubuntu apt repository)
- **Storage**: 20 GB GP3 encrypted root volume
- **Region**: us-east-1 (configurable)

## Troubleshooting

### Kamailio Won't Start

Check logs for errors:

```bash
sudo journalctl -u kamailio -n 100 --no-pager
sudo tail -n 50 /var/log/user-data.log
```

Validate configuration:

```bash
sudo kamailio -c -f /etc/kamailio/kamailio.cfg
```

### No Response from Proxy

1. Verify security group allows UDP 5060 from source Twilio IPs
2. Check Kamailio is listening:
   ```bash
   sudo netstat -ulnp | grep 5060
   ```
3. Capture packets to see if traffic is arriving:
   ```bash
   sudo tcpdump -i any port 5060 -n -vv
   ```

### 403 Forbidden from Destination Twilio

1. Verify Elastic IP is whitelisted in destination Twilio IP ACL
2. Check the IP ACL includes the `/32` CIDR notation
3. Verify the SIP trunk is active

### Routing Loop / Self-Forwarding

Check Via headers in logs:

```bash
sudo tcpdump -i any port 5060 -n -vv -A | grep -A 10 "Via:"
```

Verify `advertise` directive is set correctly in `/etc/kamailio/kamailio.cfg`:
- Should be the Elastic IP, not private IP

### Request Timeout

1. Verify DNS resolution works:
   ```bash
   dig dantwilio.sip.twilio.com
   ```

2. Test outbound connectivity:
   ```bash
   nc -vuz dantwilio.sip.twilio.com 5060
   ```

3. Check for firewall/security group blocking outbound UDP 5060

### Update Twilio IP Ranges

Twilio's IP ranges may change. Update in `terraform/variables.tf`:

```hcl
variable "twilio_ip_cidrs" {
  default = [
    "54.172.60.0/23",
    "54.244.51.0/24",
    "177.71.206.0/23"
    # Add new ranges here
  ]
}
```

Then apply:
```bash
terraform apply
```

## Monitoring

### CloudWatch Logs

Instance has CloudWatch agent configured. View logs:

```bash
# AWS CLI
aws logs tail /aws/ec2/kamailio-proxy --follow
```

### Real-time SIP Message Monitoring

Access via AWS Console Session Manager, then run:

```bash
# Live Kamailio logs
sudo tail -f /var/log/kamailio.log

# Full packet capture
sudo tcpdump -i any port 5060 -n -vv -A -s0 -w /tmp/sip-capture.pcap

# To download capture file:
# 1. Upload to S3 from instance (if you've configured AWS CLI on instance)
# 2. Or view logs in CloudWatch Logs
# 3. Or use EC2 Instance Connect to transfer files
```

## Updating Configuration

### Modify Kamailio Config

1. Edit configuration locally: `config/kamailio.cfg`
2. Update infrastructure:
   ```bash
   cd terraform
   terraform apply
   ```
   This will recreate the instance with new configuration.

### Change Destination Twilio Domain

1. Update `terraform/terraform.tfvars`:
   ```hcl
   destination_twilio_domain = "new-account.sip.twilio.com"
   ```

2. Apply changes:
   ```bash
   terraform apply
   ```

## Cleanup

To destroy all infrastructure:

```bash
cd terraform
terraform destroy
```

Confirm by typing `yes` when prompted.

**Note**: This will delete:
- EC2 instance
- Elastic IP
- Security groups
- VPC and all networking resources
- IAM roles

## Cost Estimate

- EC2 t3.small: ~$15/month (on-demand)
- Elastic IP: Free (while associated to running instance)
- Data transfer: Minimal (SIP signaling only, no media)
- CloudWatch Logs: ~$0.50/month (minimal logging)

**Total: ~$15-20/month**

## Advanced Configuration

### Enable TLS/SRTP (Future Enhancement)

Modify `config/kamailio.cfg` to load TLS modules and configure certificates.

### Multi-Instance Deployment (Future Enhancement)

For high availability:
1. Add Application Load Balancer (ALB) with UDP support
2. Create Auto Scaling Group with multiple instances
3. Use shared configuration store (S3 or Parameter Store)

### Rate Limiting (Future Enhancement)

Add Kamailio `pike` module to limit requests per IP:

```kamailio
loadmodule "pike.so"
modparam("pike", "sampling_time_unit", 2)
modparam("pike", "reqs_density_per_unit", 30)
```

## References

- [Kamailio Documentation](https://www.kamailio.org/wikidocs/)
- [Twilio SIP Trunking Guide](https://www.twilio.com/docs/sip-trunking)
- [RFC 3261 - SIP Protocol](https://www.rfc-editor.org/rfc/rfc3261)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues or questions:
1. Review `KAMAILIO_MIGRATION.md` for background and design decisions
2. Check Kamailio logs for detailed SIP message flow
3. Verify security groups and Twilio IP ACL configuration
4. Capture SIP packets with tcpdump for analysis

## License

This project is provided as-is for educational and testing purposes.
