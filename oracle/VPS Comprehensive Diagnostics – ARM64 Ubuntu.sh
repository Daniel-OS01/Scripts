#!/usr/bin/env bash
###############################################################################
# VPS Comprehensive Diagnostics – ARM64 Ubuntu
# Runs the SAME command set you received earlier (now wrapped as a script).
# It gathers a system, network, Docker & CasaOS audit into one log file.
#
#   • Default log path …… /DATA/Downloads
#   • Interactive prompt … lets you change the destination when finished
#
# Usage:  chmod +x vps-diagnostics.sh && sudo ./vps-diagnostics.sh
###############################################################################
set -euo pipefail
IFS=$'\n\t'

# ----- 1.  Preparation -------------------------------------------------------
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
TMP_LOG="$(mktemp -p /tmp vps_diag_${TIMESTAMP}_XXXX.log)"
readonly TMP_LOG

# Redirect EVERYTHING (stdout & stderr) into the log and to the screen
exec > >(tee -a "${TMP_LOG}") 2>&1

echo "=== VPS DIAGNOSTICS – START: $(date) ==="
echo "Log file (temporary): ${TMP_LOG}"
echo

# Ensure essential tools exist
sudo apt update -qq
sudo apt install -y \
  util-linux sysstat net-tools iproute2 dnsutils curl \
  lsb-release grep awk sed coreutils findutils iptables \
  ufw sudo arp-scan procps iputils-ping net-tools dnsutils \
  gnupg lsof jq column || true

# Optional colour helpers (ignored if not desired)
sudo apt install -y lolcat grc || true

# ----- 2.  SYSTEM & OS OVERVIEW ---------------------------------------------
echo -e "\n===== SYSTEM & OS OVERVIEW ====="
printf "%-20s %s\n" "Architecture:" "$(uname -m)"
printf "%-20s %s\n" "Kernel & OS:" "$(uname -sr); $(lsb_release -ds)"
printf "%-20s %s\n" "Hostname:" "$(hostname)"
printf "%-20s %s\n" "FQDN:" "$(hostname -f 2>/dev/null || echo N/A)"
printf "%-20s %s\n" "Domain:" "$(dnsdomainname 2>/dev/null || echo N/A)"
printf "%-20s %s\n" "Uptime:" "$(uptime -p)"
printf "%-20s %s\n" "Boot Time:" "$(uptime -s)"
printf "%-20s %s\n" "Timezone:" "$(timedatectl show --property=Timezone --value)"
printf "%-20s %s\n" "Locale:" "$(localectl status | grep 'System Locale' | cut -d= -f2)"

# ----- 3.  HARDWARE RESOURCES -----------------------------------------------
echo -e "\n===== HARDWARE RESOURCES ====="
printf "%-20s %s\n" "CPU Cores:" "$(nproc)"
printf "%-20s %s\n" "CPU Model:" "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' | head -c60)..."
printf "%-20s %s\n" "CPU Architecture:" "$(lscpu | grep Architecture | awk '{print $2}')"
printf "%-20s %s\n" "CPU MHz:" "$(lscpu | grep 'CPU MHz' | awk '{print $3}')"
printf "%-20s %s\n" "Total RAM:" "$(free -h --si | awk '/^Mem:/ {print $2}')"
printf "%-20s %s\n" "Used RAM:" "$(free -h --si | awk '/^Mem:/ {print $3 \" (\" $5 \" available)\"}')"
printf "%-20s %s\n" "Swap Total:" "$(free -h --si | awk '/^Swap:/ {print $2}')"
printf "%-20s %s\n" "Swap Used:" "$(free -h --si | awk '/^Swap:/ {print $3}')"
printf "%-20s %s\n" "Load Average:" "$(uptime | sed 's/.*load average: //')"

# ----- 4.  DISK & STORAGE INFORMATION ---------------------------------------
echo -e "\n===== DISK & STORAGE INFORMATION ====="
echo "=== DISK USAGE ==="
df -h --output=source,size,used,avail,pcent,target | { command -v column >/dev/null && column -t || cat; }
echo
echo "=== DISK USAGE BY DIRECTORY (/) ==="
du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10
echo
echo "=== DISK USAGE (/data) ==="
du -sh /data 2>/dev/null || echo "/data directory not found"
echo
echo "=== INODES USAGE ==="
df -i | { command -v column >/dev/null && column -t || cat; }

