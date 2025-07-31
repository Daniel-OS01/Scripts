#!/usr/bin/env bash
###############################################################################
# dokploy-traefik-doctor.sh
# Ver 3.1 – Oracle Cloud / Ubuntu 22.04 LTS
#
# One-shot validator & auto-fixer for Dokploy v0.24+ and Traefik v3 stacks.
# This version addresses issues related to SSH hardening, firewall rules,
# Docker Swarm health, Traefik configuration (including passHostHeader typo),
# ACME certificate storage, environment variables, system resources, and DNS.
#
# Outputs:
#   - /var/log/dokploy_diagnostics_<timestamp>.txt (full diagnostics report)
#   - /etc/dokploy/traefik/traefik.yml              (static config)
#   - /etc/dokploy/traefik/dynamic/trafic-domain.yml (sample domain router)
#   - /etc/dokploy/.env.dokploy                     (env vars, inc. BETTER_AUTH_SECRET)
#   - /etc/dokploy/traefik/acme.json                (Let's Encrypt cert store)
###############################################################################
set -euo pipefail
IFS=$'\n\t'
VERSION="3.1"
REPORT="/var/log/dokploy_diagnostics_$(date +%Y%m%d_%H%M%S).txt"
GREEN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[1;33m'; NC='\033[0m'

# --- Configuration ---
# This script uses the following variables injected by the main.sh orchestrator
# from the central config.env file:
# - LETSENCRYPT_EMAIL: Used for ACME registration with Traefik.
# - DOMAIN_NAME: Used as the default domain for DNS and Traefik router checks.
#
# For clarity in this script, we assign them to local variables.
TRAEFIK_EMAIL="$LETSENCRYPT_EMAIL"
DEFAULT_DOMAIN="$DOMAIN_NAME"
# -----------------------------------


# Helper functions for colored output and logging
header() { echo -e "\n====== $1 ======\n" | tee -a "$REPORT"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"  | tee -a "$REPORT"; }
warn()  { echo -e "${YLW}[WARN]${NC} $1" | tee -a "$REPORT"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$REPORT"; exit 1; }

# Function to robustly get the public IP
get_public_ip() {
    local ip=""
    # Try multiple external services for robustness
    ip=$(curl -sS --max-time 5 icanhazip.com || true)
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }
    ip=$(curl -sS --max-time 5 ipecho.net/plain || true)
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }
    ip=$(curl -sS --max-time 5 ifconfig.me || true)
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }

    warn "Could not determine public IP from external services. DNS check might be inaccurate."
    # Fallback to guessing from active network interface if direct external check fails
    # This might not be the true public IP if behind NAT, but better than nothing
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $NF;exit}') # Using 1.1.1.1 for a reliable external IP
    if [[ -n "$ip" ]]; then
        warn "Using local interface IP: $ip (may not be true public IP if behind NAT)"
        echo "$ip"
        return 0
    fi

    fail "Failed to determine public IP. Cannot perform DNS check accurately."
}

echo -e "Dokploy-Traefik Doctor $VERSION  —  $(date)\nHost: $(hostname)\n" | tee -a "$REPORT"

###############################################################################
# 0. SSH & USER HARDENING  ----------------------------------------------------
header "0. SSH & User Hardening"

# 0.a – Duplicate ubuntu key into root if missing
if [[ -f /home/ubuntu/.ssh/authorized_keys ]]; then
    UBKEY="/home/ubuntu/.ssh/authorized_keys"
    ROOTKEY="/root/.ssh/authorized_keys"
    mkdir -p /root/.ssh
    if ! cmp -s "$UBKEY" "$ROOTKEY"; then
        cp "$UBKEY" "$ROOTKEY"
        chmod 600 "$ROOTKEY"
        chown root:root "$ROOTKEY" # Ensure root owns it explicitly
        ok "Root authorized_keys aligned with ubuntu"
    else
        ok "Root & ubuntu authorized_keys already match"
    fi
else
    warn "Ubuntu key file missing – skip copy (verify /home/ubuntu/.ssh/authorized_keys exists)"
fi

# 0.b – sudoers NOPASSWD for ubuntu user
grep -q "^ubuntu .*NOPASSWD" /etc/sudoers \
  && ok "ubuntu NOPASSWD sudo already present" \
  || { echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers; ok "Added ubuntu to sudoers"; }

# 0.c – sshd config baseline (will be applied/restarted at end of script)
SSHD="/etc/ssh/sshd_config"
sed -i 's/#\?PasswordAuthentication .*/PasswordAuthentication no/' "$SSHD"
# Ensure PermitRootLogin is set to 'without-password' for key-based login only
grep -q "^PermitRootLogin without-password" "$SSHD" \
  || sed -i 's/#\?PermitRootLogin .*/PermitRootLogin without-password/' "$SSHD"
