#!/usr/bin/env bash
# oci-add-port.sh – Add a port to iptables and OCI Security List (Ingress & Egress)
set -o nounset -o pipefail
[[ -n "${BASH_VERSION:-}" ]] || { echo "Please run with bash, not sh."; exit 1; }

# --- Config ---
DEFAULT_SECURITY_LIST_OCID={{DEFAULT_SECURITY_LIST_OCID}}}
CHAIN="CASAOS-OCI-PORTS"
OCI_FLAGS=""

info()    { printf '[INFO]  %s - %s\n' "$(date '+%F %T')" "$*"; }
ok()      { printf '[ OK ]  %s - %s\n' "$(date '+%F %T')" "$*"; }
fail()    { printf '[FAIL] %s - %s\n' "$(date '+%F %T')" "$*"; exit 1; }
run()     { info "CMD ➜ $*"; "$@" || fail "Command failed: $*"; }

# --- Ensure dependencies ---
for dep in jq iptables oci; do
  command -v "$dep" &>/dev/null || fail "Missing dependency: $dep"
done

# --- Ask user for port and protocol ---
read -rp "Enter port number to open: " PORT
[[ "$PORT" =~ ^[0-9]+$ ]] || fail "Invalid port number"
if (( PORT < 1 || PORT > 65535 )); then fail "Port must be 1-65535"; fi

echo "\nWhich protocol(s) do you want to open for port $PORT?"
echo "  1) TCP   - For most web, SSH, and application traffic."
echo "           Examples: HTTP (80), HTTPS (443), SSH (22), FTP (21), SMTP (25), MySQL (3306), RDP (3389), etc."
echo "           Choose this for most server applications, file transfer, remote access, and web services."
echo "  2) UDP   - For DNS, streaming, VoIP, gaming, and some VPNs."
echo "           Examples: DNS (53), DHCP (67/68), SNMP (161), WireGuard VPN (51820), many online games, video/audio streaming."
echo "           Choose this for services that use fast, connectionless communication."
echo "  3) BOTH  - Open both TCP and UDP for this port."
echo "           Examples: Some applications/games use both protocols, or if you are unsure which is needed."
echo "           FTP (21): Usually TCP only. DNS (53): Often both TCP and UDP. Games: Check documentation."
echo "\nGuidance:"
echo "  - For FTP (port 21): Select 1 (TCP)"
echo "  - For DNS (port 53): Select 3 (BOTH) if you want to support all DNS queries."
echo "  - For HTTP/HTTPS (80/443): Select 1 (TCP)"
echo "  - For most games: Check if they require UDP, TCP, or both."
echo "  - If unsure, select 3 (BOTH) to allow both protocols."
echo
read -rp "Select protocol [1-3]: " PROTO_CHOICE
case "$PROTO_CHOICE" in
  1) PROTOS=(tcp) ;;
  2) PROTOS=(udp) ;;
  3) PROTOS=(tcp udp) ;;
  *) fail "Invalid selection. Please enter 1, 2, or 3." ;;
esac

for PROTO in "${PROTOS[@]}"; do
  # --- Add to iptables ---
  if ! iptables -nL "$CHAIN" &>/dev/null; then
    run iptables -N "$CHAIN"
  fi
  if ! iptables -C INPUT -j "$CHAIN" &>/dev/null; then
    run iptables -I INPUT 1 -j "$CHAIN"
  fi
  if iptables -C "$CHAIN" -p "$PROTO" --dport "$PORT" -j ACCEPT &>/dev/null; then
    ok "iptables rule already exists for $PORT/$PROTO"
  else
    run iptables -A "$CHAIN" -p "$PROTO" --dport "$PORT" -j ACCEPT
    ok "Added iptables rule for $PORT/$PROTO"
  fi

done

# --- Ask for Security List OCID ---
read -rp "Enter OCI Security List OCID (or press Enter for default): " SL
SL=${SL:-$DEFAULT_SECURITY_LIST_OCID}

data=$(oci $OCI_FLAGS network security-list get --security-list-id "$SL" --query 'data' --raw-output)
ingress_rules=$(echo "$data" | jq '."ingress-security-rules"')
egress_rules=$(echo "$data" | jq '."egress-security-rules"')

