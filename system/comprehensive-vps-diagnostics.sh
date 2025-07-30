#!/usr/bin/env bash
###############################################################################
# Comprehensive VPS Diagnostics Script
# Enhanced version with robust error handling and adaptive features
# Combines elements from multiple diagnostic sources
# Provides complete system analysis including Docker, CasaOS, network, security
# Usage: sudo ./comprehensive-vps-diagnostics.sh
# 
# Features:
# - System & OS overview
# - Hardware resources analysis
# - Docker & CasaOS status
# - Network configuration & connectivity
# - Firewall & security audit
# - Performance monitoring
# - Storage analysis
# - Container health checks
# - Recent logs & error analysis
# - Color output support (if lolcat/grc available)
# - Robust error handling
# - Adaptive command execution
# - Automatic log file creation
###############################################################################

set -Euo pipefail
trap 'echo "[WARN] Error at line $LINENO, continuing..." >&2' ERR
IFS=$'\n\t'

# Function definitions (must be at the top)
function setup_logging() {
  local default_dir="$1"
  local default_file="$2"
  
  # Create log directory if it doesn't exist
  if [[ ! -d "$default_dir" ]]; then
    echo "Creating log directory: $default_dir"
    mkdir -p "$default_dir" 2>/dev/null || {
      echo "Warning: Could not create $default_dir, using current directory"
      default_dir="."
      default_file="./vps-diagnostics-$(date +%Y%m%d-%H%M%S).log"
    }
  fi
  
  echo "$default_file"
}

function log_header() {
  local log_file="$1"
  echo "=========================================="
  echo "VPS DIAGNOSTICS REPORT"
  echo "Generated on: $(date)"
  echo "Hostname: $(hostname)"
  echo "User: $(whoami)"
  echo "Log file: $log_file"
  echo "=========================================="
  echo ""
}

function section() {
  if [[ $COLOR -eq 1 ]]; then
    echo -e "\n\033[1;36m=== $1 ===\033[0m" | lolcat
  else
    echo -e "\n=== $1 ==="
  fi
}

function safe_run() {
  local cmd="$*"
  if eval "$cmd" 2>/dev/null; then
    return 0
  else
    echo "[Warn] Command failed: $cmd" >&2
    return 1
  fi
}

function docker_safe() {
  local cmd="$*"
  if command -v docker &>/dev/null && sudo docker info &>/dev/null; then
    if eval "$cmd" 2>/dev/null; then
      return 0
    else
      echo "[Warn] Docker command failed: $cmd" >&2
      return 1
    fi
  else
    echo "[Info] Docker not available or not running" >&2
    return 1
  fi
}

function print_info() {
  local label="$1"
  local value="$2"
  printf "%-20s %s\n" "$label:" "$value"
}

function check_command() {
  command -v "$1" &>/dev/null
}

# ---- 0. Initialization ----
# Setup log file
DEFAULT_LOG_DIR="/DATA/Downloads"
DEFAULT_LOG_FILE="$DEFAULT_LOG_DIR/vps-diagnostics-$(date +%Y%m%d-%H%M%S).log"

# Create log directory if it doesn't exist
DEFAULT_LOG_FILE=$(setup_logging "$DEFAULT_LOG_DIR" "$DEFAULT_LOG_FILE")

# Ask user for log file location
echo "=== VPS Diagnostics Log File Setup ==="
echo "Default log file: $DEFAULT_LOG_FILE"
read -p "Do you want to change the log file location? (y/N): " -r change_location

if [[ $change_location =~ ^[Yy]$ ]]; then
  read -p "Enter new log file path (or press Enter for default): " -r custom_log_file
  if [[ -n "$custom_log_file" ]]; then
    LOG_FILE="$custom_log_file"
    # Create directory if it doesn't exist
    LOG_DIR=$(dirname "$LOG_FILE")
    if [[ ! -d "$LOG_DIR" ]]; then
      mkdir -p "$LOG_DIR" 2>/dev/null || {
        echo "Error: Could not create directory $LOG_DIR"
        LOG_FILE="$DEFAULT_LOG_FILE"
      }
    fi
  else
    LOG_FILE="$DEFAULT_LOG_FILE"
  fi
