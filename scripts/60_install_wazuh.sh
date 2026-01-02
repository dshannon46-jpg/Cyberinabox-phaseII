#!/bin/bash
#
# Module 60: Install Wazuh
# Security monitoring, SIEM, and compliance
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load installation variables
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/install_vars.sh"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [60-WAZUH] $*"
}

log "Installing Wazuh security monitoring..."

# Add Wazuh repository
log "Adding Wazuh repository..."
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

cat > /etc/yum.repos.d/wazuh.repo <<EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

# Install Wazuh Manager
log "Installing Wazuh Manager..."
dnf install -y wazuh-manager

log "✓ Wazuh Manager installed"

# Install Wazuh Indexer (OpenSearch)
log "Installing Wazuh Indexer..."
dnf install -y wazuh-indexer

# Configure Wazuh Indexer
log "Configuring Wazuh Indexer..."
cat > /etc/wazuh-indexer/opensearch.yml <<EOF
network.host: "${DC1_IP}"
node.name: "node-1"
cluster.initial_master_nodes:
- "node-1"
cluster.name: "wazuh-cluster"
node.max_local_storage_nodes: 3
path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer

plugins.security.ssl.http.enabled: false
plugins.security.disabled: true
EOF

# Start Wazuh Indexer
systemctl daemon-reload
systemctl enable --now wazuh-indexer

sleep 10

log "✓ Wazuh Indexer started"

# Install Wazuh Dashboard
log "Installing Wazuh Dashboard..."
dnf install -y wazuh-dashboard

# Configure Wazuh Dashboard
log "Configuring Wazuh Dashboard..."
cat > /etc/wazuh-dashboard/opensearch_dashboards.yml <<EOF
server.host: "${DC1_IP}"
server.port: 443
opensearch.hosts: ["http://${DC1_IP}:9200"]
opensearch.ssl.verificationMode: none
EOF

# Start Wazuh Dashboard
systemctl daemon-reload
systemctl enable --now wazuh-dashboard

log "✓ Wazuh Dashboard started"

# Configure Wazuh Manager
log "Configuring Wazuh Manager..."

# Set Wazuh Manager to connect to local indexer
cat >> /var/ossec/etc/ossec.conf <<EOF
<!-- CyberHygiene Configuration -->
<ossec_config>
  <indexer>
    <enabled>yes</enabled>
    <hosts>
      <host>http://${DC1_IP}:9200</host>
    </hosts>
  </indexer>
</ossec_config>
EOF

# Enable NIST 800-171 compliance checks
log "Enabling NIST 800-171 compliance monitoring..."
sed -i 's/<wodle name="sca">/<wodle name="sca" enabled="yes">/' /var/ossec/etc/ossec.conf

# Configure firewall
log "Configuring firewall..."
firewall-cmd --permanent --add-port=1514/tcp  # Wazuh agent enrollment
firewall-cmd --permanent --add-port=1515/tcp  # Wazuh agent events
firewall-cmd --permanent --add-port=55000/tcp # Wazuh API
firewall-cmd --permanent --add-port=9200/tcp  # Wazuh Indexer
firewall-cmd --permanent --add-port=443/tcp   # Wazuh Dashboard
firewall-cmd --reload

log "✓ Firewall configured"

# Start Wazuh Manager
log "Starting Wazuh Manager..."
systemctl enable --now wazuh-manager

sleep 10

if systemctl is-active --quiet wazuh-manager; then
    log "✓ Wazuh Manager is running"
else
    log "ERROR: Wazuh Manager failed to start"
    systemctl status wazuh-manager
    exit 1
fi

# Install Wazuh agent on local system
log "Installing Wazuh agent on local system..."
dnf install -y wazuh-agent

# Configure agent to connect to manager
cat > /var/ossec/etc/ossec.conf <<EOF
<ossec_config>
  <client>
    <server>
      <address>${DC1_IP}</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
  </client>
</ossec_config>
EOF

# Start Wazuh agent
systemctl enable --now wazuh-agent

log "✓ Wazuh Agent installed and started"

# Create initial Wazuh admin user
log "Configuring Wazuh API access..."
/var/ossec/bin/wazuh-keystore -f indexer -k username -v admin
/var/ossec/bin/wazuh-keystore -f indexer -k password -v "${ADMIN_PASSWORD}"

systemctl restart wazuh-manager

echo ""
log "=========================================="
log "Wazuh Installation Summary"
log "=========================================="
log "✓ Wazuh Manager installed"
log "✓ Wazuh Indexer (OpenSearch) installed"
log "✓ Wazuh Dashboard installed"
log "✓ Wazuh Agent installed (local monitoring)"
log ""
log "Web Interface: https://${DC1_IP}"
log "Username: admin"
log "Password: [See CREDENTIALS file]"
log ""
log "Agent Enrollment:"
log "  Server: ${DC1_IP}"
log "  Port: 1514"
log ""
log "Features enabled:"
log "  - File Integrity Monitoring"
log "  - Log Analysis"
log "  - Vulnerability Detection"
log "  - NIST 800-171 Compliance Checks"
log "  - Rootkit Detection"
log ""

exit 0