# ----- 5.  DOCKER & CONTAINER PLATFORM --------------------------------------
echo -e "\n===== DOCKER & CONTAINER PLATFORM ====="
printf "%-20s %s\n" "Docker Version:" "$(sudo docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'Not installed')"
printf "%-20s %s\n" "Docker Daemon:" "$(systemctl is-active docker)"
printf "%-20s %s\n" "Docker Root Dir:" "$(sudo docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo N/A)"
printf "%-20s %s\n" "CasaOS Version:" "$(grep '^VERSION=' /etc/os-release | cut -d= -f2 | tr -d '\"' || echo N/A)"
printf "%-20s %s\n" "CasaOS Service:" "$(systemctl is-active casaos-gateway 2>/dev/null || echo 'Not running')"

echo
echo "=== DOCKER NETWORKS ==="
sudo docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}\t{{.Internal}}"

echo
echo "=== RUNNING CONTAINERS ==="
sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}\t{{.Size}}"

echo
echo "=== ALL CONTAINERS (INCLUDING STOPPED) ==="
sudo docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}"

echo
echo "=== EXITED/FAILED CONTAINERS ==="
sudo docker ps -a --filter status=exited --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

echo
echo "=== CONTAINER RESOURCE ALLOCATION ==="
sudo docker ps -q | xargs -I {} sudo docker inspect {} --format '{{.Name}}: CPU={{.HostConfig.CpuShares}} Memory={{.HostConfig.Memory}} RestartCount={{.RestartCount}}'

# ----- 6.  NETWORK CONFIGURATION --------------------------------------------
echo -e "\n===== NETWORK CONFIGURATION ====="
echo "=== NETWORK INTERFACES ==="
ip -4 addr show | awk '/^[0-9]+:/ {iface=$2} /inet / {print iface, $2}'
echo
echo "=== NETWORK INTERFACES DETAILED ==="
ip addr show | grep -E '^[0-9]+:|inet '
echo
echo "=== ROUTING TABLE ==="
ip route show | { command -v column >/dev/null && column -t || cat; }
echo
echo "=== DEFAULT GATEWAY ==="
ip route | grep default | awk '{print $3}'
echo
echo "=== DNS CONFIGURATION ==="
grep -v '^#' /etc/resolv.conf
echo
echo "=== DNS SERVERS ==="
grep '^nameserver' /etc/resolv.conf | awk '{print $2}'

# ----- 7.  PORT & FIREWALL AUDIT -------------------------------------------
echo -e "\n===== PORT ANALYSIS ====="
echo "=== CRITICAL SERVICE PORTS ==="
ss -tulnH | awk '$4 ~ /:22$|:80$|:443$|:8000$|:8080$|:9000$|:81$|:6001$|:6002$/ {printf "%-8s %-25s %s\n",$1,$4,($7?$7:"-")}' | sort
echo
echo "=== ALL LISTENING PORTS ==="
ss -tulnH | awk 'BEGIN{printf "%-8s %-25s %-20s\n","Proto","Address:Port","Process"} {printf "%-8s %-25s %-20s\n",$1,$4,($7?$7:"-")}'
echo
echo "=== HIGH PORTS LISTENING (>=8000) ==="
ss -tulnH | awk '$4 ~ /:[8-9][0-9][0-9][0-9]$/ {printf "%-8s %-25s %s\n",$1,$4,($7?$7:"-")}' | head -20

echo -e "\n===== FIREWALL STATUS ====="
echo "=== UFW STATUS ==="
sudo ufw status verbose 2>/dev/null || echo "UFW not available"
echo
echo "=== IPTABLES INPUT CHAIN ==="
sudo iptables -L INPUT -n --line-numbers | head -20
echo
echo "=== IPTABLES CASAOS RULES ==="
sudo iptables -L CASAOS-OCI-PORTS -n --line-numbers 2>/dev/null | head -20 || echo "CasaOS rules not found"
echo
echo "=== IPTABLES NAT RULES ==="
sudo iptables -t nat -L -n | head -15

# ----- 8.  SERVICE & PROCESS AUDIT -----------------------------------------
echo -e "\n===== RUNNING SERVICES AUDIT ====="
echo "=== SYSTEMD ACTIVE SERVICES ==="
systemctl list-units --type=service --state=active --no-pager | head -20
echo
echo "=== SYSTEMD FAILED SERVICES ==="
systemctl list-units --type=service --state=failed --no-pager

