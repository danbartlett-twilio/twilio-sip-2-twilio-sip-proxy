# Kamailio SIP Proxy - Load Balanced Architecture

Production-ready, auto-scaling Kamailio SIP proxy for routing calls between Twilio accounts.

## Architecture

```
                    Internet
                       |
     ┌─────────────────┴─────────────────┐
     ↓ (inbound)                         ↓ (outbound)
[NLB - EIP 1]                    [NAT Gateway - EIP 2]
(Public Subnet)                   (Public Subnet)
     ↓                                    ↑
  Private Subnet (us-east-1a)            |
     ↓                                    |
  Kamailio Instances ──────────────────→ |
  (Auto Scaling: 2-10)
  - No public IPs
  - Inbound via NLB
  - Outbound via NAT Gateway
```

**Two Elastic IPs:**
- **NLB EIP**: For inbound traffic from source Twilio (configure in source TwiML)
- **NAT Gateway EIP**: For outbound traffic to destination Twilio (whitelist in destination IP ACL)

## Key Features

- **High Availability**: Multi-AZ deployment with 2+ instances
- **Auto Scaling**: Automatically scales based on CPU and network traffic
- **Load Balancing**: Network Load Balancer distributes SIP traffic
- **Session Persistence**: Source IP stickiness for SIP dialog continuity
- **Health Checks**: Automatic instance replacement on failure
- **Zero-Downtime Updates**: Rolling instance refresh for config changes
- **AWS Console Access**: Session Manager (no SSH required)

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** installed (v1.0+)
3. **AWS CLI** configured with profile
4. **Two Twilio Accounts**:
   - Source account with phone number
   - Destination account with SIP domain configured

## Quick Start

### 1. Configure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Required
aws_profile = "your-profile-name"

# Optional: adjust scaling
asg_min_size = 2
asg_max_size = 10
asg_desired_capacity = 2

# Optional: change instance size
instance_type = "t3.small"  # or t3.medium, t3.large, etc.

# Optional: override destination domain
# destination_twilio_domain = "your-account.sip.twilio.com"
```

### 2. Deploy

```bash
cd terraform

# Initialize
terraform init

# Review plan
terraform plan

# Deploy (takes 5-10 minutes)
terraform apply
```

### 3. Configure Twilio

After deployment, Terraform outputs two Elastic IPs.

**Destination Twilio Account:**
1. Go to Elastic SIP Trunking → IP Access Control Lists
2. Add the **NAT Gateway IP** with `/32` CIDR (this is the outbound IP from instances)
3. Example: `52.123.45.67/32` (from `nat_gateway_ip` output)

**Source Twilio Account:**
1. Go to Phone Numbers → Select your number
2. Under Voice & Fax, use TwiML with the **NLB IP**:

```xml
<Response>
  <Dial>
    <Sip>sip:EXTENSION@NLB_IP:5060</Sip>
  </Dial>
</Response>
```

Example: `sip:test@44.199.36.104:5060` (from `nlb_elastic_ip` output)

### 4. Test

Make a test call to your source Twilio number. The call should:
1. Hit the NLB
2. Route to one of the Kamailio instances
3. Forward to destination Twilio SIP domain
4. Complete successfully

## Monitoring

### AWS Console

**Auto Scaling Group:**
```
EC2 → Auto Scaling Groups → kamailio-lb-asg
```
- View current instances
- See scaling history
- Adjust min/max/desired capacity

**Network Load Balancer:**
```
EC2 → Load Balancers → kamailio-lb-nlb
```
- View health status
- See traffic metrics
- Check target health

**Target Group:**
```
EC2 → Target Groups → kamailio-lb-tg
```
- See healthy/unhealthy instances
- View health check status
- Verify registration

### CloudWatch Metrics

Key metrics to monitor:
- **ASG**: `GroupDesiredCapacity`, `GroupInServiceInstances`
- **NLB**: `ActiveFlowCount`, `ProcessedBytes`, `HealthyHostCount`
- **Target Group**: `TargetResponseTime`, `UnHealthyHostCount`

### Instance Logs

Access any instance via Session Manager:

```bash
# In AWS Console: EC2 → Instances → Select instance → Connect → Session Manager

# View Kamailio logs
sudo tail -f /var/log/syslog | grep kamailio

# Check Kamailio status
sudo systemctl status kamailio

