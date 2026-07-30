# 🔑 IPtables Installation And Configuration

Block Apache port **6300** on all app servers, allowing traffic only from the **Load Balancer** using **iptables**.

---

## 📦 Stack / Tech Used

| Technology         | Version | Purpose                          |
|--------------------|---------|----------------------------------|
| iptables           | `1.8+`  | Linux firewall rule management   |
| iptables-services  | `1.8+`  | Persistence across reboots       |
| sshpass            | `1.06+` | Non-interactive SSH auth         |
| Bash               | `4.x`   | Automation scripting             |

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

| Server          | Hostname  | User     | Password     |
|-----------------|-----------|----------|--------------|
| App Server 1    | `stapp01` | `tony`   | `Ir0nM@n`    |
| App Server 2    | `stapp02` | `steve`  | `Am3ric@`    |
| App Server 3    | `stapp03` | `banner` | `BigGr33n`   |
| Load Balancer   | `stlb01`  | `loki`   | `Mischi3f`   |
| Jump Host       | `jump_host` | `thor` | `mjolnir123` |

> **Note:** IPs are dynamic per lab session. The script resolves them from `/etc/hosts` automatically.

---

## ✅ Prerequisites

Before you begin, make sure you have the following:

- Access to the **Jump Host** (`thor@jump_host`)
- SSH connectivity to all **3 app servers** from the jump host
- `sshpass` installed on the jump host (script auto-installs if missing)

---

## 🚀 Quick Start

### 1. SSH into the Jump Host

```bash
ssh thor@jump_host
```

### 2. Upload or Create the Script

```bash
vi iptables_setup.sh
# Paste the script contents, save and exit
```

### 3. Make it Executable

```bash
chmod +x iptables_setup.sh
```

### 4. Run the Script

```bash
bash iptables_setup.sh
```

---

## 📋 What the Script Does

| Step | Action                                              | Command Used                                      |
|------|-----------------------------------------------------|---------------------------------------------------|
| 1    | Resolves LBR IP from `/etc/hosts`                   | `grep stlb01 /etc/hosts`                          |
| 2    | Installs `iptables` & `iptables-services`           | `yum install -y iptables iptables-services`        |
| 3    | Starts & enables iptables service                   | `systemctl start/enable iptables`                  |
| 4    | **ACCEPT** port 6300 from LBR only (insert at top)  | `iptables -I INPUT -p tcp --dport 6300 -s <LBR_IP> -j ACCEPT` |
| 5    | **DROP** port 6300 from everyone else                | `iptables -I INPUT 2 -p tcp --dport 6300 -j DROP`  |
| 6    | Saves rules for reboot persistence                  | `service iptables save`                            |

---

## 🔧 Configuration

| Variable      | Default   | Description                         |
|---------------|-----------|-------------------------------------|
| `APACHE_PORT` | `6300`    | Port to protect on app servers      |
| `LBR_HOST`    | `stlb01`  | Load Balancer hostname to whitelist |
| `SERVERS`     | -         | App server credentials (hardcoded)  |

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

---

## 🧪 Verification

After running the script, verify on each app server:

### 1. Check Rule Order

```bash
sudo iptables -L INPUT -n -v --line-numbers
```

**Expected output:**

```
num   target     prot opt source               destination
1     ACCEPT     tcp  --  <LBR_IP>             0.0.0.0/0     tcp dpt:6300
2     DROP       tcp  --  0.0.0.0/0            0.0.0.0/0     tcp dpt:6300
3     ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0     state RELATED,ESTABLISHED
...
```

### 2. Check Rules Persist After Reboot

```bash
cat /etc/sysconfig/iptables
```

### 3. Test Connectivity

```bash
# From LBR (should SUCCEED)
curl stapp01:6300

# From any other host (should FAIL / timeout)
curl stapp01:6300
```

---

## 📝 Changelog

| Version | Date       | Changes                              |
|---------|------------|--------------------------------------|
| `1.1.0` | 2026-07-30 | Fixed: `-I` instead of `-A`, removed flush, added error handling |
| `1.0.0` | 2026-07-30 | Initial script with iptables setup   |

---

## 👤 Author

**Rezaul**
- Platform: [KodeKloud](https://kodekloud.com/)
- Project: Nautilus — Stratos DC
