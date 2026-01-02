#!/bin/bash
#
# Module 99: Final Verification
# Verify all services are running and accessible
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load installation variables
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/install_vars.sh"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [99-VERIFY] $*"
}

log "Running final system verification..."

TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILURES=()

# Test 1: FreeIPA
log "Testing FreeIPA..."
if systemctl is-active --quiet ipa; then
    log "  ✓ FreeIPA service is running"
    ((TESTS_PASSED++))

    # Test authentication
    if echo "${ADMIN_PASSWORD}" | kinit admin 2>/dev/null; then
        log "  ✓ FreeIPA authentication works"
        kdestroy
        ((TESTS_PASSED++))
    else
        log "  ✗ FreeIPA authentication failed"
        FAILURES+=("FreeIPA authentication")
        ((TESTS_FAILED++))
    fi
else
    log "  ✗ FreeIPA service is not running"
    FAILURES+=("FreeIPA service")
    ((TESTS_FAILED++))
fi

# Test 2: DNS
log "Testing DNS resolution..."
if host "${DC1_HOSTNAME}" ${DC1_IP} &>/dev/null; then
    log "  ✓ DNS resolution works"
    ((TESTS_PASSED++))
else
    log "  ✗ DNS resolution failed"
    FAILURES+=("DNS resolution")
    ((TESTS_FAILED++))
fi

# Test 3: Firewall
log "Testing firewall..."
if systemctl is-active --quiet firewalld; then
    log "  ✓ Firewall is active"
    ((TESTS_PASSED++))
else
    log "  ✗ Firewall is not active"
    FAILURES+=("Firewall")
    ((TESTS_FAILED++))
fi

# Test 4: SELinux
log "Testing SELinux..."
if getenforce | grep -q "Enforcing"; then
    log "  ✓ SELinux is enforcing"
    ((TESTS_PASSED++))
else
    log "  ✗ SELinux is not enforcing"
    FAILURES+=("SELinux")
    ((TESTS_FAILED++))
fi

# Test 5: FIPS Mode
log "Testing FIPS mode..."
if fips-mode-setup --check | grep -q "FIPS mode is enabled"; then
    log "  ✓ FIPS mode is enabled"
    ((TESTS_PASSED++))
else
    log "  ✗ FIPS mode is not enabled"
    FAILURES+=("FIPS mode")
    ((TESTS_FAILED++))
fi

# Test 6: SSL Certificates
log "Testing SSL certificates..."
if [[ -f "${SSL_CERT_PATH}" ]] && [[ -f "${SSL_KEY_PATH}" ]]; then
    log "  ✓ SSL certificates exist"
    ((TESTS_PASSED++))

    # Verify certificate is valid
    if openssl x509 -in "${SSL_CERT_PATH}" -noout -checkend 0; then
        log "  ✓ SSL certificate is valid"
        ((TESTS_PASSED++))
    else
        log "  ✗ SSL certificate is expired or invalid"
        FAILURES+=("SSL certificate validity")
        ((TESTS_FAILED++))
    fi
else
    log "  ✗ SSL certificates not found"
    FAILURES+=("SSL certificates")
    ((TESTS_FAILED++))
fi

# Test 7: Disk Space
log "Testing disk space..."
ROOT_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ ${ROOT_SPACE} -gt 10 ]]; then
    log "  ✓ Sufficient disk space: ${ROOT_SPACE}GB"
    ((TESTS_PASSED++))
else
    log "  ⚠ Low disk space: ${ROOT_SPACE}GB"
    FAILURES+=("Low disk space")
    ((TESTS_FAILED++))
fi

# Test 8: Memory
log "Testing memory..."
FREE_MEM=$(free -g | awk '/^Mem:/ {print $7}')
if [[ ${FREE_MEM} -gt 5 ]]; then
    log "  ✓ Sufficient free memory: ${FREE_MEM}GB"
    ((TESTS_PASSED++))
else
    log "  ⚠ Low free memory: ${FREE_MEM}GB"
fi

# Test 9: Services
log "Testing installed services..."
EXPECTED_SERVICES=("ipa" "firewalld")
for service in "${EXPECTED_SERVICES[@]}"; do
    if systemctl is-enabled --quiet "${service}" 2>/dev/null; then
        log "  ✓ ${service} is enabled"
        ((TESTS_PASSED++))
    else
        log "  ✗ ${service} is not enabled"
        FAILURES+=("${service} not enabled")
        ((TESTS_FAILED++))
    fi
done

# Generate verification report
REPORT_FILE="${SCRIPT_DIR}/VERIFICATION_REPORT_${INSTALL_DATE}.txt"
cat > "${REPORT_FILE}" <<EOF
========================================
CyberHygiene Installation Verification Report
========================================
Generated: $(date)
Domain: ${DOMAIN}
Hostname: $(hostname -f)

========================================
TEST RESULTS
========================================
Total Tests: $((TESTS_PASSED + TESTS_FAILED))
Passed: ${TESTS_PASSED}
Failed: ${TESTS_FAILED}

========================================
SYSTEM INFORMATION
========================================
OS: $(cat /etc/redhat-release)
Kernel: $(uname -r)
FIPS: $(fips-mode-setup --check)
SELinux: $(getenforce)
Hostname: $(hostname -f)
IP Address: $(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)

Memory: $(free -h | awk '/^Mem:/ {print $2}') total, $(free -h | awk '/^Mem:/ {print $7}') available
Disk: $(df -h / | awk 'NR==2 {print $2}') total, $(df -h / | awk 'NR==2 {print $4}') available

========================================
SERVICE STATUS
========================================
$(systemctl list-units --type=service --state=running | grep -E "ipa|samba|firewalld" || echo "No matching services")

========================================
FAILURES (if any)
========================================
EOF

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    for failure in "${FAILURES[@]}"; do
        echo "- ${failure}" >> "${REPORT_FILE}"
    done
else
    echo "None - All tests passed!" >> "${REPORT_FILE}"
fi

cat >> "${REPORT_FILE}" <<EOF

========================================
NEXT STEPS
========================================
1. Review this verification report
2. Access FreeIPA web UI: https://${DC1_HOSTNAME}
3. Test user authentication
4. Configure additional services as needed
5. Complete customer handoff documentation

========================================
CREDENTIALS
========================================
See file: ${SCRIPT_DIR}/CREDENTIALS_${INSTALL_DATE}.txt

========================================
EOF

chmod 600 "${REPORT_FILE}"

# Summary
echo ""
log "=========================================="
log "Final Verification Summary"
log "=========================================="
log "Tests Passed: ${TESTS_PASSED}"
log "Tests Failed: ${TESTS_FAILED}"
log ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    log "✓✓✓ ALL TESTS PASSED ✓✓✓"
    log ""
    log "CyberHygiene installation is complete and verified!"
    log "System is ready for production use."
else
    log "⚠ SOME TESTS FAILED"
    log ""
    log "Failed tests:"
    for failure in "${FAILURES[@]}"; do
        log "  - ${failure}"
    done
    log ""
    log "Review and resolve failures before deploying to production"
fi

log ""
log "Full report: ${REPORT_FILE}"
log ""

# Exit with appropriate code
if [[ ${TESTS_FAILED} -eq 0 ]]; then
    exit 0
else
    exit 1
fi
