# 🔑 IPtables Installation And Configuration

Block Apache port **6300** on all app servers, allowing traffic only from the **Load Balancer** using **iptables**.

![KodeKloud](https://img.shields.io/badge/KodeKloud-Completed-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Nautilus-blue)
![Status](https://img.shields.io/badge/Lab-Passed%20✅-success)

---

## 📦 Stack / Tech Used

| Technology         | Version  | Purpose                          |
|--------------------|----------|----------------------------------|
| iptables           | `1.8+`   | Linux firewall rule management   |
| iptables-services  | `1.8+`   | Persistence across reboots       |
| sshpass            | `1.06+`  | Non-interactive SSH auth         |
| Bash               | `4.x`    | Automation scripting             |
| nslookup           | -        | Dynamic LBR IP resolution        |

---

## 📁 Project Structure

```
.
├── iptables_setup.sh    # Main automation script (run from jump host)
├── project.txt          # Original task requirements
└── README.md            # This file
```

---

## 🌐 Infrastructure Details

### Servers

| Server        | Hostname    | User     | Password     |
|---------------|-------------|----------|--------------|
| App Server 1  | `stapp01`   | `tony`   | `Ir0nM@n`    |
| App Server 2  | `stapp02`   | `steve`  | `Am3ric@`    |
| App Server 3  | `stapp03`   | `banner` | `BigGr33n`   |
| Load Balancer | `stlb01`    | `loki`   | `Mischi3f`   |
| Jump Host     | `jump_host` | `thor`   | `mjolnir123` |

> **Note:** IPs are dynamic per lab session. The script auto-resolves the LBR IP via `/etc/hosts` → `nslookup` → manual input fallback.

---

## ✅ Prerequisites

Before you begin, make sure you have the following:

- Access to the **Jump Host** (`thor@jump_host`)
- SSH connectivity to all **3 app servers** from the jump host
- `sshpass` on the jump host — script auto-installs via `apt`, `dnf`, or `yum`

> ⚠️ **Run from jump host only** — the aws-client cannot reach Nautilus internal DNS.

---

## 🚀 Quick Start

### 1. SSH into the Jump Host

```bash
ssh thor@jump_host
```

### 2. Clone the Repository

```bash
git clone https://github.com/webrezaul/IPtables-Installation-And-Configuration.git
cd IPtables-Installation-And-Configuration
```

### 3. Make it Executable & Run

```bash
chmod +x iptables_setup.sh
./iptables_setup.sh
```

### 4. Update & Re-run (if script was updated)

```bash
git checkout -- . && git pull origin main && chmod +x ./iptables_setup.sh && ./iptables_setup.sh
```

---

## 📋 What the Script Does

| Step | Action                                                  | Command Used                                                   |
|------|---------------------------------------------------------|----------------------------------------------------------------|
| 0    | Auto-resolves LBR IP (`/etc/hosts` → `nslookup`)       | `grep stlb01 /etc/hosts` / `nslookup stlb01`                  |
| 1    | Installs `iptables` & `iptables-services`               | `yum install -y iptables iptables-services`                    |
| 2    | Starts & enables iptables service                       | `systemctl start/enable iptables`                              |
| 3    | **Cleans up** existing port 6300 rules (prevents dupes) | `iptables -D INPUT ... (while loop)`                           |
| 4    | **ACCEPT** port 6300 from LBR only (insert at top)      | `iptables -I INPUT -p tcp --dport 6300 -s <LBR_IP> -j ACCEPT` |
| 5    | **DROP** port 6300 from everyone else                   | `iptables -I INPUT 2 -p tcp --dport 6300 -j DROP`              |
| 6    | Saves rules for reboot persistence                      | `iptables-save > /etc/sysconfig/iptables`                      |
| 7    | Restarts iptables to verify persistence                 | `systemctl restart iptables`                                   |
| 8    | Tests LBR → App connectivity from `stlb01`              | `curl stapp0X:6300` (expects HTTP 200/403)                     |

> **Note:** The script is **idempotent** — safe to run multiple times without creating duplicate rules.

---

## 🔧 Configuration

| Variable      | Default  | Description                         |
|---------------|----------|-------------------------------------|
| `APACHE_PORT` | `6300`   | Port to protect on app servers      |
| `LBR_HOST`    | `stlb01` | Load Balancer hostname to whitelist |
| `SERVERS`     | -        | App server credentials (hardcoded)  |

---

## ⚡ Key Technical Decisions

### Why `-I` (Insert) instead of `-A` (Append)?

```bash
# ❌ WRONG — Appended AFTER default REJECT rule, never reached
sudo iptables -A INPUT -p tcp --dport 6300 -j DROP

# ✅ CORRECT — Inserted at top, evaluated BEFORE default REJECT
sudo iptables -I INPUT -p tcp --dport 6300 -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 6300 -j DROP
```

CentOS default iptables has a **REJECT-all** rule at the bottom. Using `-A` places rules **after** it — they would **never be reached**.

### Why no `iptables -F` (Flush)?

Flushing removes **all** rules including SSH access. This can **lock you out** of the server permanently.

### Why clean up before adding rules?

Running the script multiple times would **duplicate** ACCEPT/DROP rules. The cleanup step (Step 3) deletes any existing port 6300 rules first using a `while` loop with `iptables -D`, ensuring exactly **one** ACCEPT and **one** DROP rule exist.

### Why `iptables-save` instead of `service iptables save`?

RHEL 9 / CentOS Stream 9 does **not** have the `service` command. Using `iptables-save > /etc/sysconfig/iptables` writes the rules directly to the persistence file.

### Why no `-t` (pseudo-terminal) in SSH?

Using `-t -t` with `sshpass` corrupts file redirects (e.g. `>`) because the terminal adds extra characters. Removed to ensure `iptables-save > /etc/sysconfig/iptables` works correctly.

---

## 🧪 Verification

The script self-verifies automatically. To manually check on each app server:

### 1. Check Rule Order

```bash
sudo iptables -L INPUT -n -v --line-numbers
```

**Expected output:**

```
num   target  prot  source           destination
1     ACCEPT  tcp   <LBR_IP>         0.0.0.0/0    tcp dpt:6300
2     DROP    tcp   0.0.0.0/0        0.0.0.0/0    tcp dpt:6300
3     ACCEPT  all   0.0.0.0/0        0.0.0.0/0    state RELATED,ESTABLISHED
...
7     REJECT  all   0.0.0.0/0        0.0.0.0/0    reject-with icmp-host-prohibited
```

### 2. Check Rules Persist After Reboot

```bash
cat /etc/sysconfig/iptables | grep 6300
```

**Expected output:**

```
-A INPUT -s <LBR_IP>/32 -p tcp -m tcp --dport 6300 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 6300 -j DROP
```

### 3. Test LBR Connectivity

```bash
# From stlb01 (should SUCCEED — HTTP 403 or 200)
curl stapp01:6300
curl stapp02:6300
curl stapp03:6300

# From jump host (should FAIL — connection drops)
curl --connect-timeout 5 stapp01:6300
```

---

## 📝 Changelog

| Version | Date       | Changes                                                          |
|---------|------------|------------------------------------------------------------------|
| `1.3.0` | 2026-07-30 | Added LBR connectivity test, restart verification, apt/dnf/yum support |
| `1.2.0` | 2026-07-30 | Added duplicate rule cleanup, `iptables-save` for RHEL9          |
| `1.1.0` | 2026-07-30 | Fixed: `-I` instead of `-A`, removed flush, `sudo -S` for SSH   |
| `1.0.0` | 2026-07-30 | Initial script with iptables setup                               |

---

## 👤 Author

**Rezaul**
- Platform: [KodeKloud](https://kodekloud.com/)
- Project: Nautilus — Stratos DC
