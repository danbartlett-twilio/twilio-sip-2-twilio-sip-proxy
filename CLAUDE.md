# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kamailio-based SIP proxy for routing calls between two Twilio accounts. The project provides two deployment architectures:

- **single-ec2/**: POC deployment (1 instance, 1 Elastic IP) - ~$15/month
- **load-balanced/**: Production deployment (2-10 instances, NLB, NAT Gateway, multi-AZ) - ~$45-75/month

Both architectures use identical Kamailio configurations and perform the same core function: receive SIP INVITE from source Twilio → rewrite Request-URI from IP to destination Twilio FQDN → forward to destination Twilio SIP domain.

### Key Architectural Difference

**single-ec2**:
- Instance in public subnet with Elastic IP
- Uses same IP for inbound and outbound
- Whitelist: 1 Elastic IP in destination Twilio

**load-balanced**:
- NLB in public subnet for inbound (1 Elastic IP)
- Instances in private subnets (no public IPs)
- NAT Gateway in public subnet for outbound (1 Elastic IP)
- Whitelist: NAT Gateway IP in destination Twilio (NOT the NLB IP)

## Critical Architectural Context

### Why Kamailio

Kamailio is a mature, production-grade SIP proxy server specifically designed for stateless SIP proxying. It handles:
- Via header manipulation correctly out of the box
- Proper Record-Route and loose routing
- Response routing through Via header stack
- No routing loops with `received` parameters

Key advantages: 20+ years of development, proven with various SIP providers including Twilio, handles edge cases correctly, scales to thousands of concurrent calls.

### AWS Network Architecture Constraints

**Single EC2 Architecture**: Instance in public subnet with single Elastic IP for both inbound and outbound traffic.

**Load-Balanced Architecture**: Uses private subnets + NAT Gateway successfully because inbound and outbound are separate traffic flows:
- **Inbound path**: Source Twilio → NLB (public subnet) → Instances (private subnet)
- **Outbound path**: Instances (private subnet) → NAT Gateway (public subnet) → Destination Twilio

This avoids asymmetric routing issues because:
1. Responses to source Twilio go back through NLB (symmetric to inbound)
2. New requests to destination Twilio go through NAT Gateway (separate flow)

**Previous failed architecture (v3)**: Attempted NLB inbound + NAT Gateway response path for the SAME flow caused asymmetric routing failures.

### Multi-Homed EC2 Configuration

**Single EC2**: Instance has both private and public IPs.
**Load-Balanced**: Instances have only private IPs (no public IPs assigned).

Kamailio must:
- **Listen** on private IP (where traffic arrives from NLB or directly)
- **Advertise** the Elastic IP in Via headers (for proper response routing)
- Set `mhomed=1` to handle multi-homed scenarios correctly

This configuration is critical and appears in both `kamailio.cfg` files as:
```
listen=udp:PRIVATE_IP:5060
listen=tcp:PRIVATE_IP:5060
advertise ELASTIC_IP:5060
mhomed=1
```

**Note**: Load-balanced architecture includes TCP listener for NLB health checks, while UDP is used for SIP traffic.

These placeholders are replaced by the user-data script at instance boot time.

## Common Commands

### Deploying Infrastructure

**Single EC2 (POC/Testing):**
```bash
cd single-ec2/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aws_profile (required)
terraform init
terraform plan
terraform apply
```

**Load Balanced (Production):**
```bash
cd load-balanced/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aws_profile (required), optionally adjust asg_min_size, asg_max_size, instance_type
terraform init
terraform plan
terraform apply
```

### Accessing Instances

No SSH is configured. Access instances via AWS Session Manager:
1. AWS Console → EC2 → Instances
2. Select instance → Connect → Session Manager → Connect

### Debugging Kamailio

**On instance (via Session Manager):**
```bash
# Check if Kamailio is running
sudo systemctl status kamailio

# View live SIP message logs
sudo tail -f /var/log/syslog | grep kamailio

# Check user-data script execution
sudo tail -n 200 /var/log/cloud-init-output.log

# Verify Kamailio configuration
sudo cat /etc/kamailio/kamailio.cfg | grep -E "listen=|advertise|destination"

# Test Kamailio config syntax
sudo kamailio -c -f /etc/kamailio/kamailio.cfg

# Restart Kamailio
sudo systemctl restart kamailio
```

**Capture SIP traffic:**
```bash
# Live capture with headers visible
sudo tcpdump -i any port 5060 -n -vv -A

# Save to file for analysis
sudo tcpdump -i any port 5060 -n -vv -s0 -w /tmp/sip-capture.pcap
```

### Modifying Kamailio Configuration

1. Edit `config/kamailio.cfg` or `scripts/user-data.sh` in the appropriate directory
2. Run `terraform apply` - this triggers instance replacement with new config
3. For load-balanced: instances are replaced via rolling update (50% healthy minimum)

## Key Configuration Patterns

### Kamailio Routing Logic

The core routing in `request_route` block:

1. **IP-based filtering**: Only accept INVITEs from Twilio IP ranges (54.172.*, 54.244.*, 177.71.*)
2. **Request-URI rewriting**: Extract user from incoming R-URI, rewrite domain to destination Twilio FQDN
3. **Record-Route**: Add Record-Route header to stay in signaling path for in-dialog messages (ACK, BYE)
4. **Transaction relay**: Use `t_relay()` from tm module for proper SIP transaction handling

**Critical pattern:**
```kamailio
if (is_method("INVITE") && ($si =~ "^54\.172\." || $si =~ "^54\.244\." || $si =~ "^177\.71\.")) {
    $var(user) = $rU;
    $ru = "sip:" + $var(user) + "@DESTINATION_DOMAIN";
    record_route();
    route(RELAY);
}
```

### User-Data Script Pattern

The `scripts/user-data.sh` must:

1. **Get private IP from EC2 metadata** (with retry logic and IMDSv2 token support)
2. **Stop Kamailio immediately** after apt install (it auto-starts with invalid config)
3. **Create Kamailio config** with PLACEHOLDER values
4. **Replace placeholders** with actual IPs via sed
5. **Verify config** with `kamailio -c`
6. **Start Kamailio** after config is validated

**Critical timing**: Kamailio auto-starts during `apt-get install`, but config doesn't exist yet. Must `systemctl stop kamailio` immediately after installation, then configure, then start.

## Load-Balanced Architecture Specifics

### NLB Configuration

- Single Elastic IP attached to NLB in us-east-1a
- Cross-zone load balancing enabled (distributes to instances in all 3 AZs)
- UDP listener on port 5060
- **Source IP stickiness** enabled (critical for SIP dialog continuity - all messages for a call must go to same instance)

### Health Checks

- TCP health check on port 5060 (Kamailio listens on both UDP and TCP)
- Interval: 30 seconds
- Healthy threshold: 2 consecutive successes
- Unhealthy threshold: 2 consecutive failures

Kamailio doesn't have a built-in HTTP health endpoint, so TCP port check is the simplest reliable method.

### Auto Scaling

ASG scales based on:
- **CPU**: Target 70% average CPU utilization
- **Network In**: Target 50 MB/s average network traffic

Scale out adds instances. Scale in removes instances but respects min_size (default: 2).

### Instance Refresh

When Terraform configuration changes (Kamailio config or user-data script), ASG performs rolling instance refresh:
1. Launch new instances with new config
2. Wait for them to pass health checks
3. Terminate old instances
4. Maintains minimum 50% healthy capacity

This provides zero-downtime config updates.

## Capacity Planning

### Single EC2 (t3.small)
- **Conservative capacity**: 150-200 concurrent calls, 20-30 CPS sustained
- **Tested**: 100 concurrent calls with <10% CPU utilization
- **Recommended limit**: Up to 100 concurrent for light production
- **When to upgrade**: Sustained CPU > 70%, or need high availability

### Load Balanced (t3.small instances)
- **Per instance**: 150-200 concurrent calls, 20-30 CPS sustained
- **2 instances (min)**: 300-400 concurrent calls, 40-60 CPS
- **10 instances (max)**: 1,500-2,000 concurrent calls, 200-300 CPS
- **Scaling time**: 5-7 minutes to add new instance

### Capacity Formula
```
Concurrent Calls = CPS × Average Call Duration (seconds)
Example: 20 CPS × 300 seconds (5 min) = 600 concurrent calls
```

### Real-World Scenarios
- **Small call center** (100-200 concurrent): 2 instances minimum
- **Medium call center** (300-600 concurrent): 3-5 instances
- **Large call center** (1,500-2,500 concurrent): 6-10 instances
- **Enterprise** (3,000+ concurrent): Increase `asg_max_size` beyond 10

### Primary Bottleneck
CPU is the primary bottleneck for SIP message parsing and transaction management. Network and memory are rarely limiting factors.

## Monitoring Recommendations

### Critical Alarms for Load-Balanced
When users ask about monitoring or production readiness, recommend these CloudWatch alarms:

1. **UnHealthyHostCount > 0**: Any unhealthy instance indicates issues
2. **HealthyHostCount < 2**: Loss of redundancy, one failure causes outage
3. **CPU > 80%**: Sustained high CPU, verify auto-scaling is working
4. **GroupDesiredCapacity >= 8**: Approaching max capacity (if max is 10)
5. **HealthyHostCount = 0**: CRITICAL - complete outage

### Monitoring Setup
- See README.md "CloudWatch Monitoring & Alerting" section for complete Terraform examples
- Estimated cost: ~$3/month (5 free alarms + $3 dashboard)
- SNS topics for email/PagerDuty/Slack integration
- CloudWatch dashboard with 4 key widgets

### Key Metrics to Track
- `AWS/NetworkELB`: HealthyHostCount, UnHealthyHostCount, ActiveFlowCount
- `AWS/AutoScaling`: GroupDesiredCapacity, GroupInServiceInstances
- `AWS/EC2`: CPUUtilization (primary capacity indicator)

## Troubleshooting Patterns

### "403 Not relaying" from Kamailio

**Cause**: IP-based filtering in `request_route` rejected the request. Source IP doesn't match Twilio IP regex patterns.

**Debug**: Check Kamailio logs for "Rejecting request" message, verify source IP.

### "Request timeout" from Twilio

**Possible causes**:
1. Kamailio not running (`systemctl status kamailio`)
2. Security group blocking UDP 5060 from Twilio IPs
3. Kamailio config error (check logs)
4. Instance private IP metadata retrieval failed during boot (check `/var/log/cloud-init-output.log`)

### "403 Forbidden" from destination Twilio

**Cause**: Proxy's outbound IP not whitelisted in destination Twilio account's IP ACL.

**Fix**:
- **Single EC2**: Add the Elastic IP with /32 CIDR to destination Twilio SIP Trunk IP ACL
- **Load-Balanced**: Add the NAT Gateway IP (NOT the NLB IP) with /32 CIDR to destination Twilio SIP Trunk IP ACL

### Load-balanced instances unhealthy in target group

1. Access instance via Session Manager
2. Check `sudo systemctl status kamailio`
3. Check `sudo tail -n 200 /var/log/cloud-init-output.log` for user-data errors
4. Verify Kamailio is listening: `sudo netstat -ulnp | grep 5060`

## Twilio Configuration Requirements

### Destination Twilio Account

1. **SIP Trunk** configured with domain (e.g., your-account.sip.twilio.com)
2. **IP ACL** must include proxy Elastic IP with /32 CIDR

### Source Twilio Account

**TwiML** to route calls through proxy:
```xml
<Response>
  <Dial>
    <Sip>sip:EXTENSION@PROXY_ELASTIC_IP:5060</Sip>
  </Dial>
</Response>
```

Where EXTENSION is the destination phone number or SIP username.

## File Structure Critical Points

- **Both architectures** use the same Kamailio config logic (only difference is which Elastic IP is advertised)
- **Terraform state files** are in `single-ec2/terraform/` and `load-balanced/terraform/` - keep them separate
- **config/kamailio.cfg** is a template with PLACEHOLDER values, actual config is generated by user-data script
- **README.md** contains comprehensive documentation including architecture diagrams, configuration guide, troubleshooting, and learnings/gotchas

## Testing Changes

**Recommended flow:**
1. Test changes in `single-ec2` first (faster, cheaper)
2. Make test call from source Twilio number
3. Verify call completes successfully
4. Check Kamailio logs show correct Request-URI rewriting
5. Apply same changes to `load-balanced` if moving to production

**Test call verification checklist:**
- INVITE received from Twilio (check logs)
- Request-URI rewritten from IP to destination FQDN (check logs)
- INVITE forwarded to destination Twilio (check tcpdump or logs)
- Responses (100 Trying, 180 Ringing, 200 OK) received (check logs)
- ACK and BYE handled correctly for full call flow (check logs)