ok "sshd configuration set for hardening (PasswordAuth OFF, root-login keys-only)"

###############################################################################
# 1. PACKAGE & SERVICE CHECK  -------------------------------------------------
header "1. Packages & Services"

# List essential packages
REQUIRED_PACKAGES=(curl openssh-server ufw iptables-persistent netfilter-persistent)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    warn "$pkg not installed. Attempting to install..."
    apt update -qq && apt install -y "$pkg"
    if dpkg -s "$pkg" &>/dev/null; then
      ok "$pkg installed."
    else
      fail "Failed to install $pkg. Please install manually."
    fi
  else
    ok "$pkg already installed."
  fi
done

systemctl is-active --quiet ssh && ok "sshd active." || fail "sshd inactive. Please start sshd."

###############################################################################
# 2. FIREWALL & IPTABLES  -----------------------------------------------------
header "2. UFW / iptables Rules"

# UFW enable if not active
if ! ufw status | grep -q "Status: active"; then
  ufw --force enable >/dev/null # Use force to avoid interactive prompt
  ok "UFW enabled."
else
  ok "UFW already enabled."
fi

# UFW rules for Dokploy and Swarm
# Common ports: HTTP, HTTPS, Dokploy UI, Traefik Dashboard, Swarm management, Overlay network
ufw allow 80,443,3000,8080,2377,7946,4789,996/tcp >/dev/null # Added 996 for Dokploy's internal use/webhook
ufw allow 7946,4789/udp >/dev/null
ok "UFW rules for Dokploy & Swarm ports present."

# iptables DOCKER-USER chain inserts (to ensure Docker doesn't override them)
# Insert at rule 1 to give them precedence
for p in 2377 7946 4789 996; do # Added 996
  if ! iptables -C DOCKER-USER -p tcp --dport "$p" -j ACCEPT 2>/dev/null; then
    iptables -I DOCKER-USER 1 -p tcp --dport "$p" -j ACCEPT; ok "iptables ACCEPT $p/tcp added to DOCKER-USER."
  else
    ok "iptables ACCEPT $p/tcp already in DOCKER-USER."
  fi
done
for p in 7946 4789; do
  if ! iptables -C DOCKER-USER -p udp --dport "$p" -j ACCEPT 2>/dev/null; then
    iptables -I DOCKER-USER 1 -p udp --dport "$p" -j ACCEPT; ok "iptables ACCEPT $p/udp added to DOCKER-USER."
  else
    ok "iptables ACCEPT $p/udp already in DOCKER-USER."
  fi
done

# Reposition REJECT rule to the end of FORWARD chain (common Docker Swarm fix)
if iptables -C FORWARD -j REJECT --reject-with icmp-host-prohibited 2>/dev/null; then
  iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited
  iptables -A FORWARD -j REJECT --reject-with icmp-host-prohibited
  ok "FORWARD REJECT rule repositioned to end of chain."
else
  ok "FORWARD REJECT rule not found or already at end."
fi
netfilter-persistent save >/dev/null
ok "netfilter-persistent saved iptables rules."

###############################################################################
# 3. SWARM & PORT HEALTH  -----------------------------------------------------
header "3. Docker Swarm / Port Liveness"

docker info --format '{{.Swarm.LocalNodeState}}' | grep -qi active \
  && ok "Docker Swarm active." || fail "Swarm not initialised. Please initialize Docker Swarm."

# Check if essential Dokploy services are running (by name convention from previous Docker Compose)
DOKPLOY_SWARM_SERVICES=(dokploy dokploy_dokploy-traefik dokploy_dokploy-redis dokploy_dokploy-postgres)
for svc in "${DOKPLOY_SWARM_SERVICES[@]}"; do
    # Check for both "1/1" for replicated services and "running" status for tasks
    if docker service ls --filter name="$svc" --format '{{.Replicas}}' | grep -qE '1/1'; then
        ok "Service $svc reports 1/1 replicas."
    elif docker service ls --filter name="$svc" &>/dev/null; then
        warn "Service $svc is present but not 1/1 replicas. Review 'docker service ps $svc'."
    else
        warn "Service $svc not found. Is Dokploy fully deployed?"
    fi
done

# Check if essential ports are actually listening locally
REQUIRED_LISTENING_PORTS=(80 443 3000 8080 2377 7946 4789)
for port in "${REQUIRED_LISTENING_PORTS[@]}"; do
  proto=tcp # Default
  if [[ "$port" == "4789" || "$port" == "7946" ]]; then proto=udp; fi

  if ss -lwn "( sport = :$port )" | grep -q LISTEN; then
      ok "Port $port/$proto listening locally."
  else
      warn "Port $port/$proto NOT listening locally. Check service status."
  fi