echo
echo "=== KEY SERVICES STATUS ==="
printf "%-20s %s\n" "SSH:" "$(systemctl is-active ssh)"
printf "%-20s %s\n" "Docker:" "$(systemctl is-active docker)"
printf "%-20s %s\n" "CasaOS Gateway:" "$(systemctl is-active casaos-gateway 2>/dev/null || echo N/A)"
printf "%-20s %s\n" "CasaOS MessageBus:" "$(systemctl is-active casaos-message-bus 2>/dev/null || echo N/A)"
printf "%-20s %s\n" "CasaOS UserService:" "$(systemctl is-active casaos-user-service 2>/dev/null || echo N/A)"
printf "%-20s %s\n" "Nginx:" "$(systemctl is-active nginx 2>/dev/null || echo N/A)"
printf "%-20s %s\n" "Apache2:" "$(systemctl is-active apache2 2>/dev/null || echo N/A)"

echo
echo "=== TOP PROCESSES BY CPU ==="
ps aux --sort=-%cpu | head -10 | awk 'BEGIN{printf "%-10s %-8s %-8s %-50s\n","USER","CPU%","MEM%","COMMAND"} NR>1{printf "%-10s %-8s %-8s %-50s\n",$1,$3,$4,$11}'
echo
echo "=== TOP PROCESSES BY MEMORY ==="
ps aux --sort=-%mem | head -10 | awk 'BEGIN{printf "%-10s %-8s %-8s %-50s\n","USER","CPU%","MEM%","COMMAND"} NR>1{printf "%-10s %-8s %-8s %-50s\n",$1,$3,$4,$11}'

# ----- 9.  DOCKER DIAGNOSTICS ----------------------------------------------
echo -e "\n===== DOCKER DIAGNOSTICS ====="
echo "=== DOCKER SYSTEM INFO ==="
sudo docker system df
echo
echo "=== DOCKER IMAGES ==="
sudo docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
echo
echo "=== DOCKER VOLUMES ==="
sudo docker volume ls
echo
echo "=== DOCKER VOLUME SIZES ==="
sudo docker system df -v | grep -A100 "Local Volumes:" | head -20
echo
echo "=== DOCKER CONTAINER RESOURCE USAGE ==="
sudo docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"

echo
echo "=== CONTAINER HEALTH STATUS ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

echo
echo "=== DOCKER DAEMON STATUS ==="
systemctl status docker --no-pager -l | head -25
echo
echo "=== DOCKER SOCKET PERMISSIONS ==="
ls -la /var/run/docker.sock
echo
echo "=== DOCKER GROUP MEMBERSHIP ==="
getent group docker

# ----- 10. NETWORK AUDIT ----------------------------------------------------
echo -e "\n===== NETWORK AUDIT ====="
echo "=== NETWORK CONNECTIONS (TOP 20) ==="
ss -tup | head -20
echo
echo "=== NETWORK STATISTICS ==="
awk 'NR>2 {print $1, $2, $10}' /proc/net/dev | { command -v column >/dev/null && column -t || cat; }
echo
echo "=== NETWORK ROUTING ==="
netstat -rn 2>/dev/null | head -10 || ip route show
echo
echo "=== ARP TABLE ==="
arp -a 2>/dev/null | head -10 || ip neigh show | head -10

# ----- 11. SECURITY AUDIT ---------------------------------------------------
echo -e "\n===== SECURITY AUDIT ====="
printf "%-20s %s\n" "Current User:" "$(whoami)"
printf "%-20s %s\n" "Groups:" "$(id -nG | tr ' ' ',')"
printf "%-20s %s\n" "Docker Group:" "$(groups | grep -q docker && echo 'Yes' || echo 'No')"
printf "%-20s %s\n" "SSH Status:" "$(systemctl is-active ssh)"
echo
echo "=== CURRENT SESSIONS ==="
who
echo
echo "=== RECENT LOGINS ==="
last -n 10
echo
echo "=== CRITICAL FILE PERMISSIONS ==="
ls -la /etc/passwd /etc/shadow /etc/sudoers 2>/dev/null
echo
echo "=== DOCKER SOCKET PERMISSIONS (again) ==="
ls -la /var/run/docker.sock

# ----- 12. TROUBLESHOOTING & LOGS ------------------------------------------
echo -e "\n===== TROUBLESHOOTING & LOGS ====="
journalctl -p err -n 10 --no-pager
journalctl -u docker -p err -n 10 --no-pager
journalctl -u casaos-gateway -p err -n 10 --no-pager 2>/dev/null || true
dmesg | tail -10
echo
echo "=== KERNEL RING BUFFER ERRORS ==="
dmesg | grep -i error | tail -10
echo
echo "=== SYSTEM LOG ERRORS ==="
grep -i error /var/log/syslog 2>/dev/null | tail -10 || echo "Syslog not accessible"

