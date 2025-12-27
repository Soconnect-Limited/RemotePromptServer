#!/bin/bash
# Let's Encrypt証明書自動更新スクリプト
# Cloudflare DNS-01チャレンジを使用

set -e

CERT_DIR="/Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/remoteprompt.net"
CLOUDFLARE_CREDENTIALS="/Users/macstudio/Projects/RemotePrompt/secrets/cloudflare.ini"
LOG_FILE="/Users/macstudio/Projects/RemotePrompt/remote-job-server/logs/certbot-renew.log"

echo "$(date): Starting certificate renewal check" >> "$LOG_FILE"

# 証明書更新（有効期限30日未満なら更新）
certbot renew \
  --dns-cloudflare \
  --dns-cloudflare-credentials "$CLOUDFLARE_CREDENTIALS" \
  --config-dir "$CERT_DIR/config" \
  --work-dir "$CERT_DIR/work" \
  --logs-dir "$CERT_DIR/logs" \
  --quiet \
  --deploy-hook "echo '$(date): Certificate renewed, server restart required' >> $LOG_FILE" \
  2>&1 | tee -a "$LOG_FILE"

echo "$(date): Certificate renewal check completed" >> "$LOG_FILE"