done


###############################################################################
# 4. TRAEFIK FILE STRUCTURE & SYNTAX  -----------------------------------------
header "4. Traefik Configuration Files"

BASE="/etc/dokploy/traefik"
STATIC="$BASE/traefik.yml"
DYNAMIC="$BASE/dynamic"
ACME="$BASE/acme.json" # Redefine for local scope if needed

mkdir -p "$DYNAMIC"
ok "Traefik config directories ensured."

# 4.a Static traefik.yml configuration
if [[ ! -f "$STATIC" ]]; then
cat >"$STATIC" <<YAML
entryPoints:
  web:       { address: ":80" }
  websecure: { address: ":443" }

certificatesResolvers:
  letsencrypt:
    acme:
      email: $TRAEFIK_EMAIL # User-defined email
      storage: /traefik/acme.json
      httpChallenge:
        entryPoint: web # Or tlsChallenge for 443 only

providers:
  docker:
    exposedByDefault: false
  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true
YAML
  ok "Created default traefik.yml."
else
  ok "traefik.yml already exists."
fi

# 4.b Dynamic – sample router for the default domain
# This ensures a clean, correctly formatted file is always available or created.
if [[ ! -f "$DYNAMIC/trafic-domain.yml" ]]; then
cat >"$DYNAMIC/trafic-domain.yml" <<YML
http:
  routers:
    trafic-router:
      rule: Host(\`$DEFAULT_DOMAIN\`) # User-defined domain
      entryPoints: [web, websecure]
      service: trafic-service
      tls:
        certResolver: letsencrypt
  services:
    trafic-service:
      loadBalancer:
        servers:
          - url: http://dokploy:3000
        passHostHeader: true # Correct placement
YML
  ok "Seeded trafic-domain.yml with correct passHostHeader placement."
else
  # If file exists, check for *common* passHostHeader indentation issue (as per previous convo)
  if grep -q "servers:" "$DYNAMIC/trafic-domain.yml" && \
     awk '/servers:/{f=1} /passHostHeader:/{if(f){p_line=NR}} END{if(p_line && p_line > 0){print "found"}}' "$DYNAMIC/trafic-domain.yml" | grep -q "found"; then
    warn "trafic-domain.yml might have a 'passHostHeader' indentation issue. Please verify manually or overwrite with a fresh template."
  else
    ok "trafic-domain.yml already exists and seems okay."
  fi
fi

# 4.c Comprehensive YAML linting for all Traefik config files
# This checks all .yml files in the Traefik config and dynamic directories
if ! python3 - <<'PY' &>/dev/null; then
import yaml, glob, sys
yaml_files = glob.glob('/etc/dokploy/traefik/**/*.yml', recursive=True) + \
             glob.glob('/etc/dokploy/traefik/*.yml', recursive=False)
for path in yaml_files:
    try:
        with open(path, 'r') as f:
            yaml.safe_load(f)
        sys.stdout.write(f"OK: {path}\n")
    except yaml.YAMLError as e:
        sys.stderr.write(f"FAIL: {path} - {e}\n")
        sys.exit(1)
PY
  fail "One or more Traefik YAML files have syntax errors. Check output above."
else
  ok "All Traefik YAML files parse cleanly."
fi

###############################################################################
# 5. ACME STORE  --------------------------------------------------------------
header "5. acme.json Permissions & Size"

# Handle acme.json if it was mistakenly created as a directory
if [[ -d "$ACME" ]]; then
  rm -rf "$ACME"
  warn "Removed mis-created acme.json directory."
fi
# Ensure acme.json exists as a file and has correct permissions
[[ -f "$ACME" ]] || touch "$ACME"
chmod 600 "$ACME"; chown root:root "$ACME"
ok "acme.json exists and has correct permissions (600 root:root)."

# Check if acme.json is empty (implies no certs have been issued or stored)
# Use 'stat -c %s' for portability, checking for 0 size
if [[ "$(stat -c %s "$ACME")" -eq 0 ]]; then
  warn "acme.json is empty (0 bytes). Certificates will be (re)issued on next Traefik reload."
else
  ok "acme.json is non-empty. Existing certificates may be present."
fi

###############################################################################
# 6. ENV FILES / BETTER AUTH  -------------------------------------------------
header "6. Dokploy Environment (.env)"

ENV_FILE="/etc/dokploy/.env.dokploy"
[[ -f "$ENV_FILE" ]] || touch "$ENV_FILE"

# Check and set BETTER_AUTH_SECRET if not present or too short
if ! grep -q "^BETTER_AUTH_SECRET=" "$ENV_FILE"; then
  echo "BETTER_AUTH_SECRET=$(openssl rand -base64 32)" >> "$ENV_FILE"
  ok "Generated and added BETTER_AUTH_SECRET to .env.dokploy."
else
  local_secret=$(grep "BETTER_AUTH_SECRET=" "$ENV_FILE" | cut -d= -f2 | xargs) # xargs to trim whitespace
  if [[ ${#local_secret} -ge 32 ]]; then
    ok "BETTER_AUTH_SECRET is set and sufficient length."
  else
    warn "BETTER_AUTH_SECRET is set but too short. Consider generating a new one."
  fi
fi

# Check for social provider warnings (if applicable)
if grep -q "WARN \[Better Auth\]: Social provider github is missing clientId or clientSecret" "$REPORT"; then
    warn "Dokploy logs indicate missing GitHub OAuth credentials. Configure GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET."
fi
if grep -q "WARN \[Better Auth\]: Social provider google is missing clientId or clientSecret" "$REPORT"; then
    warn "Dokploy logs indicate missing Google OAuth credentials. Configure GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."
fi

###############################################################################
# 7. RESOURCES  ---------------------------------------------------------------
header "7. Disk & Memory"

# Check disk usage (root filesystem)
df -h / | awk 'NR==2{print $5}' | sed 's/%//' | {
  read P;
  if [[ "$P" -lt 90 ]]; then
    ok "Disk utilization: ${P}% (OK)."
  else
    warn "Disk utilization: ${P}% (HIGH! Consider freeing space)."
  fi
}

# Check RAM usage
free -m | awk '/Mem:/{used=$3; total=$2; print int(used/total*100)}' | {
  read M;
  if [[ "$M" -lt 90 ]]; then
    ok "RAM utilization: ${M}% (OK)."
  else
    warn "RAM utilization: ${M}% (HIGH! Consider increasing RAM or optimizing services)."
  fi
}

###############################################################################
# 8. RELOAD SERVICES  ---------------------------------------------------------
header "8. Reloading Traefik Service"

# Determine the correct Traefik service name in Swarm or fallback to container
TRAEFIK_SERVICE_NAME="dokploy_dokploy-traefik" # Default for Swarm
if docker service ls --format '{{.Name}}' | grep -q "$TRAEFIK_SERVICE_NAME"; then
  ok "Attempting to force-update Swarm service $TRAEFIK_SERVICE_NAME..."
  docker service update --force "$TRAEFIK_SERVICE_NAME" >>"$REPORT" 2>&1 \
    && ok "Traefik service reloaded via Swarm." \
    || warn "Failed to reload Traefik Swarm service. Check '$REPORT' for details."
else
  # Fallback if Dokploy's Traefik isn't part of the default swarm stack name
  # or is running as a standalone container (less common for Dokploy)
  warn "Swarm service '$TRAEFIK_SERVICE_NAME' not found. Trying 'dokploy-traefik' standalone container restart."
  if docker ps -a --format '{{.Names}}' | grep -q "dokploy-traefik"; then
    docker restart dokploy-traefik >>"$REPORT" 2>&1 \
      && ok "Standalone dokploy-traefik container restarted." \
      || warn "Failed to restart standalone dokploy-traefik container. Check '$REPORT'."
  else
    warn "No running Traefik service or container found by expected names."
  fi
fi

###############################################################################
# 9. DNS SANITY  --------------------------------------------------------------
header "9. DNS Record Check"

PUBIP=$(get_public_ip) # Call the function to get public IP
if [[ -z "$PUBIP" ]]; then
    warn "Skipping final DNS check as public IP could not be determined."
else
    # Use the user-defined DEFAULT_DOMAIN for the DNS check
    DOMAIN_IP=$(dig +short "$DEFAULT_DOMAIN" | tail -1 || true) # Use tail -1 for multi-line output, || true to prevent pipefail
    if [[ "$PUBIP" == "$DOMAIN_IP" ]]; then
        ok "Domain $DEFAULT_DOMAIN A-record resolves to this host's public IP ($PUBIP)."
    else
        warn "DNS mismatch: $DEFAULT_DOMAIN resolves to $DOMAIN_IP (should be $PUBIP). Update your DNS A record."
    fi
fi

###############################################################################
# Final SSHD Restart to apply all SSH config changes
header "10. Applying SSHD Configuration"
systemctl restart sshd \
  && ok "sshd restarted successfully to apply configuration changes." \
  || warn "Failed to restart sshd. Manual restart may be required."

###############################################################################
echo -e "\n${GREEN}All diagnostics complete${NC} – report saved to $REPORT"