else
  LOG_FILE="$DEFAULT_LOG_FILE"
fi

echo "Log file will be saved to: $LOG_FILE"
echo "Starting diagnostics... (all output will be logged)"

# Start logging
exec > >(tee "$LOG_FILE") 2>&1

# Add log header
log_header "$LOG_FILE"

COLOR=0
if command -v lolcat &>/dev/null && command -v grc &>/dev/null; then
  COLOR=1
  echo "Color support enabled (lolcat/grc found)" | lolcat
fi



# ---- 1. System & OS Overview ----
section "System & OS Overview"
print_info "Architecture" "$(uname -m)"
print_info "Kernel & OS" "$(uname -sr); $(lsb_release -ds 2>/dev/null || echo N/A)"
print_info "Hostname" "$(hostname)"
print_info "FQDN" "$(hostname -f 2>/dev/null || echo N/A)"
print_info "Domain" "$(dnsdomainname 2>/dev/null || echo N/A)"
print_info "Uptime" "$(uptime -p)"
print_info "Boot Time" "$(uptime -s 2>/dev/null || echo N/A)"
print_info "Timezone" "$(timedatectl show --property=Timezone --value 2>/dev/null || echo N/A)"
print_info "Locale" "$(localectl status 2>/dev/null | grep 'System Locale' | cut -d= -f2 || echo N/A)"
print_info "OS Release" "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo N/A)"

# ---- 2. Hardware Resources ----
section "Hardware Resources"
print_info "CPU Cores" "$(nproc)"
print_info "CPU Model" "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' | head -c60)..."
print_info "CPU Architecture" "$(lscpu 2>/dev/null | grep Architecture | awk '{print $2}' || echo N/A)"
print_info "CPU MHz" "$(lscpu 2>/dev/null | grep 'CPU MHz' | awk '{print $3}' || echo N/A)"
print_info "CPU Cores/Threads" "$(lscpu 2>/dev/null | grep -E '^CPU\(s\)|^Thread\(s\) per core' | awk '{print $2}' | tr '\n' '/' | sed 's/\/$//' || echo N/A)"
print_info "Total RAM" "$(free -h --si | awk '/^Mem:/ {print $2}')"
print_info "Used RAM" "$(free -h --si | awk '/^Mem:/ {print $3 " (" $5 " available)"}')"
print_info "Swap Total" "$(free -h --si | awk '/^Swap:/ {print $2}')"
print_info "Swap Used" "$(free -h --si | awk '/^Swap:/ {print $3}')"
print_info "Load Average" "$(uptime | sed 's/.*load average: //')"
print_info "CPU Usage" "$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo N/A)%"

# ---- 3. Disk & Storage Information ----
section "Disk & Storage Information"
echo "=== DISK USAGE ==="
if command -v column &>/dev/null; then
  df -h --output=source,size,used,avail,pcent,target 2>/dev/null | column -t
else
  df -h --output=source,size,used,avail,pcent,target 2>/dev/null
fi

echo -e "\n=== DISK USAGE BY DIRECTORY (/) ==="
du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10 || echo "Unable to get directory usage"

echo -e "\n=== DISK USAGE (/data) ==="
du -sh /data 2>/dev/null || echo "/data directory not found"

echo -e "\n=== DISK USAGE (/DATA) ==="
du -sh /DATA 2>/dev/null || echo "/DATA directory not found"

echo -e "\n=== INODES USAGE ==="
if command -v column &>/dev/null; then
  df -i 2>/dev/null | column -t
else
  df -i 2>/dev/null
fi

echo -e "\n=== LARGE FILES (>100MB) ==="
find / -type f -size +100M 2>/dev/null | head -10 2>/dev/null || echo "No large files found or permission denied"

