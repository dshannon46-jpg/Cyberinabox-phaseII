#!/bin/bash
#
# Module 30: Install Graylog
# Centralized log management with Elasticsearch
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load installation variables
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/install_vars.sh"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [30-GRAYLOG] $*"
}

log "Installing Graylog log management..."

# Install prerequisites
log "Installing Java and MongoDB..."
dnf install -y java-17-openjdk-headless mongodb-org mongodb-org-server

# Install Elasticsearch
log "Installing Elasticsearch..."
dnf install -y elasticsearch-oss

# Configure Elasticsearch for Graylog
log "Configuring Elasticsearch..."
cat > /etc/elasticsearch/elasticsearch.yml <<EOF
cluster.name: graylog
node.name: \${HOSTNAME}
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
action.auto_create_index: false
EOF

# Start Elasticsearch
systemctl daemon-reload
systemctl enable --now elasticsearch
sleep 10

log "✓ Elasticsearch installed"

# Install Graylog
log "Installing Graylog server..."
dnf install -y graylog-server

# Generate password secret
PASSWORD_SECRET=$(pwgen -N 1 -s 96)
ADMIN_PASSWORD_SHA2=$(echo -n "${ADMIN_PASSWORD}" | sha256sum | cut -d" " -f1)

# Configure Graylog
log "Configuring Graylog..."
cat > /etc/graylog/server/server.conf <<EOF
is_leader = true
node_id_file = /etc/graylog/server/node-id
password_secret = ${PASSWORD_SECRET}
root_username = admin
root_password_sha2 = ${ADMIN_PASSWORD_SHA2}
root_email = ${ADMIN_EMAIL}
root_timezone = ${TIMEZONE}

http_bind_address = ${DC1_IP}:9000
http_external_uri = https://graylog.${DOMAIN}/

elasticsearch_hosts = http://127.0.0.1:9200
mongodb_uri = mongodb://localhost/graylog

message_journal_enabled = true
message_journal_dir = /var/lib/graylog-server/journal

allow_leading_wildcard_searches = true
allow_highlighting = true
EOF

# Configure firewall
log "Configuring firewall..."
firewall-cmd --permanent --add-port=9000/tcp  # Graylog web
firewall-cmd --permanent --add-port=514/tcp   # Syslog
firewall-cmd --permanent --add-port=514/udp   # Syslog
firewall-cmd --permanent --add-port=1514/tcp  # Graylog syslog
firewall-cmd --reload

log "✓ Firewall configured"

# Start services
log "Starting Graylog services..."
systemctl enable --now mongodb
systemctl enable --now graylog-server

# Wait for Graylog to start
log "Waiting for Graylog to initialize (this may take 60 seconds)..."
sleep 60

if systemctl is-active --quiet graylog-server; then
    log "✓ Graylog is running"
else
    log "ERROR: Graylog failed to start"
    systemctl status graylog-server
    exit 1
fi

echo ""
log "=========================================="
log "Graylog Installation Summary"
log "=========================================="
log "✓ Graylog server installed"
log "✓ Elasticsearch configured"
log "✓ MongoDB configured"
log ""
log "Web Interface: http://${DC1_IP}:9000"
log "Username: admin"
log "Password: [See CREDENTIALS file]"
log ""
log "Syslog Input: ${DC1_IP}:514 (TCP/UDP)"
log ""

exit 0
