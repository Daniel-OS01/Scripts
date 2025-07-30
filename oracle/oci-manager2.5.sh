#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# oci-manager2.4.sh – Auto‐sync host ports → iptables & OCI Security List
# ---------------------------------------------------------------------------

set -o nounset -o pipefail
[[ -n "${BASH_VERSION:-}" ]] || { echo "Please run with bash, not sh."; exit 1; }

# ──────────────────── Logging Setup ────────────────────
LOG_DIR="/DATA/Documents"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/oci-manager2-$(date +%Y%m%d-%H%M%S).log"
# duplicate all stdout+stderr to both console and log
exec > >(tee -a "$LOG_FILE") 2>&1

# ──────────────────── Constants ────────────────────────
TENANCY_OCID={{TENANCY_OCID}}
VCN_OCID={{VCN_OCID}}
INSTANCE_OCID={{INSTANCE_OCID}}
DEFAULT_SECURITY_LIST_OCID={{DEFAULT_SECURITY_LIST_OCID}}

CHAIN="CASAOS-OCI-PORTS"
SERVICE="/etc/systemd/system/oci-port-sync.service"
TIMER="/etc/systemd/system/oci-port-sync.timer"

declare -A PORTMAP
NEW_IPT=()
NEW_OCI=()
SKIPPED_OCI=()
OCI_FLAGS=""

# ──────────────────── Helpers ─────────────────────────
info()    { printf '[INFO]  %s - %s\n' "$(date '+%F %T')" "$*"; }
ok()      { printf '[ OK ]  %s - %s\n' "$(date '+%F %T')" "$*"; }
fail()    { printf '[FAIL] %s - %s\n' "$(date '+%F %T')" "$*"; exit 1; }
need()    { command -v "$1" &>/dev/null || fail "Missing dependency: $1"; }
run()     { info "CMD ➜ $*"; "$@" || fail "Command failed: $*"; }

# ────────────────── Troubleshooting Header ─────────────
print_header() {
  local script realdir owner perms downer dperms mtime
  script=$(realpath "$0")
  perms=$(stat -c '%a' "$script")
  owner=$(stat -c '%U:%G' "$script")
  mtime=$(stat -c '%y' "$script")
  realdir=$(dirname "$script")
  dperms=$(stat -c '%a' "$realdir")
  downer=$(stat -c '%U:%G' "$realdir")
  cat << HEADER

────────────────── SCRIPT ENVIRONMENT ──────────────────
 Script path : $script
 File owner  : $owner    perms: $perms    mtime: $mtime
 Dir         : $realdir
 Dir owner   : $downer    perms: $dperms
 Run as      : $(id)
 Shell       : $SHELL
 CWD         : $PWD
 Umask       : $(umask)
────────────────────────────────────────────────────────

HEADER
}

# ────────────────── Ensure OCI CLI & Auth ───────────────
ensure_oci() {
  # Check required dependencies
  local deps=("jq" "ss" "iptables")
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      info "Missing dependency: $dep"
      return 1
    fi
  done
  
  # Optional dependencies
  if ! command -v curl &>/dev/null; then
    info "Warning: curl not found, some features may not work"
  fi
  
  # Install OCI CLI if needed
  if ! command -v oci &>/dev/null; then
    info "Installing OCI CLI..."
    if command -v python3 &>/dev/null; then
      if command -v pip3 &>/dev/null; then
        if pip3 install --quiet oci-cli 2>/dev/null; then
          info "OCI CLI installed successfully"
        else
          info "Failed to install OCI CLI via pip3"
          return 1
        fi
      else
        info "pip3 not found, cannot install OCI CLI"
        return 1
      fi
    else
      info "python3 not found, cannot install OCI CLI"
      return 1
    fi
  fi
  
  # Set up authentication
  if [[ -f "$HOME/.oci/config" ]]; then
    info "Using ~/.oci/config for authentication"
    OCI_FLAGS=""
  else
    info "No ~/.oci/config, using instance-principal auth"
    OCI_FLAGS="--auth instance_principal"
  fi
  
  # Test OCI authentication
  if oci $OCI_FLAGS iam region list >/dev/null 2>&1; then
    ok "OCI CLI authenticated"
    return 0
  else
    info "OCI authentication failed"
    return 1
  fi
}