# ---- 4. Docker & Container Platform ----
section "Docker & Container Platform"
print_info "Docker Version" "$(docker_safe 'sudo docker version --format "{{.Server.Version}}"' || echo 'Not installed')"
print_info "Docker Daemon" "$(sudo systemctl is-active docker 2>/dev/null || echo N/A)"
print_info "Docker Root Dir" "$(docker_safe 'sudo docker info --format "{{.DockerRootDir}}"' || echo N/A)"
print_info "Docker Driver" "$(docker_safe 'sudo docker info --format "{{.Driver}}"' || echo N/A)"
print_info "CasaOS Version" "$(grep '^VERSION=' /etc/os-release | cut -d= -f2 | tr -d '"' || echo N/A)"
print_info "CasaOS Service" "$(sudo systemctl is-active casaos-gateway 2>/dev/null || echo N/A)"

if docker_safe "sudo docker info" &>/dev/null; then
  echo -e "\n=== DOCKER NETWORKS ==="
  docker_safe "sudo docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}'"

  echo -e "\n=== RUNNING CONTAINERS ==="
  docker_safe "sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}\t{{.Size}}'"

  echo -e "\n=== ALL CONTAINERS (INCLUDING STOPPED) ==="
  docker_safe "sudo docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}'"

  echo -e "\n=== EXITED/FAILED CONTAINERS ==="
  docker_safe "sudo docker ps -a --filter status=exited --format 'table {{.Names}}\t{{.Status}}'"

  echo -e "\n=== CONTAINER STATISTICS ==="
  docker_safe "sudo docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'"
fi

# ---- 5. Network Configuration ----
section "Network Configuration"
echo "=== NETWORK INTERFACES ==="
ip -4 addr show | awk '/^[0-9]+:/ {iface=$2} /inet / {print iface, $2}'

echo -e "\n=== NETWORK INTERFACES DETAILED ==="
ip addr show | grep -E '^[0-9]+:|inet '

echo -e "\n=== ROUTING TABLE ==="
if command -v column &>/dev/null; then
  ip route show | column -t
else
  ip route show
fi

echo -e "\n=== DEFAULT GATEWAY ==="
ip route | grep default | awk '{print $3}'

echo -e "\n=== DNS CONFIGURATION ==="
cat /etc/resolv.conf | grep -v '^#'

echo -e "\n=== DNS SERVERS ==="
grep '^nameserver' /etc/resolv.conf | awk '{print $2}'

echo -e "\n=== NETWORK CONNECTIONS ==="
ss -tup | head -20

# ---- 6. Port Analysis ----
section "Port Analysis"
echo "=== CRITICAL SERVICE PORTS ==="
sudo ss -tulnH | awk '$4 ~ /:22$|:80$|:443$|:8000$|:8080$|:9000$|:81$|:6001$|:6002$/ {printf "%-8s %-25s %s\n",$1,$4,($7? $7: "-")}' | sort

echo -e "\n=== ALL LISTENING PORTS ==="
sudo ss -tulnH | awk 'BEGIN{printf "%-8s %-25s %-20s\n","Proto","Address:Port","Process"} {printf "%-8s %-25s %-20s\n",$1,$4,($7? $7: "-")}'

echo -e "\n=== LISTENING PORTS (ALTERNATIVE) ==="
sudo netstat -tuln 2>/dev/null | grep LISTEN || echo "netstat not available"

echo -e "\n=== LISTENING PORTS (SS SIMPLE) ==="
sudo ss -tuln 2>/dev/null | head -20 || echo "ss command failed"

echo -e "\n=== HIGH PORTS LISTENING (>=8000) ==="
sudo ss -tulnH | awk '$4 ~ /:[8-9][0-9][0-9][0-9]$/ {printf "%-8s %-25s %s\n",$1,$4,($7? $7: "-")}' | head -20

