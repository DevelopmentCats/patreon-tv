#!/usr/bin/env bash
# Start the pairing portal for local dev on your LAN (iPhone / Apple TV can reach it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TVOS_CONFIG="$ROOT/../apps/tvos/PatreonTV/Sources/Auth/PairingConfig.swift"
PORT="${PAIRING_PORT:-8788}"

pick_ip() {
  for iface in en0 en1 bridge0; do
    local ip
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return 0
    fi
  done
  echo "Could not detect a LAN IP (en0/en1). Set PAIRING_LAN_IP manually." >&2
  exit 1
}

IP="${PAIRING_LAN_IP:-$(pick_ip)}"
ORIGIN="http://${IP}:${PORT}"

echo "Pairing LAN origin: ${ORIGIN}"
echo "QR / link URLs will use this address for devices on your Wi‑Fi."

cat > "$ROOT/.dev.vars" <<EOF
PAIRING_PUBLIC_ORIGIN=${ORIGIN}
EOF

HARNESS_ENV="$ROOT/../harness/.env"
if [[ -f "$HARNESS_ENV" ]]; then
  echo "Loading Patreon OAuth credentials from harness/.env"
  # shellcheck disable=SC1090
  set -a
  source "$HARNESS_ENV"
  set +a
  if [[ -n "${PATREON_CLIENT_ID:-}" && -n "${PATREON_CLIENT_SECRET:-}" ]]; then
    cat >> "$ROOT/.dev.vars" <<EOF
PATREON_CLIENT_ID=${PATREON_CLIENT_ID}
PATREON_CLIENT_SECRET=${PATREON_CLIENT_SECRET}
PATREON_REDIRECT_URI=${ORIGIN}/api/pairing/oauth/callback
EOF
    echo "OAuth enabled — register this redirect URI in the Patreon developer portal:"
    echo "  ${ORIGIN}/api/pairing/oauth/callback"
  fi
else
  echo "No harness/.env — OAuth disabled; use session_id paste on the link page."
fi

if [[ -f "$TVOS_CONFIG" ]]; then
  perl -0pi -e "s#URL\\(string: \"http://[^\"]+:${PORT}\"\\)!#URL(string: \"${ORIGIN}\")!#g" "$TVOS_CONFIG"
  echo "Updated ${TVOS_CONFIG}"
fi

cd "$ROOT"
npm run build
exec npx wrangler pages dev dist --port "$PORT" --ip 0.0.0.0