for PROTO in "${PROTOS[@]}"; do
  proto_num=$([[ $PROTO == tcp ]] && echo "6" || echo "17")
  # --- Check if rule exists (Ingress) ---
  ing_covered=$(echo "$ingress_rules" | jq --argjson p "$PORT" --arg proto_str "$PROTO" --arg proto_num "$proto_num" '
    any(.[];
      (.source == "0.0.0.0/0") and
      (
        (.protocol == $proto_num) and (
          if $proto_str == "tcp" then
            (has("tcp-options") and (."tcp-options" | has("destination-port-range")) and ($p >= ."tcp-options"."destination-port-range".min and $p <= ."tcp-options"."destination-port-range".max))
          elif $proto_str == "udp" then
            (has("udp-options") and (."udp-options" | has("destination-port-range")) and ($p >= ."udp-options"."destination-port-range".min and $p <= ."udp-options"."destination-port-range".max))
          else false end
        )
        or
        (.protocol == "all" and (
          # Only treat as covered if no port range is specified (i.e., all ports are open)
          (
            ( ($proto_str == "tcp" and ( (has("tcp-options") | not) or ( ."tcp-options"."destination-port-range" | not ))) or
              ($proto_str == "udp" and ( (has("udp-options") | not) or ( ."udp-options"."destination-port-range" | not )))
            )
          )
        ))
      )
    )
  ')

  # --- Check if rule exists (Egress) ---
  eg_covered=$(echo "$egress_rules" | jq --argjson p "$PORT" --arg proto_str "$PROTO" --arg proto_num "$proto_num" '
    any(.[];
      (.destination == "0.0.0.0/0") and
      (
        (.protocol == $proto_num) and (
          if $proto_str == "tcp" then
            (has("tcp-options") and (."tcp-options" | has("destination-port-range")) and ($p >= ."tcp-options"."destination-port-range".min and $p <= ."tcp-options"."destination-port-range".max))
          elif $proto_str == "udp" then
            (has("udp-options") and (."udp-options" | has("destination-port-range")) and ($p >= ."udp-options"."destination-port-range".min and $p <= ."udp-options"."destination-port-range".max))
          else false end
        )
        or
        (.protocol == "all" and (
          # Only treat as covered if no port range is specified (i.e., all ports are open)
          (
            ( ($proto_str == "tcp" and ( (has("tcp-options") | not) or ( ."tcp-options"."destination-port-range" | not ))) or
              ($proto_str == "udp" and ( (has("udp-options") | not) or ( ."udp-options"."destination-port-range" | not )))
            )
          )
        ))
      )
    )
  ')

  # --- Build new rules if needed ---
  new_ingress_json='[]'
  new_egress_json='[]'
  if [[ "$ing_covered" != "true" ]]; then
    new_ing=$(jq -n --argjson n "$proto_num" --argjson p "$PORT" --arg proto "$PROTO" '
      if $proto == "tcp" then
        { protocol: $n, source: "0.0.0.0/0", isStateless: false, "tcp-options": { "destination-port-range": { min: $p, max: $p } } }
      elif $proto == "udp" then
        { protocol: $n, source: "0.0.0.0/0", isStateless: false, "udp-options": { "destination-port-range": { min: $p, max: $p } } }
      else
        { protocol: $n, source: "0.0.0.0/0", isStateless: false }
      end
    ')
    new_ingress_json=$(echo "$new_ingress_json" | jq --argjson rule "$new_ing" '. + [$rule]')
    info "Will add ingress rule for $PORT/$PROTO"
  else
    ok "Ingress rule already exists for $PORT/$PROTO"
  fi
  if [[ "$eg_covered" != "true" ]]; then
    new_eg=$(jq -n --argjson n "$proto_num" --argjson p "$PORT" --arg proto "$PROTO" '
      if $proto == "tcp" then
        { protocol: $n, destination: "0.0.0.0/0", isStateless: false, "tcp-options": { "destination-port-range": { min: $p, max: $p } } }
      elif $proto == "udp" then
        { protocol: $n, destination: "0.0.0.0/0", isStateless: false, "udp-options": { "destination-port-range": { min: $p, max: $p } } }
      else
        { protocol: $n, destination: "0.0.0.0/0", isStateless: false }
      end
    ')
    new_egress_json=$(echo "$new_egress_json" | jq --argjson rule "$new_eg" '. + [$rule]')
    info "Will add egress rule for $PORT/$PROTO"
  else
    ok "Egress rule already exists for $PORT/$PROTO"
  fi

  # --- Update OCI Security List if needed ---
  if [[ "$new_ingress_json" != '[]' || "$new_egress_json" != '[]' ]]; then
    merged_ingress_json=$(jq -s '.[0] + .[1]' <(echo "$ingress_rules") <(echo "$new_ingress_json"))
    merged_egress_json=$(jq -s '.[0] + .[1]' <(echo "$egress_rules") <(echo "$new_egress_json"))
    tmp=$(mktemp)
    echo '{}' | jq \
      --argjson in "$merged_ingress_json" \
      --argjson eg "$merged_egress_json" \
      '.["ingress-security-rules"]=$in | .["egress-security-rules"]=$eg' > "$tmp"
    run oci $OCI_FLAGS network security-list update \
      --security-list-id "$SL" --from-json "file://$tmp" --force
    rm -f "$tmp"
    ok "OCI security-list updated for $PORT/$PROTO"
  else
    ok "No OCI update needed for $PORT/$PROTO"
  fi

done