echo -e "\n=== OPEN TCP PORTS LISTEN (>=1024) ==="
sudo ss -tnlp4H | awk '$4 ~ /:[0-9]{4,}$/ {printf "%-21s %-6s %s\n",$4,$1,$7}'

# ---- 7. Firewall Status ----
section "Firewall Status"
echo "=== UFW STATUS ==="
sudo ufw status verbose 2>/dev/null || echo "UFW not available"

echo -e "\n=== IPTABLES INPUT CHAIN ==="
sudo iptables -L INPUT -n --line-numbers | head -20

echo -e "\n=== IPTABLES CASAOS RULES ==="
sudo iptables -L CASAOS-OCI-PORTS -n --line-numbers 2>/dev/null | head -20 || echo "CasaOS rules not found"

echo -e "\n=== IPTABLES NAT RULES ==="
sudo iptables -t nat -L -n | head -15

echo -e "\n=== CASAOS-OCI-PORTS CHAIN ==="
sudo iptables -L CASAOS-OCI-PORTS -n --line-numbers | sed 's/ACCEPT/ /' 2>/dev/null || echo "Chain not found"

echo -e "\n=== INPUT CHAIN (ACCEPT rules) ==="
sudo iptables -L INPUT -n --line-numbers | grep ACCEPT

echo -e "\n=== INPUT CHAIN (REJECT rules) ==="
sudo iptables -L INPUT -n --line-numbers | grep REJECT

# ---- 8. Running Services Audit ----
section "Running Services Audit"
echo "=== SYSTEMD ACTIVE SERVICES ==="
systemctl list-units --type=service --state=active --no-pager | head -20

echo -e "\n=== SYSTEMD FAILED SERVICES ==="
systemctl list-units --type=service --state=failed --no-pager

echo -e "\n=== KEY SERVICES STATUS ==="
print_info "SSH" "$(systemctl is-active ssh)"
print_info "Docker" "$(systemctl is-active docker)"
print_info "CasaOS Gateway" "$(systemctl is-active casaos-gateway 2>/dev/null || echo N/A)"
print_info "CasaOS MessageBus" "$(systemctl is-active casaos-message-bus 2>/dev/null || echo N/A)"
print_info "CasaOS UserService" "$(systemctl is-active casaos-user-service 2>/dev/null || echo N/A)"
print_info "Nginx" "$(systemctl is-active nginx 2>/dev/null || echo N/A)"
print_info "Apache2" "$(systemctl is-active apache2 2>/dev/null || echo N/A)"
print_info "Systemd-resolved" "$(systemctl is-active systemd-resolved 2>/dev/null || echo N/A)"

# ---- 9. Process Analysis ----
section "Process Analysis"
echo "=== TOP PROCESSES BY CPU ==="
ps aux --sort=-%cpu | head -10 | awk 'BEGIN{printf "%-10s %-8s %-8s %-50s\n","USER","CPU%","MEM%","COMMAND"} NR>1{printf "%-10s %-8s %-8s %-50s\n",$1,$3,$4,$11}'

echo -e "\n=== TOP PROCESSES BY MEMORY ==="
ps aux --sort=-%mem | head -10 | awk 'BEGIN{printf "%-10s %-8s %-8s %-50s\n","USER","CPU%","MEM%","COMMAND"} NR>1{printf "%-10s %-8s %-8s %-50s\n",$1,$3,$4,$11}'

echo -e "\n=== SYSTEM LOAD ==="
uptime

# ---- 10. Docker Diagnostics ----
section "Docker Diagnostics"
if docker_safe "sudo docker info" &>/dev/null; then
  echo "=== DOCKER SYSTEM INFO ==="
  docker_safe "sudo docker system df"

  echo -e "\n=== DOCKER IMAGES ==="
  docker_safe "sudo docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}'"

  echo -e "\n=== DOCKER VOLUMES ==="
  docker_safe "sudo docker volume ls"

  echo -e "\n=== DOCKER VOLUME SIZES ==="
  docker_safe "sudo docker system df -v" || echo "Docker system df failed"
  
  echo -e "\n=== DOCKER VOLUMES LIST ==="
  docker_safe "sudo docker volume ls" || echo "Docker volumes command failed"

  echo -e "\n=== DOCKER CONTAINER RESOURCE USAGE ==="
  docker_safe "sudo docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}'"

  echo -e "\n=== DOCKER DISK USAGE ==="
  docker_safe "sudo docker system df"
