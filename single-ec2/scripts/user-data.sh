#!/bin/bash
set -e
set -x

# Log all output to user-data log
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "===== Starting Kamailio SIP Proxy Setup ====="
echo "Timestamp: $(date)"

# Update system packages
echo "Updating system packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Get private IP address (EC2 metadata) FIRST
echo "Retrieving EC2 metadata..."

# Get IMDSv2 token (required on newer instances)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)

# Retry logic for metadata service (it might not be ready immediately)
PRIVATE_IP=""
MAX_RETRIES=10
RETRY_COUNT=0

while [ -z "$PRIVATE_IP" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ -n "$TOKEN" ]; then
        # Try with IMDSv2 token
        PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)
    else
        # Fallback to IMDSv1
        PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    fi

    if [ -z "$PRIVATE_IP" ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Attempt $RETRY_COUNT/$MAX_RETRIES: Waiting for metadata service..."
        sleep 2
    fi
done

echo "Private IP: $PRIVATE_IP"

# Verify we got the IP
if [ -z "$PRIVATE_IP" ]; then
    echo "ERROR: Failed to retrieve private IP from metadata service after $MAX_RETRIES attempts!"
    exit 1
fi

# Install Kamailio and utilities
echo "Installing Kamailio..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    kamailio \
    tcpdump \
    net-tools \
    dnsutils \
    curl

# Stop Kamailio immediately after install (it auto-starts)
echo "Stopping Kamailio to configure it..."
systemctl stop kamailio

# Elastic IP is passed as template variable
ELASTIC_IP="${elastic_ip}"
echo "Elastic IP: $ELASTIC_IP"

# Verify Elastic IP
if [ -z "$ELASTIC_IP" ]; then
    echo "ERROR: Elastic IP not provided by Terraform!"
    exit 1
fi

# Destination Twilio domain is passed as template variable
DESTINATION_DOMAIN="${destination_domain}"
echo "Destination domain: $DESTINATION_DOMAIN"

# Verify destination domain
if [ -z "$DESTINATION_DOMAIN" ]; then
    echo "ERROR: Destination domain not provided by Terraform!"
    exit 1
fi

# Backup original Kamailio config
echo "Backing up original Kamailio configuration..."
if [ -f /etc/kamailio/kamailio.cfg ]; then
    cp /etc/kamailio/kamailio.cfg /etc/kamailio/kamailio.cfg.original
fi

# Copy Kamailio configuration from embedded template
echo "Creating Kamailio configuration..."
cat > /etc/kamailio/kamailio.cfg << 'KAMAILIO_CFG_EOF'
#!KAMAILIO
#
# Kamailio SIP Proxy Configuration
# Purpose: Route SIP calls from source Twilio account to destination Twilio account
#

####### Global Parameters #########

# Logging
debug=4
log_stderror=no
log_facility=LOG_LOCAL0
log_prefix="{$mt $hdr(CSeq) $ci} "

# Network settings
listen=udp:PRIVATE_IP_PLACEHOLDER:5060
advertise ELASTIC_IP_PLACEHOLDER:5060

# Multi-homed support (EC2 has both private and public IPs)
mhomed=1

# Fork and run as daemon
fork=yes
children=4

# Disable TCP
disable_tcp=yes

# DNS settings
dns=yes
rev_dns=no
dns_try_ipv6=no

# Aliases
alias=ELASTIC_IP_PLACEHOLDER:5060

####### Modules Section ########

# Module path
mpath="/usr/lib/x86_64-linux-gnu/kamailio/modules/"

# Load modules
loadmodule "tm.so"
loadmodule "tmx.so"
loadmodule "sl.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "maxfwd.so"
loadmodule "textops.so"
loadmodule "siputils.so"
loadmodule "xlog.so"
loadmodule "ctl.so"
loadmodule "kex.so"

# Module parameters
modparam("tm", "failure_reply_mode", 3)
modparam("tm", "fr_timer", 30000)
modparam("tm", "fr_inv_timer", 120000)

modparam("rr", "enable_full_lr", 1)
modparam("rr", "append_fromtag", 0)

####### Routing Logic ########

request_route {
    # Log all incoming requests
    xlog("L_INFO", "===== INCOMING REQUEST =====\n");
    xlog("L_INFO", "Method: $rm | From: $fu | To: $tu | R-URI: $ru\n");
    xlog("L_INFO", "Source IP: $si:$sp\n");

    # Check Max-Forwards to prevent loops
    if (!mf_process_maxfwd_header("70")) {
        xlog("L_WARN", "Too many hops - Max-Forwards exceeded\n");
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    # Handle CANCEL processing
    if (is_method("CANCEL")) {
        if (t_check_trans()) {
            xlog("L_INFO", "CANCEL request - relaying\n");
            route(RELAY);
        }
        exit;
    }

    # Handle retransmissions
    if (!is_method("ACK")) {
        if (t_precheck_trans()) {
            t_check_trans();
            exit;
        }
        t_check_trans();
    }

    # Handle in-dialog requests (has To-tag)
    if (has_totag()) {
        xlog("L_INFO", "In-dialog request detected\n");

        if (loose_route()) {
            xlog("L_INFO", "Loose routing applied\n");
            route(RELAY);
        } else {
            if (is_method("ACK")) {
                if (t_check_trans()) {
                    xlog("L_INFO", "ACK matched transaction\n");
                    route(RELAY);
                }
                exit;
            }
            xlog("L_WARN", "In-dialog request without Route header\n");
            sl_send_reply("404", "Not Here");
        }
        exit;
    }

    # MAIN ROUTING LOGIC: Process INVITE from Twilio only
    # Only accept INVITEs from Twilio IP ranges (54.172.x.x, 54.244.x.x, 177.71.x.x)
    if (is_method("INVITE") && ($si =~ "^54\.172\." || $si =~ "^54\.244\." || $si =~ "^177\.71\.")) {
        xlog("L_INFO", "Twilio INVITE received from $si\n");
        xlog("L_INFO", "Original R-URI: $ru\n");

        # Extract username from Request-URI
        $var(user) = $rU;

        # Rewrite destination to Twilio SIP Domain
        $ru = "sip:" + $var(user) + "@DESTINATION_DOMAIN_PLACEHOLDER";

        xlog("L_INFO", "Rewritten R-URI: $ru\n");

        # Record-Route to stay in signaling path
        record_route();

        # Route the call
        route(RELAY);
        exit;
    }

    # Reject everything else
    xlog("L_WARN", "Rejecting request: method=$rm from IP=$si\n");
    sl_send_reply("403", "Forbidden");
    exit;
}

route[RELAY] {
    xlog("L_INFO", "===== RELAYING REQUEST =====\n");
    xlog("L_INFO", "Final R-URI: $ru\n");

    if (!t_relay()) {
        xlog("L_ERR", "Failed to relay request\n");
        sl_reply_error();
    }

    exit;
}

onreply_route {
    xlog("L_INFO", "===== RESPONSE RECEIVED =====\n");
    xlog("L_INFO", "Status: $rs $rr | From: $fu | To: $tu\n");
    xlog("L_INFO", "Source IP: $si:$sp\n");
}

failure_route[FAIL_ROUTE] {
    xlog("L_INFO", "===== TRANSACTION FAILURE =====\n");
    xlog("L_INFO", "Status: $T_reply_code | Reason: $T_reply_reason\n");
}

branch_route {
    xlog("L_INFO", "===== NEW BRANCH =====\n");
    xlog("L_INFO", "Branch R-URI: $ru\n");
}
KAMAILIO_CFG_EOF

# Replace placeholders in config file
echo "Configuring Kamailio with actual IP addresses..."
echo "  Replacing PRIVATE_IP_PLACEHOLDER with $PRIVATE_IP"
sed -i "s/PRIVATE_IP_PLACEHOLDER/$PRIVATE_IP/g" /etc/kamailio/kamailio.cfg

echo "  Replacing ELASTIC_IP_PLACEHOLDER with $ELASTIC_IP"
sed -i "s/ELASTIC_IP_PLACEHOLDER/$ELASTIC_IP/g" /etc/kamailio/kamailio.cfg

echo "  Replacing DESTINATION_DOMAIN_PLACEHOLDER with $DESTINATION_DOMAIN"
sed -i "s/DESTINATION_DOMAIN_PLACEHOLDER/$DESTINATION_DOMAIN/g" /etc/kamailio/kamailio.cfg

# Verify replacements worked
echo "Verifying replacements..."
if grep -q "PLACEHOLDER" /etc/kamailio/kamailio.cfg; then
    echo "ERROR: Some placeholders were not replaced!"
    grep "PLACEHOLDER" /etc/kamailio/kamailio.cfg
    exit 1
fi

# Verify configuration
echo "Verifying Kamailio configuration..."
if ! kamailio -c -f /etc/kamailio/kamailio.cfg; then
    echo "ERROR: Kamailio configuration validation failed!"
    exit 1
fi

echo "Kamailio configuration is valid!"

# Configure syslog for Kamailio logs
echo "Configuring syslog for Kamailio..."
cat > /etc/rsyslog.d/kamailio.conf << 'EOF'
# Kamailio logging
local0.*    /var/log/kamailio.log
EOF

# Restart rsyslog
systemctl restart rsyslog

# Enable and start Kamailio
echo "Enabling and starting Kamailio service..."
systemctl enable kamailio
systemctl start kamailio

# Wait a moment for service to start
sleep 3

# Check Kamailio status
echo "Checking Kamailio status..."
if systemctl is-active --quiet kamailio; then
    echo "SUCCESS: Kamailio is running!"
    systemctl status kamailio --no-pager
else
    echo "ERROR: Kamailio failed to start!"
    systemctl status kamailio --no-pager
    journalctl -u kamailio -n 50 --no-pager
    exit 1
fi

# Display listening ports
echo "Kamailio listening on:"
netstat -ulnp | grep kamailio || true

# Create a status script for easy checking
cat > /usr/local/bin/kamailio-status.sh << 'EOF'
#!/bin/bash
echo "===== Kamailio Status ====="
systemctl status kamailio --no-pager

echo ""
echo "===== Listening Ports ====="
netstat -ulnp | grep kamailio

echo ""
echo "===== Recent Logs ====="
tail -n 50 /var/log/kamailio.log
EOF

chmod +x /usr/local/bin/kamailio-status.sh

echo "===== Setup Complete ====="
echo "Kamailio SIP Proxy is ready!"
echo ""
echo "Configuration Summary:"
echo "  Private IP: $PRIVATE_IP"
echo "  Elastic IP: $ELASTIC_IP"
echo "  Destination: $DESTINATION_DOMAIN"
echo ""
echo "To check status: sudo /usr/local/bin/kamailio-status.sh"
echo "To view logs: sudo tail -f /var/log/kamailio.log"
echo "To view syslog: sudo tail -f /var/log/syslog | grep kamailio"
