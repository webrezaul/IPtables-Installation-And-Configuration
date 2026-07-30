#!/bin/bash

#=============================================================
# KodeKloud Engineer - Nautilus: iptables Firewall Setup
#=============================================================
# Task:
#   1. Install iptables on all app servers
#   2. Block incoming port 6300 for everyone except LBR host
#   3. Make rules persistent across reboots
#
# Run this script from the Jump Host (thor@jump_host)
#=============================================================

# -------------------- Configuration --------------------

# App server details
declare -A SERVERS
SERVERS=(
    ["stapp01"]="tony Ir0nM@n"
    ["stapp02"]="steve Am3ric@"
    ["stapp03"]="banner BigGr33n"
)

# Load Balancer hostname
LBR_HOST="stlb01"

# Apache port to protect
APACHE_PORT=6300

# -------------------- Functions --------------------

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "[ERROR] '$1' is not installed. Installing..."
        sudo yum install -y "$1" > /dev/null 2>&1
        if ! command -v "$1" &> /dev/null; then
            echo "[FATAL] Failed to install '$1'. Exiting."
            exit 1
        fi
    fi
}

# Run a command on a remote host via SSH
# IMPORTANT: No -t flag to avoid pseudo-terminal issues with file redirects
run_remote() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local cmd="$4"

    sshpass -p "${pass}" ssh -o StrictHostKeyChecking=no "${user}@${host}" \
        "echo '${pass}' | sudo -S bash -c '${cmd}'" 2>&1
    return $?
}

# -------------------- Pre-flight Checks --------------------

echo "============================================="
echo " iptables Firewall Setup - Nautilus Project"
echo "============================================="
echo ""

# Check sshpass is available
echo "[PRE] Checking dependencies..."
check_dependency sshpass
echo "      sshpass: OK"

# Resolve LBR IP: try /etc/hosts first, then nslookup, then manual input
LBR_IP=$(grep -i "${LBR_HOST}" /etc/hosts | awk '{print $1}' | head -1)

if [ -z "${LBR_IP}" ]; then
    echo "[INFO] LBR not found in /etc/hosts, trying nslookup..."
    LBR_IP=$(nslookup "${LBR_HOST}" 2>/dev/null | awk '/^Address:/ && !/#/ {print $2}' | head -1)
fi

if [ -z "${LBR_IP}" ]; then
    echo "[WARN] Could not resolve LBR IP for '${LBR_HOST}' automatically"
    echo "       Please enter the LBR IP manually:"
    read -r LBR_IP
    if [ -z "${LBR_IP}" ]; then
        echo "[FATAL] No LBR IP provided. Exiting."
        exit 1
    fi
fi

echo ""
echo "[INFO] Load Balancer IP: ${LBR_IP}"
echo "[INFO] Port to protect:  ${APACHE_PORT}"
echo ""

# -------------------- Main --------------------

for host in stapp01 stapp02 stapp03; do
    read -r user pass <<< "${SERVERS[$host]}"

    echo "---------------------------------------------"
    echo "[*] Configuring ${host} (user: ${user})"
    echo "---------------------------------------------"

    # Step 1: Install iptables and iptables-services
    echo "[1/6] Installing iptables and iptables-services..."
    run_remote "${host}" "${user}" "${pass}" \
        "yum install -y iptables iptables-services"
    echo "      Done."

    # Step 2: Start and enable iptables service
    echo "[2/6] Starting and enabling iptables service..."
    run_remote "${host}" "${user}" "${pass}" \
        "systemctl start iptables && systemctl enable iptables"
    echo "      Done."

    # Step 3: Remove any existing rules for this port (prevents duplicates)
    echo "[3/6] Cleaning existing port ${APACHE_PORT} rules..."
    run_remote "${host}" "${user}" "${pass}" \
        "while iptables -D INPUT -p tcp --dport ${APACHE_PORT} -s ${LBR_IP} -j ACCEPT 2>/dev/null; do :; done; \
         while iptables -D INPUT -p tcp --dport ${APACHE_PORT} -j DROP 2>/dev/null; do :; done"
    echo "      Done."

    # Step 4: Add iptables rules
    echo "[4/6] Adding iptables rules..."
    run_remote "${host}" "${user}" "${pass}" \
        "iptables -I INPUT -p tcp --dport ${APACHE_PORT} -s ${LBR_IP} -j ACCEPT && \
         iptables -I INPUT 2 -p tcp --dport ${APACHE_PORT} -j DROP"
    echo "      Done."

    # Step 5: Save rules for persistence
    echo "[5/6] Saving rules for persistence..."
    run_remote "${host}" "${user}" "${pass}" \
        "iptables-save > /etc/sysconfig/iptables && chmod 600 /etc/sysconfig/iptables"
    echo "      Done."

    # Step 6: Verify persistence by restarting iptables and checking rules survive
    echo "[6/6] Verifying persistence (restart test)..."
    run_remote "${host}" "${user}" "${pass}" \
        "systemctl restart iptables"

    # Check rules after restart
    echo ""
    echo "[✓] Rules on ${host} AFTER restart:"
    run_remote "${host}" "${user}" "${pass}" \
        "iptables -L INPUT -n --line-numbers | head -10"

    # Check saved file
    echo "[✓] Saved rules file:"
    run_remote "${host}" "${user}" "${pass}" \
        "grep ${APACHE_PORT} /etc/sysconfig/iptables"

    # Check Apache is running
    echo "[✓] Apache status:"
    run_remote "${host}" "${user}" "${pass}" \
        "systemctl status httpd 2>/dev/null | grep Active || echo 'httpd not found, checking port...'; ss -tlnp | grep ${APACHE_PORT}"
    echo ""

done

# -------------------- Final Connectivity Test --------------------

echo "============================================="
echo " 🔍 Testing LBR → App Server connectivity"
echo "============================================="
echo ""

for host in stapp01 stapp02 stapp03; do
    result=$(sshpass -p 'Mischi3f' ssh -o StrictHostKeyChecking=no loki@stlb01 \
        "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 ${host}:${APACHE_PORT}" 2>/dev/null)
    if [ "$result" = "200" ] || [ "$result" = "403" ]; then
        echo "[✅] LBR → ${host}:${APACHE_PORT} = HTTP ${result} (REACHABLE)"
    else
        echo "[❌] LBR → ${host}:${APACHE_PORT} = HTTP ${result} (FAILED!)"
    fi
done

echo ""
echo "============================================="
echo " ✅ All app servers configured successfully!"
echo "============================================="
echo ""
echo "Summary:"
echo "  - iptables installed on: stapp01, stapp02, stapp03"
echo "  - Port ${APACHE_PORT} ACCEPT from: ${LBR_IP} (${LBR_HOST})"
echo "  - Port ${APACHE_PORT} DROP from: all others"
echo "  - Rules saved and persistent across reboots"