else
  echo "Docker not available or not running"
fi

# ---- 11. Container Health Checks ----
section "Container Health Checks"
if docker_safe "sudo docker info" &>/dev/null; then
  echo "=== CONTAINER HEALTH STATUS ==="
  docker_safe "sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Health}}'"

  echo -e "\n=== CONTAINER LOGS (LAST 5 LINES EACH) ==="
  for container in $(sudo docker ps --format "{{.Names}}" 2>/dev/null); do
    echo "--- $container ---"
    sudo docker logs --tail 5 "$container" 2>/dev/null || echo "No logs available"
  done
else
  echo "Docker not available"
fi

# ---- 12. Security Audit ----
section "Security Audit"
print_info "Current User" "$(whoami)"
print_info "Groups" "$(id -nG | tr ' ' ',')"
print_info "Docker Group" "$(groups | grep -q docker && echo 'Yes' || echo 'No')"
print_info "SSH Status" "$(systemctl is-active ssh)"
print_info "Sudo Access" "$(sudo -n true 2>/dev/null && echo 'Yes' || echo 'No')"

echo -e "\n=== CURRENT USERS ==="
who

echo -e "\n=== RECENT LOGINS ==="
last -n 10

echo -e "\n=== FAILED LOGIN ATTEMPTS ==="
sudo journalctl -u ssh -n 200 --no-pager | grep "Failed password" | tail -10 || echo "No recent failed SSH attempts"

# ---- 13. Troubleshooting & Logs ----
section "Troubleshooting & Logs"
echo "=== RECENT SYSTEM ERRORS ==="
journalctl -p err -n 10 --no-pager

echo -e "\n=== DOCKER ERRORS ==="
journalctl -u docker -p err -n 10 --no-pager

echo -e "\n=== CASAOS GATEWAY ERRORS ==="
journalctl -u casaos-gateway -p err -n 10 --no-pager 2>/dev/null || echo "CasaOS gateway service not found"

echo -e "\n=== KERNEL MESSAGES ==="
dmesg | tail -10

echo -e "\n=== SYSTEM LOGS (LAST 20) ==="
tail -20 /var/log/syslog 2>/dev/null || tail -20 /var/log/messages 2>/dev/null || echo "System logs not accessible"

# ---- 14. Coolify Status ----
section "Coolify Status"
if docker_safe "sudo docker ps --filter name=coolify" &>/dev/null; then
  echo "=== COOLIFY CONTAINERS ==="
  docker_safe "sudo docker ps --filter name=coolify --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

  echo -e "\n=== COOLIFY HEALTH CHECK ==="
  curl -sfI http://localhost:8000/ping >/dev/null 2>&1 && echo '✓ Coolify OK' || echo '✗ Coolify not responding'

  echo -e "\n=== COOLIFY LOGS ==="
  docker_safe "sudo docker logs coolify --tail 10" || echo "Coolify logs not available"
else
  echo "Coolify containers not found"
fi

# ---- 15. CasaOS Apps ----
section "CasaOS Apps"
echo "=== CASAOS APPS ==="
ls -la /DATA/AppData 2>/dev/null | head -20 || echo 'AppData not found'

echo -e "\n=== CASAOS CONFIG ==="
ls -la /etc/casaos/ 2>/dev/null || echo 'CasaOS config not found'

# ---- 16. Nginx Proxy Manager ----
section "Nginx Proxy Manager"
echo "=== NGINX PROXY MANAGER CONTAINERS ==="
docker_safe "sudo docker ps --filter name=nginxproxymanager --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "No NPM containers found"