# View configuration
sudo cat /etc/kamailio/kamailio.cfg | grep -E "listen=|advertise|destination"
```

## Scaling

### Manual Scaling

Update `terraform.tfvars`:

```hcl
asg_desired_capacity = 5  # Scale to 5 instances
```

Then apply:

```bash
terraform apply
```

### Auto Scaling Triggers

The ASG automatically scales based on:

**Scale Out (add instances):**
- CPU > 70% for 2 consecutive periods
- Network In > 50 MB/s average

**Scale In (remove instances):**
- CPU < 70% and Network In < 50 MB/s
- Respects min_size limit

### Changing Instance Size

Update `terraform.tfvars`:

```hcl
instance_type = "t3.medium"  # or t3.large, c5.xlarge, etc.
```

Apply with instance refresh:

```bash
terraform apply
```

The ASG will perform a rolling update (50% healthy minimum).

## High Availability

### Health Checks

- **Type**: TCP on port 5060
- **Interval**: 30 seconds
- **Healthy threshold**: 2 consecutive successes
- **Unhealthy threshold**: 2 consecutive failures

If an instance fails health checks:
1. NLB stops sending traffic to it
2. Auto Scaling Group replaces it automatically
3. New instance joins target group within ~5 minutes

### Multi-AZ Deployment

Instances are distributed across 3 availability zones:
- `us-east-1a`
- `us-east-1b`
- `us-east-1c`

If an entire AZ fails, instances in other AZs continue serving traffic.

### Session Persistence

NLB uses **source IP stickiness** to ensure all SIP messages for a dialog (INVITE, ACK, BYE) go to the same instance.

## Troubleshooting

### No Traffic Reaching Instances

**Check:**
1. NLB Target Group health status
2. Security group allows UDP 5060 from Twilio IPs
3. Kamailio is running: `sudo systemctl status kamailio`

**Fix:**
```bash
# Restart instance via AWS Console
# Or access via Session Manager and restart Kamailio
sudo systemctl restart kamailio
```

### Instances Unhealthy in Target Group

**Check:**
```bash
# Access instance via Session Manager
sudo systemctl status kamailio
sudo tail -n 100 /var/log/cloud-init-output.log
```

**Common causes:**
- Kamailio config error (check logs)
- User-data script failed
- Kamailio not listening on port 5060

### Calls Failing with 403 Forbidden

**Check:**
- NAT Gateway Elastic IP (NOT the NLB IP) is whitelisted in destination Twilio IP ACL
- Destination Twilio SIP domain is correct

### Auto Scaling Not Working

**Check:**
```bash
# View ASG scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name kamailio-lb-asg \
  --max-records 20
```

**Common causes:**
- CPU never reaches 70% threshold
- Instance launch failures
- Insufficient IAM permissions

## Configuration Updates

### Changing Kamailio Config

Edit `config/kamailio.cfg` and redeploy:

```bash
terraform apply
```

This will trigger a rolling instance refresh:
1. Launch new instances with new config
2. Wait for them to be healthy
3. Terminate old instances
4. Ensures zero downtime

### Changing User-Data Script

Edit `scripts/user-data.sh` and apply:

```bash
terraform apply
```

Same rolling update process applies.

## Cost Optimization

**Current setup (~$30-60/month):**
- 2 × t3.small instances: ~$30/month
- NLB: ~$16/month (base) + $0.006/GB processed
- Data transfer: Minimal (SIP signaling only)
- Elastic IP: Free (while attached)

**To reduce costs:**
1. Use Spot Instances (risky for production):
   - Add `spot_price` to launch template
   - Can reduce instance costs by 70%

2. Single AZ deployment:
   - Remove 2 availability zones from variables
   - Loses multi-AZ redundancy

3. Smaller instances:
   - Use `t3.micro` (2 vCPU, 1 GB) for light traffic
   - Monitor CPU to ensure sufficient capacity

## Security

### Current Configuration

- **Network**: Public subnets (proven to work with UDP NLB)
- **Access**: AWS Session Manager (no SSH ports open)
- **Encryption**: EBS volumes encrypted
- **Isolation**: Security groups restrict SIP to Twilio IPs only

### Future Enhancements

Can add when needed:
- **Private subnets + NAT Gateway** (requires architectural changes)
- **VPC Flow Logs** for traffic analysis
- **WAF** for DDoS protection (limited effectiveness with UDP)
- **TLS/SRTP** for encrypted SIP signaling

## Comparison to Single EC2

| Feature | Single EC2 | Load Balanced |
|---------|-----------|---------------|
| **Availability** | Single instance | Multi-AZ, 2+ instances |
| **Scalability** | Manual (change instance size) | Auto-scaling (2-10 instances) |
| **Failure Recovery** | Manual replacement | Automatic |
| **Cost** | ~$15/month | ~$30-60/month |
| **Complexity** | Simple | Moderate |
| **Use Case** | POC, testing | Production |

## Next Steps

### Immediate
1. Test with production call volume
2. Monitor CloudWatch metrics
3. Set up CloudWatch alarms (optional)

### Future Enhancements
1. **Monitoring Dashboard**
   - CloudWatch dashboard with key metrics
   - Custom SIP success/failure metrics

2. **Alerting**
   - SNS topic for critical alerts
   - Email/Slack notifications

3. **Call Quality Metrics**
   - Parse Kamailio logs for call analytics
   - Track success rate, latency, error types

4. **Multi-Region**
   - Deploy in second region for disaster recovery
   - Route53 failover between regions

## Support

For issues or questions:
1. Check CloudWatch logs
2. Access instances via Session Manager
3. Review Kamailio logs: `sudo tail -f /var/log/syslog | grep kamailio`
4. Check NLB target health in AWS Console

## References

- [Kamailio Documentation](https://www.kamailio.org/wikidocs/)
- [AWS Network Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)
- [AWS Auto Scaling](https://docs.aws.amazon.com/autoscaling/)
- [Twilio SIP Trunking](https://www.twilio.com/docs/sip-trunking)
- [KAMAILIO_MIGRATION.md](../KAMAILIO_MIGRATION.md) - Background and lessons learned