# ----- 13. CONNECTIVITY TESTS ----------------------------------------------
echo -e "\n===== INTERNET CONNECTIVITY ====="
ping -c 3 8.8.8.8 >/dev/null 2>&1 && \
  echo "No Internet connectivity issues found - Google DNS reachable" || \
  echo "Internet connectivity issues detected - cannot reach Google DNS"

nslookup google.com >/dev/null 2>&1 && \
  echo "No DNS resolution issues found - google.com resolves correctly" || \
  echo "DNS resolution issues detected - cannot resolve google.com"

echo
echo "=== EXTENDED CONNECTIVITY TESTS ==="
ping -c 2 1.1.1.1 >/dev/null 2>&1 && echo "Cloudflare DNS: No issues found" || echo "Cloudflare DNS: Connection failed"
ping -c 2 8.8.4.4 >/dev/null 2>&1 && echo "Google DNS Secondary: No issues found" || echo "Google DNS Secondary: Connection failed"
curl -Is --connect-timeout 5 https://www.google.com >/dev/null 2>&1 && echo "HTTPS Connectivity: No issues found" || echo "HTTPS Connectivity: Connection failed"

# ----- 14. CONTAINER LOG ERROR SCRAPE --------------------------------------
echo -e "\n===== RECENT CONTAINER ERRORS ====="
sudo docker ps -q | while read -r container; do
  name="$(sudo docker inspect "$container" --format '{{.Name}}' | sed 's|/||')"
  echo "=== $name ERRORS ==="
  sudo docker logs "$container" --tail 10 2>&1 | grep -i error | head -5 || true
done

# ----- 15. PSI / LOAD / ARM64 DETAILS ---------------------------------------
echo -e "\n===== SYSTEM RESOURCE MONITORING ====="
echo "=== CURRENT SYSTEM LOAD ==="
cat /proc/loadavg
echo
echo "=== MEMORY PRESSURE (PSI) ==="
cat /proc/pressure/memory 2>/dev/null || echo "PSI not available"
echo
echo "=== CPU PRESSURE (PSI) ==="
cat /proc/pressure/cpu 2>/dev/null || echo "PSI not available"

echo -e "\n===== ARM64 ARCHITECTURE INFORMATION ====="
printf "%-20s %s\n" "CPU Model:" "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
printf "%-20s %s\n" "CPU Features:" "$(grep -m1 'Features' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' | head -c80)..."
printf "%-20s %s\n" "Hardware:" "$(grep -m1 'Hardware' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"

echo
echo "=== CONTAINER RUNTIME INFORMATION ==="
sudo docker info --format '{{.ServerVersion}}' 2>/dev/null | head -1
sudo docker version --format 'Runtime: {{.Server.Platform.Name}}' 2>/dev/null
containerd --version 2>/dev/null || echo "containerd version not available"
runc --version 2>/dev/null || echo "runc version not available"

# ----- 16. FINAL SUMMARY ----------------------------------------------------
echo -e "\n===== FINAL SYSTEM SUMMARY ====="
printf "%-20s %s\n" "Generated on:" "$(date)"
printf "%-20s %s\n" "Docker Status:" "$(systemctl is-active docker)"
printf "%-20s %s\n" "Running Containers:" "$(sudo docker ps -q | wc -l)"
printf "%-20s %s\n" "Total Containers:" "$(sudo docker ps -aq | wc -l)"
printf "%-20s %s\n" "Docker Images:" "$(sudo docker images -q | wc -l)"
printf "%-20s %s\n" "Docker Volumes:" "$(sudo docker volume ls -q | wc -l)"
printf "%-20s %s\n" "Load Average:" "$(uptime | awk -F'load average:' '{print $2}')"

echo -e "\n=== VPS DIAGNOSTICS – COMPLETE: $(date) ==="
echo "Temporary log file: ${TMP_LOG}"

# ----- 17.  Ask where to save final log -------------------------------------
default_dir="/DATA/Downloads"
read -rp "Enter destination directory for the log [${default_dir}]: " dest_dir
dest_dir="${dest_dir:-$default_dir}"

# Create directory if it doesn’t exist
if [[ ! -d "${dest_dir}" ]]; then
  echo "Directory not found – creating ${dest_dir} ..."
  sudo mkdir -p "${dest_dir}"
  sudo chown "$(id -u):$(id -g)" "${dest_dir}"
fi

final_log="${dest_dir}/vps_diagnostics_${TIMESTAMP}.log"
mv "${TMP_LOG}" "${final_log}"
echo "Log saved to: ${final_log}"
echo "Done ✔"