echo -e "\n=== ALL CONTAINERS WITH 'nginx' IN NAME ==="
docker_safe "sudo docker ps --filter name=nginx --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "No nginx containers found"

echo -e "\n=== ALL CONTAINERS WITH 'proxy' IN NAME ==="
docker_safe "sudo docker ps --filter name=proxy --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "No proxy containers found"

echo -e "\n=== NPM LOGS (if container exists) ==="
if docker_safe "sudo docker ps --filter name=nginxproxymanager --format {{.Names}}" | grep -q nginxproxymanager; then
  docker_safe "sudo docker logs nginxproxymanager --tail 10" || echo "NPM logs not available"
else
  echo "NPM container not running"
fi

# ---- 17. Storage Analysis ----
section "Storage Analysis"
if docker_safe "sudo docker info" &>/dev/null; then
  echo "=== DOCKER SYSTEM DETAILED ==="
  docker_safe "sudo docker system df -v"

  echo -e "\n=== DOCKER VOLUMES (TOP 5 LARGEST) ==="
  sudo find /var/lib/docker/volumes -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | sort -hr | head -5 || echo "Unable to access Docker volumes directory"

  echo -e "\n=== RECLAIMABLE DOCKER SPACE ==="
  docker_safe "sudo docker system df | tail -n +2 | awk '{print \$1\": \"\$4\" reclaimable\"}'"
fi

echo -e "\n=== SYSTEM DIRECTORY USAGE (TOP 5) ==="
sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -6

echo -e "\n=== APP DATA DIRECTORY SIZE ==="
sudo du -sh /DATA/AppData 2>/dev/null || echo "AppData directory not accessible"

# ---- 18. Internet Connectivity ----
section "Internet Connectivity"
echo "=== INTERNET CONNECTIVITY TEST ==="
ping -c 3 8.8.8.8 >/dev/null 2>&1 && echo '✓ Internet OK' || echo '✗ Internet issues'

echo -e "\n=== DNS RESOLUTION TEST ==="
nslookup google.com >/dev/null 2>&1 && echo '✓ DNS OK' || echo '✗ DNS issues'

echo -e "\n=== PUBLIC IP ==="
curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Unable to determine public IP"

echo -e "\n=== ROUTE TO GOOGLE ==="
traceroute -m 5 google.com 2>/dev/null | head -10 || echo "Traceroute not available"

# ---- 19. Recent Issues & Logs ----
section "Recent Issues & Logs"
echo "=== RECENT DOCKER ERRORS (LAST 5 FROM PAST HOUR) ==="
sudo journalctl -u docker -n 100 --no-pager --since "1 hour ago" | grep -iE 'error|fail' | tail -5 || echo "No recent Docker errors found"

echo -e "\n=== CASAOS GATEWAY ERRORS (LAST 5 FROM PAST HOUR) ==="
sudo journalctl -u casaos-gateway -n 100 --no-pager --since "1 hour ago" | grep -iE 'error|fail' | tail -5 || echo "No recent CasaOS errors found"

echo -e "\n=== NGINX PROXY MANAGER STATUS (LAST 5 ENTRIES) ==="
if docker_safe "sudo docker ps --filter name=nginxproxymanager --format {{.Names}}" | grep -q nginxproxymanager; then
  docker_safe "sudo docker logs nginxproxymanager --tail 20 2>/dev/null | grep -E '\[(SSL|Nginx|Global)\]' | tail -5" || echo "NPM logs not available"
else
  echo "NPM container not found"
fi

echo -e "\n=== CASAOS CONTAINERS ==="
docker_safe "sudo docker ps --filter name=casaos --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "No CasaOS containers found"

echo -e "\n=== ALL CONTAINERS WITH 'casa' IN NAME ==="
docker_safe "sudo docker ps --filter name=casa --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "No casa containers found"

echo -e "\n=== ALL CONTAINERS WITH 'gateway' IN NAME ==="
docker_safe "sudo docker ps --filter name=gateway --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "No gateway containers found"

