#!/bin/bash

# 練習環境向けの自己署名証明書を作成し、Nginx用スニペットを配置する。
# 秘密鍵は get-conf の収集対象である /etc/nginx 配下には置かない。

set -euo pipefail
cd "$(dirname "$0")/.."

CERT_PATH=/etc/ssl/certs/isucon-self-signed.crt
KEY_PATH=/etc/ssl/private/isucon-self-signed.key
NGINX_SNIPPET_PATH=/etc/nginx/snippets/isucon-self-signed-ssl.conf
NGINX_SNIPPET_SOURCE=tool-config/nginx/self-signed-ssl.conf

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/create-self-signed-cert.sh [--force] <hostname-or-ip>

Examples:
  scripts/create-self-signed-cert.sh isucon.example.test
  scripts/create-self-signed-cert.sh --force 192.0.2.10

The certificate is valid for CERT_DAYS days (default: 365).
USAGE
  exit 1
}

FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
  shift
fi

CERT_HOST="${1:-}"
[ "$#" -eq 1 ] || usage

# openssl.cnfへ埋め込むため、改行や設定構文になり得る文字を拒否する。
if ! printf '%s' "$CERT_HOST" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._:-]{0,252}$'; then
  echo "invalid hostname or IP address: ${CERT_HOST}" >&2
  exit 1
fi

CERT_DAYS="${CERT_DAYS:-365}"
if ! printf '%s' "$CERT_DAYS" | grep -qE '^[0-9]+$' ||
   [ "$CERT_DAYS" -lt 1 ] || [ "$CERT_DAYS" -gt 3650 ]; then
  echo "CERT_DAYS must be an integer between 1 and 3650" >&2
  exit 1
fi

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required" >&2
  exit 1
}

if [ "$FORCE" -ne 1 ] && { sudo test -e "$CERT_PATH" || sudo test -e "$KEY_PATH"; }; then
  echo "certificate or key already exists; pass --force to replace both" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
umask 077

case "$CERT_HOST" in
  *:*) SAN_ENTRY="IP.1 = ${CERT_HOST}" ;;
  *)
    if printf '%s' "$CERT_HOST" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
      SAN_ENTRY="IP.1 = ${CERT_HOST}"
    else
      SAN_ENTRY="DNS.1 = ${CERT_HOST}"
    fi
    ;;
esac

cat >"${TMP_DIR}/openssl.cnf" <<EOF
[req]
distinguished_name = subject
x509_extensions = v3_req
prompt = no

[subject]
CN = ${CERT_HOST}

[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
${SAN_ENTRY}
DNS.2 = localhost
IP.2 = 127.0.0.1
IP.3 = ::1
EOF

openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -days "$CERT_DAYS" \
  -config "${TMP_DIR}/openssl.cnf" \
  -keyout "${TMP_DIR}/server.key" \
  -out "${TMP_DIR}/server.crt"

openssl x509 -in "${TMP_DIR}/server.crt" -noout -checkend 0 >/dev/null
openssl pkey -in "${TMP_DIR}/server.key" -check -noout >/dev/null

sudo install -d -m 0755 /etc/ssl/certs /etc/ssl/private /etc/nginx/snippets
sudo install -o root -g root -m 0600 "${TMP_DIR}/server.key" "$KEY_PATH"
sudo install -o root -g root -m 0644 "${TMP_DIR}/server.crt" "$CERT_PATH"
sudo install -o root -g root -m 0644 "$NGINX_SNIPPET_SOURCE" "$NGINX_SNIPPET_PATH"

if command -v nginx >/dev/null 2>&1; then
  sudo nginx -t
  if command -v systemctl >/dev/null 2>&1 && sudo systemctl is-active --quiet nginx; then
    sudo systemctl reload nginx
  fi
fi

echo "created: ${CERT_PATH}"
echo "private key: ${KEY_PATH}"
echo "nginx snippet: ${NGINX_SNIPPET_PATH}"
echo "add 'include snippets/isucon-self-signed-ssl.conf;' to the target server block"
echo "after editing nginx config, run: sudo nginx -t && sudo systemctl reload nginx"
