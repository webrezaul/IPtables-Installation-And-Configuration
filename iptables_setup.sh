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

set -e  # Exit on any error

# -------------------- Configuration --------------------

# App server details
declare -A SERVERS
SERVERS=(
    ["stapp01"]="tony Ir0nM@n"
    ["stapp02"]="steve Am3ric@"
    ["stapp03"]="banner BigGr33n"
)

# Load Balancer hostname (used to resolve IP dynamically)
LBR_HOST="stlb01"

# Apache port to protect
APACHE_PORT=6300

# -------------------- Functions --------------------

# Check if a command exists
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

run_remote() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local cmd="$4"

    # Use 'echo pass | sudo -S' because non-interactive SSH has no terminal for sudo prompt
    sshpass -p "${pass}" ssh -o StrictHostKeyChecking=no "${user}@${host}" \
        "echo '${pass}' | sudo -S bash -c '${cmd}'"
    local status=$?
    if [ ${status} -ne 0 ]; then
        echo "[ERROR] Command failed on ${host} (exit code: ${status})"
        echo "        Command: ${cmd}"
        return ${status}
    fi
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

# Resolve LBR IP from /etc/hosts on jump host
LBR_IP=$(grep -i "${LBR_HOST}" /etc/hosts | awk '{print $1}' | head -1)

if [ -z "${LBR_IP}" ]; then
    echo "[WARN] Could not resolve LBR IP for '${LBR_HOST}' from /etc/hosts"
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

# Loop through each app server
for host in stapp01 stapp02 stapp03; do
    read -r user pass <<< "${SERVERS[$host]}"

    echo "---------------------------------------------"
    echo "[*] Configuring ${host} (user: ${user})"
    echo "---------------------------------------------"

    # Step 1: Install iptables and iptables-services
    echo "[1/4] Installing iptables and iptables-services..."
    run_remote "${host}" "${user}" "${pass}" \
        "yum install -y iptables iptables-services"
    echo "      Done."

    # Step 2: Start and enable iptables service
    echo "[2/4] Starting and enabling iptables service..."
    run_remote "${host}" "${user}" "${pass}" \
        "systemctl start iptables && systemctl enable iptables"
    echo "      Done."

    # Step 3: Add iptables rules using INSERT (-I) not APPEND (-A)
    #   -I INPUT 1 → ACCEPT port 6300 from LBR (inserted at position 1, top)
    #   -I INPUT 2 → DROP   port 6300 from all  (inserted at position 2, after ACCEPT)
    #
    #   WHY -I instead of -A?
    #   CentOS default iptables has a REJECT-all rule at the bottom.
    #   Using -A (append) would place our rules AFTER that REJECT,
    #   meaning they'd NEVER be reached. -I inserts at the top.
    echo "[3/4] Adding iptables rules..."
    run_remote "${host}" "${user}" "${pass}" \
        "iptables -I INPUT -p tcp --dport ${APACHE_PORT} -s ${LBR_IP} -j ACCEPT && \
         iptables -I INPUT 2 -p tcp --dport ${APACHE_PORT} -j DROP"
    echo "      Done."

    # Step 4: Save rules to persist across reboots
    echo "[4/4] Saving iptables rules for persistence..."
    run_remote "${host}" "${user}" "${pass}" \
        "iptables-save > /etc/sysconfig/iptables"
    echo "      Done."

    # Verify: Show all INPUT rules to confirm correct ordering
    echo ""
    echo "[✓] Verifying rules on ${host}:"
    run_remote "${host}" "${user}" "${pass}" \
        "iptables -L INPUT -n -v --line-numbers"
    echo ""

done

echo "============================================="
echo " ✅ All app servers configured successfully!"
echo "============================================="
echo ""
echo "Summary:"
echo "  - iptables installed on: stapp01, stapp02, stapp03"
echo "  - Port ${APACHE_PORT} ACCEPT from: ${LBR_IP} (${LBR_HOST})"
echo "  - Port ${APACHE_PORT} DROP from: all others"
echo "  - Rules saved and persistent across reboots"
echo ""
echo "Rule order (top → bottom):"
echo "  1. ACCEPT tcp dpt:${APACHE_PORT} from ${LBR_IP}"
echo "  2. DROP   tcp dpt:${APACHE_PORT} from anywhere"
echo "  3. (default CentOS rules follow...)"