echo -e "\n=== ALL CONTAINERS WITH 'manager' IN NAME ==="
docker_safe "sudo docker ps --filter name=manager --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "No manager containers found"

echo -e "\n=== ALL CONTAINERS WITH 'app' IN NAME ==="
docker_safe "sudo docker ps --filter name=app --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "No app containers found"

echo -e "\n=== SYSTEM ERRORS (LAST 10) ==="
journalctl -p err --since "1 hour ago" --no-pager | tail -10 || echo "No recent system errors"

# ---- 20. Performance Monitoring ----
section "Performance Monitoring"
echo "=== MEMORY USAGE DETAILED ==="
free -h

echo -e "\n=== CPU INFO ==="
lscpu | grep -E "Model name|CPU\(s\)|Thread|Core" | head -5

echo -e "\n=== DISK I/O STATS ==="
iostat -x 1 1 2>/dev/null || echo "iostat not available"

echo -e "\n=== NETWORK INTERFACE STATS ==="
cat /proc/net/dev | grep -v lo | head -5

echo -e "\n=== NETWORK INTERFACE DETAILS ==="
ip link show | grep -E '^[0-9]+:' | head -10

echo -e "\n=== ACTIVE NETWORK CONNECTIONS ==="
ss -tup | head -15

echo -e "\n=== ESTABLISHED CONNECTIONS ==="
ss -tup state established | head -10

# ---- 21. Final System Summary ----
section "Final System Summary"
print_info "Generated on" "$(date)"
print_info "Docker Status" "$(sudo systemctl is-active docker)"
print_info "CasaOS Status" "$(sudo systemctl is-active casaos-gateway)"
print_info "Running Containers" "$(docker_safe 'sudo docker ps -q | wc -l' || echo 'N/A')"
print_info "Total Containers" "$(docker_safe 'sudo docker ps -aq | wc -l' || echo 'N/A')"
print_info "System Health" "$(uptime | grep -q 'load average: [0-4]' && echo 'Healthy' || echo 'Under load')"
print_info "Disk Usage" "$(df -h / | awk 'NR==2 {print $5}')"
print_info "Memory Usage" "$(free | awk '/Mem:/ {printf "%.1f%%", $3/$2*100}')"
print_info "Available Memory" "$(free -h | awk '/Mem:/ {print $7}')"
print_info "System Load" "$(uptime | awk -F'load average:' '{print $2}' | tr -d ' ')"

echo -e "\n=== ADDITIONAL SYSTEM INFO ==="
print_info "Kernel Version" "$(uname -r)"
print_info "System Architecture" "$(arch)"
print_info "Available Disk Space" "$(df -h / | awk 'NR==2 {print $4}')"
print_info "Inodes Available" "$(df -i / | awk 'NR==2 {print $4}')"

if [[ $COLOR -eq 1 ]]; then
  echo -e "\n\033[1;32m✓ Comprehensive diagnostics completed successfully!\033[0m" | lolcat
else
  echo -e "\n✓ Comprehensive diagnostics completed successfully!"
fi

echo -e "\n=== LOG FILE SUMMARY ==="
echo "Diagnostics log saved to: $LOG_FILE"
echo "Log file size: $(du -h "$LOG_FILE" 2>/dev/null | cut -f1 || echo 'Unknown')"
echo "Log file permissions: $(ls -la "$LOG_FILE" 2>/dev/null | awk '{print $1}' || echo 'Unknown')"

# Show last few lines of the log file as confirmation
echo -e "\n=== LOG FILE PREVIEW (Last 5 lines) ==="
tail -5 "$LOG_FILE" 2>/dev/null || echo "Could not read log file"

echo -e "\n=== LOG FILE LOCATION ==="
echo "Full path: $(realpath "$LOG_FILE" 2>/dev/null || echo "$LOG_FILE")"
echo "Directory: $(dirname "$LOG_FILE")"
echo "Filename: $(basename "$LOG_FILE")" 