# ────────────────── Port Discovery ─────────────────────
gather_ports() {
  PORTMAP=()
  info "Gathering listening TCP/UDP ports via ss..."
  while read -r proto _ _ _ addr _; do
    port=${addr##*:}
    [[ $port =~ ^[0-9]+$ ]] && PORTMAP["$port/$proto"]=1
  done < <(ss -tunlH)

  if command -v docker &>/dev/null; then
    info "Gathering Docker published ports..."
    docker ps --format '{{.Ports}}' | tr ',' '\n' | grep -E '0\.0\.0\.0|:::' \
      | while read -r line; do
          port=$(grep -oP '(?<=:)\d+(?=-|/)' <<<"$line")
          proto=$(grep -oP '(tcp|udp)$'    <<<"$line")
          [[ $port && $proto ]] && PORTMAP["$port/$proto"]=1
      done
  fi

  [[ -f /var/run/casaos/gateway.url ]] && \
    PORTMAP["$(cut -d: -f2 /var/run/casaos/gateway.url)/tcp"]=1

  # Always include SSH/HTTP(S)
  PORTMAP["22/tcp"]=1
  PORTMAP["80/tcp"]=1
  PORTMAP["443/tcp"]=1

  ok "Discovered ${#PORTMAP[@]} unique ports"
}

# ────────────────── iptables Sync ──────────────────────
sync_iptables() {
  info "Syncing iptables chain $CHAIN"
  
  # Create chain if it doesn't exist
  if ! iptables -nL "$CHAIN" &>/dev/null; then
    run iptables -N "$CHAIN" || { fail "Failed to create iptables chain $CHAIN"; return 1; }
  fi
  
  # Add chain to INPUT if not already there
  if ! iptables -C INPUT -j "$CHAIN" &>/dev/null; then
    run iptables -I INPUT 1 -j "$CHAIN" || { fail "Failed to add chain to INPUT"; return 1; }
  fi

  # Get existing rules safely
  local existing_output
  existing_output=$(iptables -S "$CHAIN" 2>/dev/null) || { info "No existing rules in $CHAIN"; existing_output=""; }
  
  declare -a existing=()
  if [[ -n "$existing_output" ]]; then
    mapfile -t existing < <(echo "$existing_output" | awk '/--dport/ {for(i=1;i<=NF;i++){if($i=="--dport"){printf "%s/%s\n", $(i+1), $4}}}')
  fi
  
  # Add new rules only if not duplicates
  for p in "${!PORTMAP[@]}"; do
    if [[ ${#existing[@]} -eq 0 ]] || ! printf '%s\n' "${existing[@]}" | grep -qx "$p"; then
      port=${p%/*}; proto=${p#*/}
      if iptables -A "$CHAIN" -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
        NEW_IPT+=("$p")
        info "Added iptables rule: $p"
      else
        info "Failed to add iptables rule: $p"
      fi
    else
      info "Skipping duplicate iptables rule: $p"
    fi
  done

  if [[ ${#NEW_IPT[@]} -gt 0 ]]; then
    if command -v netfilter-persistent &>/dev/null; then
      run netfilter-persistent save
    else
      info "netfilter-persistent not found, rules may not persist after reboot"
    fi
  fi
  ok "iptables sync complete (added ${#NEW_IPT[@]} rules)"
}

# ────────────────── OCI: List Current Ports ────────────
oci_list_current() {
  local SL="$1"
  local data
  declare -g -A EXISTING_OCI_PORTS
  EXISTING_OCI_PORTS=()

  info "Fetching current security list configuration"
  if ! data=$(oci $OCI_FLAGS network security-list get --security-list-id "$SL" --query 'data' --raw-output 2>/dev/null); then
    info "Failed to fetch security list data for $SL"
    return 1
  fi

  if [[ -z "$data" || "$data" == "null" ]]; then
    info "No data returned from security list query"
    return 1
  fi

  info "Current Ingress Rules (Ports/Protocols):"
  local port_lines=()
  local ingress_rules
  
  if ! ingress_rules=$(echo "$data" | jq -c '."ingress-security-rules"[]' 2>/dev/null); then
    info "No ingress rules found or failed to parse"
  else
    while IFS= read -r rule; do
      [[ -z "$rule" ]] && continue
      
      local proto src stateless desc tcp_opts udp_opts icmp_opts proto_name port_str
      proto=$(echo "$rule" | jq -r '.protocol // "unknown"' 2>/dev/null)
      src=$(echo "$rule" | jq -r '.source // "unknown"' 2>/dev/null)
      stateless=$(echo "$rule" | jq -r '."is-stateless" // false' 2>/dev/null)
      desc=$(echo "$rule" | jq -r '.description // ""' 2>/dev/null)
      tcp_opts=$(echo "$rule" | jq -c '."tcp-options" // null' 2>/dev/null)
      udp_opts=$(echo "$rule" | jq -c '."udp-options" // null' 2>/dev/null)
      icmp_opts=$(echo "$rule" | jq -c '."icmp-options" // null' 2>/dev/null)
      
      case "$proto" in
        6) proto_name="tcp" ;;
        17) proto_name="udp" ;;
        1) proto_name="icmp" ;;
        all) proto_name="all" ;;
        *) proto_name="$proto" ;;
      esac
      
      port_str=""
      local port_keys=()
      
      if [[ "$proto_name" == "tcp" && "$tcp_opts" != "null" && -n "$tcp_opts" ]]; then
        local min max
        min=$(echo "$tcp_opts" | jq -r '."destination-port-range".min // ""' 2>/dev/null)
        max=$(echo "$tcp_opts" | jq -r '."destination-port-range".max // ""' 2>/dev/null)
        if [[ -n "$min" && -n "$max" && "$min" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]]; then
          if [[ "$min" == "$max" ]]; then
            port_str="$min"
            port_keys+=("$min/tcp")
          else
            port_str="$min-$max"
            # Limit range to avoid excessive loops
            if [[ $((max - min)) -lt 1000 ]]; then
              for ((p=min; p<=max; p++)); do port_keys+=("$p/tcp"); done
            fi
          fi
        else
          port_str="ALL"
        fi
      elif [[ "$proto_name" == "udp" && "$udp_opts" != "null" && -n "$udp_opts" ]]; then
        local min max
        min=$(echo "$udp_opts" | jq -r '."destination-port-range".min // ""' 2>/dev/null)
        max=$(echo "$udp_opts" | jq -r '."destination-port-range".max // ""' 2>/dev/null)
        if [[ -n "$min" && -n "$max" && "$min" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]]; then
          if [[ "$min" == "$max" ]]; then
            port_str="$min"
            port_keys+=("$min/udp")
          else
            port_str="$min-$max"
            # Limit range to avoid excessive loops
            if [[ $((max - min)) -lt 1000 ]]; then
              for ((p=min; p<=max; p++)); do port_keys+=("$p/udp"); done
            fi
          fi
        else
          port_str="ALL"
        fi
      elif [[ "$proto_name" == "icmp" ]]; then
        port_str="ICMP"
      elif [[ "$proto_name" == "all" ]]; then
        port_str="ALL"
      else
        port_str="$proto_name"
      fi
      
      info "  • $proto_name $port_str (source: $src) stateless: $stateless${desc:+ desc: $desc}"
      for k in "${port_keys[@]}"; do port_lines+=("$k"); done
    done <<< "$ingress_rules"
  fi
  
  # Populate the global array
  for k in "${port_lines[@]}"; do EXISTING_OCI_PORTS["$k"]=1; done

  info "Current Egress Rules (Ports/Protocols):"
  local egress_rules
  if ! egress_rules=$(echo "$data" | jq -c '."egress-security-rules"[]' 2>/dev/null); then
    info "No egress rules found or failed to parse"
  else
    while IFS= read -r rule; do
      [[ -z "$rule" ]] && continue
      
      local proto dst stateless desc tcp_opts udp_opts icmp_opts proto_name port_str
      proto=$(echo "$rule" | jq -r '.protocol // "unknown"' 2>/dev/null)
      dst=$(echo "$rule" | jq -r '.destination // "unknown"' 2>/dev/null)
      stateless=$(echo "$rule" | jq -r '."is-stateless" // false' 2>/dev/null)
      desc=$(echo "$rule" | jq -r '.description // ""' 2>/dev/null)
      tcp_opts=$(echo "$rule" | jq -c '."tcp-options" // null' 2>/dev/null)
      udp_opts=$(echo "$rule" | jq -c '."udp-options" // null' 2>/dev/null)
      icmp_opts=$(echo "$rule" | jq -c '."icmp-options" // null' 2>/dev/null)
      
      case "$proto" in
        6) proto_name="tcp" ;;
        17) proto_name="udp" ;;
        1) proto_name="icmp" ;;
        all) proto_name="all" ;;
        *) proto_name="$proto" ;;
      esac
      
      port_str=""
      if [[ "$proto_name" == "tcp" && "$tcp_opts" != "null" && -n "$tcp_opts" ]]; then
        local min max
        min=$(echo "$tcp_opts" | jq -r '."destination-port-range".min // ""' 2>/dev/null)
        max=$(echo "$tcp_opts" | jq -r '."destination-port-range".max // ""' 2>/dev/null)
        if [[ -n "$min" && -n "$max" && "$min" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]]; then
          port_str=$([ "$min" == "$max" ] && echo "$min" || echo "$min-$max")
        else
          port_str="ALL"
        fi
      elif [[ "$proto_name" == "udp" && "$udp_opts" != "null" && -n "$udp_opts" ]]; then
        local min max
        min=$(echo "$udp_opts" | jq -r '."destination-port-range".min // ""' 2>/dev/null)
        max=$(echo "$udp_opts" | jq -r '."destination-port-range".max // ""' 2>/dev/null)
        if [[ -n "$min" && -n "$max" && "$min" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]]; then
          port_str=$([ "$min" == "$max" ] && echo "$min" || echo "$min-$max")
        else
          port_str="ALL"
        fi
      elif [[ "$proto_name" == "icmp" ]]; then
        port_str="ICMP"
      elif [[ "$proto_name" == "all" ]]; then
        port_str="ALL"
      else
        port_str="$proto_name"
      fi
      
      info "  • $proto_name $port_str (destination: $dst) stateless: $stateless${desc:+ desc: $desc}"
    done <<< "$egress_rules"
  fi

  info "Found ${#EXISTING_OCI_PORTS[@]} existing OCI ingress ports"
  if [[ ${#EXISTING_OCI_PORTS[@]} -gt 0 ]]; then
    for port in "${!EXISTING_OCI_PORTS[@]}"; do
      info "  • $port"
    done
  fi
  
  return 0
}

# ────────────────── OCI: Perform Update ────────────────
oci_perform_update() {
  local SL="$1" data="$2" new_ingress_json="$3" new_egress_json="$4"

  local ingress_rules egress_rules
  ingress_rules=$(echo "$data" | jq '."ingress-security-rules"')
  egress_rules=$(echo "$data" | jq '."egress-security-rules"')

  local merged_ingress_json merged_egress_json
  merged_ingress_json=$(jq -s '.[0] + .[1]' <(echo "$ingress_rules") <(echo "$new_ingress_json"))
  merged_egress_json=$(jq -s '.[0] + .[1]' <(echo "$egress_rules") <(echo "$new_egress_json"))

  info "Adding ${#NEW_OCI[@]} missing ports to OCI security-list …"
  tmp=$(mktemp)
  echo '{}' | jq \
    --argjson in "$merged_ingress_json" \
    --argjson eg "$merged_egress_json" \
    '.["ingress-security-rules"]=$in | .["egress-security-rules"]=$eg' > "$tmp"

  run oci $OCI_FLAGS network security-list update \
          --security-list-id "$SL" --from-json "file://$tmp" --force
  rm -f "$tmp"
  ok "OCI security-list updated (added: ${NEW_OCI[*]})"
}

# ────────────────── OCI Security-List Sync (robust, no duplicates or redundants) ─────────────
oci_sync() {
  local SL="$1"

  info "Fetching current rules for security-list $SL"
  local data ingress_rules egress_rules
  
  if ! data=$(oci $OCI_FLAGS network security-list get \
           --security-list-id "$SL" --query 'data' --raw-output 2>/dev/null); then
    info "Failed to fetch security list data"
    return 1
  fi
  
  if [[ -z "$data" || "$data" == "null" ]]; then
    info "No data returned from security list query"
    return 1
  fi
  
  if ! ingress_rules=$(echo "$data" | jq '."ingress-security-rules"' 2>/dev/null); then
    info "Failed to parse ingress rules"
    return 1
  fi
  
  if ! egress_rules=$(echo "$data" | jq '."egress-security-rules"' 2>/dev/null); then
    info "Failed to parse egress rules"
    return 1
  fi

  # Prepare arrays for new rules
  local new_ingress_json='[]'
  local new_egress_json='[]'
  NEW_OCI=()
  SKIPPED_OCI=()

  # JQ script templates for coverage checks
  local ingress_check='
    any(.[];
      (.source == "0.0.0.0/0") and
      (.protocol == "all" or .protocol == $proto_num) and
      (if .protocol == "all" then true
       elif .protocol == $proto_num then
         if $proto_num == "6" then
           (if has("tcpOptions") and (.tcpOptions | has("destinationPortRange")) then
              $p >= .tcpOptions.destinationPortRange.min and $p <= .tcpOptions.destinationPortRange.max
            else true end)
         elif $proto_num == "17" then
           (if has("udpOptions") and (.udpOptions | has("destinationPortRange")) then
              $p >= .udpOptions.destinationPortRange.min and $p <= .udpOptions.destinationPortRange.max
            else true end)
         else true end
       else false end)
    )
  '

  local egress_check='
    any(.[];
      (.destination == "0.0.0.0/0") and
      (.protocol == "all" or .protocol == $proto_num) and
      (if .protocol == "all" then true
       elif .protocol == $proto_num then
         if $proto_num == "6" then
           (if has("tcpOptions") and (.tcpOptions | has("destinationPortRange")) then
              $p >= .tcpOptions.destinationPortRange.min and $p <= .tcpOptions.destinationPortRange.max
            else true end)
         elif $proto_num == "17" then
           (if has("udpOptions") and (.udpOptions | has("destinationPortRange")) then
              $p >= .udpOptions.destinationPortRange.min and $p <= .udpOptions.destinationPortRange.max
            else true end)
         else true end
       else false end)
    )
  '

  # Check and add only if not covered
  for pp in "${!PORTMAP[@]}"; do
    local port proto proto_num
    port=${pp%/*}; proto=${pp#*/}
    proto_num=$([[ $proto == tcp ]] && echo "6" || echo "17")
    
    # Validate port number
    if ! [[ $port =~ ^[0-9]+$ ]] || [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
      info "Skipping invalid port: $port"
      continue
    fi

    # Ingress check with error handling
    local ing_covered
    if ing_covered=$(echo "$ingress_rules" | jq --argjson p "$port" --arg proto_num "$proto_num" "$ingress_check" 2>/dev/null); then
      if [[ "$ing_covered" != "true" ]]; then
        local new_ing
        if new_ing=$(jq -n \
          --argjson n "$proto_num" --argjson p "$port" --arg proto "$proto" '
          if $proto == "tcp" then
            { protocol: $n, source: "0.0.0.0/0", isStateless: false, "tcp-options": { "destination-port-range": { min: $p, max: $p } } }
          elif $proto == "udp" then
            { protocol: $n, source: "0.0.0.0/0", isStateless: false, "udp-options": { "destination-port-range": { min: $p, max: $p } } }
          else
            { protocol: $n, source: "0.0.0.0/0", isStateless: false }
          end
        ' 2>/dev/null); then
          new_ingress_json=$(echo "$new_ingress_json" | jq --argjson rule "$new_ing" '. + [$rule]' 2>/dev/null)
          NEW_OCI+=("ingress:$pp")
        else
          info "Failed to create ingress rule for $pp"
        fi
      else
        SKIPPED_OCI+=("ingress:$pp (already covered)")
      fi
    else
      info "Failed to check ingress coverage for $pp"
    fi

    # Egress check with error handling
    local eg_covered
    if eg_covered=$(echo "$egress_rules" | jq --argjson p "$port" --arg proto_num "$proto_num" "$egress_check" 2>/dev/null); then
      if [[ "$eg_covered" != "true" ]]; then
        local new_eg
        if new_eg=$(jq -n \
          --argjson n "$proto_num" --argjson p "$port" --arg proto "$proto" '
          if $proto == "tcp" then
            { protocol: $n, destination: "0.0.0.0/0", isStateless: false, "tcp-options": { "destination-port-range": { min: $p, max: $p } } }
          elif $proto == "udp" then
            { protocol: $n, destination: "0.0.0.0/0", isStateless: false, "udp-options": { "destination-port-range": { min: $p, max: $p } } }
          else
            { protocol: $n, destination: "0.0.0.0/0", isStateless: false }
          end
        ' 2>/dev/null); then
          new_egress_json=$(echo "$new_egress_json" | jq --argjson rule "$new_eg" '. + [$rule]' 2>/dev/null)
          NEW_OCI+=("egress:$pp")
        else
          info "Failed to create egress rule for $pp"
        fi
      else
        SKIPPED_OCI+=("egress:$pp (already covered)")
      fi
    else
      info "Failed to check egress coverage for $pp"
    fi
  done

  # If no new rules, exit
  if [[ ${#NEW_OCI[@]} -eq 0 ]]; then
    ok "OCI security-list already covers every required port – no change"
    if [[ ${#SKIPPED_OCI[@]} -gt 0 ]]; then
      info "Skipped (already covered): ${SKIPPED_OCI[*]}"
    fi
    return
  fi

  # Merge new rules with existing rules (never remove anything)
  local merged_ingress_json merged_egress_json tmp
  
  if ! merged_ingress_json=$(jq -s '.[0] + .[1]' <(echo "$ingress_rules") <(echo "$new_ingress_json") 2>/dev/null); then
    info "Failed to merge ingress rules"
    return 1
  fi
  
  if ! merged_egress_json=$(jq -s '.[0] + .[1]' <(echo "$egress_rules") <(echo "$new_egress_json") 2>/dev/null); then
    info "Failed to merge egress rules"
    return 1
  fi

  info "Adding ${#NEW_OCI[@]} missing ports to OCI security-list …"
  
  if ! tmp=$(mktemp); then
    info "Failed to create temporary file"
    return 1
  fi
  
  if ! echo '{}' | jq \
    --argjson in "$merged_ingress_json" \
    --argjson eg "$merged_egress_json" \
    '.["ingress-security-rules"]=$in | .["egress-security-rules"]=$eg' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    info "Failed to create update JSON"
    return 1
  fi

  if oci $OCI_FLAGS network security-list update \
          --security-list-id "$SL" --from-json "file://$tmp" --force 2>/dev/null; then
    ok "OCI security-list updated (added: ${NEW_OCI[*]})"
  else
    info "Failed to update OCI security list"
    rm -f "$tmp"
    return 1
  fi
  
  rm -f "$tmp"
  
  if [[ ${#SKIPPED_OCI[@]} -gt 0 ]]; then
    info "Skipped (already covered): ${SKIPPED_OCI[*]}"
  fi
}

# ────────────────── Scan & Remove Duplicates ───────────────────
scan_and_remove_duplicates() {
  echo
  info "Scanning for duplicate iptables rules in $CHAIN..."

  # Defensive: check if iptables is available
  if ! command -v iptables &>/dev/null; then
    info "iptables not found, skipping iptables duplicate scan."
    return 0
  fi

  # Check if the chain exists before proceeding
  if ! iptables -nL "$CHAIN" &>/dev/null; then
    ok "Chain $CHAIN does not exist. No iptables duplicates to scan."
    return 0
  fi

  # Get all rules in the chain (full rule spec), handle errors robustly
  local ipt_output
  if ! ipt_output=$(iptables -S "$CHAIN" 2>/dev/null); then
    ok "Could not list rules for $CHAIN. No iptables duplicates to scan."
    return 0
  fi

  # Defensive: handle empty output
  if [[ -z "$ipt_output" ]]; then
    ok "No rules found in $CHAIN. No iptables duplicates to scan."
    return 0
  fi

  # Find duplicates
  declare -a all_rules
  mapfile -t all_rules < <(echo "$ipt_output" | grep -- '-j ACCEPT' || true)

  if [[ ${#all_rules[@]} -eq 0 ]]; then
    ok "No ACCEPT rules found in $CHAIN."
    return 0
  fi

  declare -A rule_counts=()
  declare -a dups=()

  for rule in "${all_rules[@]}"; do
    rule_key=$(echo "$rule" | sed 's/^-A [^ ]* //')
    ((rule_counts["$rule_key"]++))
    if [[ ${rule_counts["$rule_key"]} -eq 2 ]]; then
      dups+=("$rule_key")
    fi
  done

  if [[ ${#dups[@]} -gt 0 ]]; then
    info "Duplicate iptables rules found:" 
    for d in "${dups[@]}"; do echo "  • $d"; done
    read -rp "Remove duplicate iptables rules from $CHAIN? (y/n): " rmipt
    if [[ $rmipt =~ ^[Yy]$ ]]; then
      for d in "${dups[@]}"; do
        local attempts=0
        while [[ $attempts -lt 20 ]]; do
          local current_output count
          current_output=$(iptables -S "$CHAIN" 2>/dev/null) || break
          count=$(echo "$current_output" | grep -c -- "-A $CHAIN $d" || echo "0")
          if [[ $count -le 1 ]]; then break; fi
          if iptables -D "$CHAIN" $d 2>/dev/null; then
            info "Removed duplicate: $d"
          else
            info "Failed to remove duplicate: $d"
            break
          fi
          ((attempts++))
        done
      done
      ok "Duplicate iptables rules removed."
    else
      ok "Skipped iptables duplicate removal."
    fi
  else
    ok "No duplicate iptables rules found."
  fi

  echo
  info "Scanning for duplicate OCI ingress rules..."

  # Defensive: check if oci is available
  if ! command -v oci &>/dev/null; then
    info "oci CLI not found, skipping OCI duplicate scan."
    return 0
  fi

  # Safely call oci_list_current
  if ! oci_list_current "$DEFAULT_SECURITY_LIST_OCID"; then
    info "Failed to list OCI rules, skipping duplicate scan"
    return 0
  fi

  # Check if EXISTING_OCI_PORTS is populated
  if [[ ${#EXISTING_OCI_PORTS[@]} -eq 0 ]]; then
    ok "No OCI ports found to check for duplicates."
    return 0
  fi

  declare -a oci_dups=()
  declare -A oci_seen=()

  for port in "${!EXISTING_OCI_PORTS[@]}"; do
    if [[ -n "${oci_seen[$port]:-}" ]]; then
      oci_dups+=("$port")
    else
      oci_seen[$port]=1
    fi
  done

  if [[ ${#oci_dups[@]} -gt 0 ]]; then
    info "Duplicate OCI ingress rules found:"
    for d in "${oci_dups[@]}"; do echo "  • $d"; done
    read -rp "Remove duplicate OCI ingress rules? (y/n): " rmoci
    if [[ $rmoci =~ ^[Yy]$ ]]; then
      local data ingress_rules egress_rules unique_rules tmp
      if ! data=$(oci $OCI_FLAGS network security-list get --security-list-id "$DEFAULT_SECURITY_LIST_OCID" --query 'data' --raw-output 2>/dev/null); then
        info "Failed to fetch OCI security list data"
        return 1
      fi
      if ! ingress_rules=$(echo "$data" | jq '."ingress-security-rules"' 2>/dev/null); then
        info "Failed to parse ingress rules"
        return 1
      fi
      if ! unique_rules=$(echo "$ingress_rules" | jq 'unique_by(.protocol, .source, ."is-stateless", .description, .tcpOptions.destinationPortRange.min, .tcpOptions.destinationPortRange.max, .udpOptions.destinationPortRange.min, .udpOptions.destinationPortRange.max)' 2>/dev/null); then
        info "Failed to create unique rules"
        return 1
      fi
      if ! egress_rules=$(echo "$data" | jq '."egress-security-rules"' 2>/dev/null); then
        info "Failed to parse egress rules"
        return 1
      fi
      if ! tmp=$(mktemp); then
        info "Failed to create temp file"
        return 1
      fi
      if ! echo '{}' | jq \
        --argjson in "$unique_rules" \
        --argjson eg "$egress_rules" \
        '.["ingress-security-rules"]=$in | .["egress-security-rules"]=$eg' > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        info "Failed to create update JSON"
        return 1
      fi
      if oci $OCI_FLAGS network security-list update \
        --security-list-id "$DEFAULT_SECURITY_LIST_OCID" --from-json "file://$tmp" --force 2>/dev/null; then
        ok "Duplicate OCI ingress rules removed."
      else
        info "Failed to update OCI security list"
      fi
      rm -f "$tmp"
    else
      ok "Skipped OCI duplicate removal."
    fi
  else
    ok "No duplicate OCI ingress rules found."
  fi
}

# ────────────────── systemd Timer Setup ─────────────────
setup_timer() {
  local SL=$1
  info "Creating systemd service & timer for 10m auto‐sync"
  cat > "$SERVICE" <<EOF
[Unit]
Description=OCI & iptables port sync
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/oci-manager2.sh --sync-only $SL
EOF

  cat > "$TIMER" <<EOF
[Unit]
Description=Run port sync every 10 minutes

[Timer]
OnCalendar=*:0/10
Persistent=true

[Install]
WantedBy=timers.target
EOF

  run systemctl daemon-reload
  run systemctl enable --now "$(basename "$TIMER")"
  ok "Automatic sync enabled"
}

# ────────────────── Interactive Menu ───────────────────
interactive() {
  print_header
  ensure_oci

  # Security‐List selection
  PS3="Choose Security List [1-4]: "
  select opt in \
    "Use default [$DEFAULT_SECURITY_LIST_OCID]" \
    "Enter custom OCID" \
    "Skip OCI sync" \
    "Scan for duplicates (iptables & OCI)"; do
    case $REPLY in
      1) SL="$DEFAULT_SECURITY_LIST_OCID"; break ;;
      2) read -rp "Enter Security List OCID: " SL; break ;;
      3) SL=""; break ;;
      4) scan_and_remove_duplicates; return ;;
      *) echo "Invalid choice"; ;;
    esac
  done

  gather_ports
  echo
  info "Discovered ports:"
  for p in "${!PORTMAP[@]}"; do echo "  • $p"; done | sort -n
  echo

  info "Synchronization Options:"
  PS3="Choose action [1-3]: "
  select act in "One-time sync now" "Enable 10m auto-sync" "Both"; do
    case $REPLY in
      1) ACTION=sync;    break ;;
      2) ACTION=timer;   break ;;
      3) ACTION=both;    break ;;
      *) echo "Invalid choice"; ;;
    esac
  done

  # Perform actions
  if [[ $ACTION =~ sync|both ]]; then
    # A. Ask for iptables sync
    read -rp "Do you want to add ports to iptables? (y/n): " ipt_confirm
    if [[ $ipt_confirm =~ ^[Yy]$ ]]; then
      sync_iptables
    else
      ok "Skipping iptables sync"
    fi

    # B. OCI sync with display and confirmation (if SL selected)
    if [[ -n $SL ]]; then
      # List current OCI ports
      oci_list_current "$SL"

      # Fetch OCI security list data for update
      data=$(oci $OCI_FLAGS network security-list get --security-list-id "$SL" --query 'data' --raw-output)

      # Use robust jq-based coverage checks for both ingress and egress (like oci_sync)
      NEW_OCI=()
      SKIPPED_OCI_INGRESS=()
      SKIPPED_OCI_EGRESS=()
      local new_ingress_json='[]'
      local new_egress_json='[]'
      ingress_rules=$(echo "$data" | jq '."ingress-security-rules"')
      egress_rules=$(echo "$data" | jq '."egress-security-rules"')
      for pp in "${!PORTMAP[@]}"; do
        port=${pp%/*}; proto=${pp#*/}; proto_num=$([[ $proto == tcp ]] && echo "6" || echo "17")

        # Ingress check (robust)
        ing_covered=$(echo "$ingress_rules" | jq --argjson p "$port" --arg proto_num "$proto_num" '
          any(.[]; (.source == "0.0.0.0/0") and (.protocol == "all" or .protocol == $proto_num) and
            (if .protocol == "all" then true
             elif .protocol == $proto_num then
               if $proto_num == "6" then
                 (if has("tcp-options") and (."tcp-options" | has("destination-port-range")) then
                    $p >= ."tcp-options"."destination-port-range".min and $p <= ."tcp-options"."destination-port-range".max
                  else true end)
               elif $proto_num == "17" then
                 (if has("udp-options") and (."udp-options" | has("destination-port-range")) then
                    $p >= ."udp-options"."destination-port-range".min and $p <= ."udp-options"."destination-port-range".max
                  else true end)
               else true end
             else false end)
          )' 2>/dev/null)

        if [[ "$ing_covered" != "true" ]]; then
          new_ing=$(jq -n \
            --argjson n "$proto_num" --argjson p "$port" --arg proto "$proto" '
            if $proto == "tcp" then
              { protocol: $n, source: "0.0.0.0/0", isStateless: false, "tcp-options": { "destination-port-range": { min: $p, max: $p } } }
            elif $proto == "udp" then
              { protocol: $n, source: "0.0.0.0/0", isStateless: false, "udp-options": { "destination-port-range": { min: $p, max: $p } } }
            else
              { protocol: $n, source: "0.0.0.0/0", isStateless: false }
            end
          ')
          new_ingress_json=$(echo "$new_ingress_json" | jq --argjson rule "$new_ing" '. + [$rule]')
          NEW_OCI+=("ingress:$pp")
        else
          SKIPPED_OCI_INGRESS+=("ingress:$pp (already covered)")
        fi

        # Egress check (robust)
        eg_covered=$(echo "$egress_rules" | jq --argjson p "$port" --arg proto_num "$proto_num" '
          any(.[]; (.destination == "0.0.0.0/0") and (.protocol == "all" or .protocol == $proto_num) and
            (if .protocol == "all" then true
             elif .protocol == $proto_num then
               if $proto_num == "6" then
                 (if has("tcp-options") and (."tcp-options" | has("destination-port-range")) then
                    $p >= ."tcp-options"."destination-port-range".min and $p <= ."tcp-options"."destination-port-range".max
                  else true end)
               elif $proto_num == "17" then
                 (if has("udp-options") and (."udp-options" | has("destination-port-range")) then
                    $p >= ."udp-options"."destination-port-range".min and $p <= ."udp-options"."destination-port-range".max
                  else true end)
               else true end
             else false end)
          )' 2>/dev/null)

        if [[ "$eg_covered" != "true" ]]; then
          new_eg=$(jq -n \
            --argjson n "$proto_num" --argjson p "$port" --arg proto "$proto" '
            if $proto == "tcp" then
              { protocol: $n, destination: "0.0.0.0/0", isStateless: false, "tcp-options": { "destination-port-range": { min: $p, max: $p } } }
            elif $proto == "udp" then
              { protocol: $n, destination: "0.0.0.0/0", isStateless: false, "udp-options": { "destination-port-range": { min: $p, max: $p } } }
            else
              { protocol: $n, destination: "0.0.0.0/0", isStateless: false }
            end
          ')
          new_egress_json=$(echo "$new_egress_json" | jq --argjson rule "$new_eg" '. + [$rule]')
          NEW_OCI+=("egress:$pp")
        else
          SKIPPED_OCI_EGRESS+=("egress:$pp (already covered)")
        fi
      done

      # Display proposed new ports (split by ingress/egress)
      echo
      if [[ ${#NEW_OCI[@]} -gt 0 ]]; then
        info "Proposed new ports to add to OCI:"
        for p in "${NEW_OCI[@]}"; do echo "  • $p"; done
      else
        info "No new ports to add to OCI"
      fi
      if [[ ${#SKIPPED_OCI_INGRESS[@]} -gt 0 ]]; then
        info "Skipped Ingress (already covered):"
        for s in "${SKIPPED_OCI_INGRESS[@]}"; do echo "  • $s"; done
      fi
      if [[ ${#SKIPPED_OCI_EGRESS[@]} -gt 0 ]]; then
        info "Skipped Egress (already covered):"
        for s in "${SKIPPED_OCI_EGRESS[@]}"; do echo "  • $s"; done
      fi
      echo

      # Ask for confirmation
      if [[ ${#NEW_OCI[@]} -gt 0 ]]; then
        read -rp "Confirm adding these new ports to OCI? (y/n): " oci_confirm
        if [[ $oci_confirm =~ ^[Yy]$ ]]; then
          oci_perform_update "$SL" "$data" "$new_ingress_json" "$new_egress_json"
        else
          ok "Skipping OCI update"
        fi
      else
        ok "No OCI changes needed"
      fi
    fi
  fi

  if [[ -n $SL && $ACTION =~ timer|both ]]; then setup_timer "$SL"; fi

  # Summary
  echo
  info "SUMMARY of changes:"
  if [[ ${#NEW_IPT[@]} -gt 0 ]]; then
    echo "iptables – added ports:" ${NEW_IPT[*]}
  else
    echo "iptables – no new ports"
  fi
  if [[ -n $SL ]]; then
    if [[ ${#NEW_OCI[@]} -gt 0 ]]; then
      echo "OCI – added ports:" ${NEW_OCI[*]}
    else
      echo "OCI – no new ports"
    fi
  fi
  echo "Log file: $LOG_FILE"
  echo
  read -n1 -s -r -p "Press any key to exit…"
}

# ────────────────── Entry Point ────────────────────────
case "${1:-}" in
  --interactive) 
    interactive 
    ;;
  --sync-only)   
    if [[ -z "${2:-}" ]]; then
      echo "Error: Security list OCID required for --sync-only"
      echo "Usage: $0 --interactive | --sync-only <security-list-ocid>"
      exit 1
    fi
    if ! ensure_oci; then
      fail "Failed to initialize OCI CLI"
    fi
    if ! gather_ports; then
      fail "Failed to gather ports"
    fi
    if ! sync_iptables; then
      info "iptables sync failed, continuing with OCI sync"
    fi
    if ! oci_sync "$2"; then
      fail "OCI sync failed"
    fi
    ;;
  *) 
    echo "Usage: $0 --interactive | --sync-only <security-list-ocid>" 
    exit 1 
    ;;
esac
