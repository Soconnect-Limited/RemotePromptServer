#!/bin/bash
# SSL証明書更新スクリプト（手動実行用）
# 証明書の有効期限が近づいたら、このスクリプトを実行してください。

set -e

CERT_DIR="/Users/macstudio/Projects/RemotePrompt/remote-job-server/certs"
DOMAIN="remoteprompt.soconnect.co.jp"

echo "=== SSL証明書更新手順 ==="
echo ""
echo "1. 以下のコマンドを実行してください："
echo ""
echo "   sudo certbot certonly --manual --preferred-challenges dns \\"
echo "     -d ${DOMAIN} \\"
echo "     --config-dir ${CERT_DIR}/config \\"
echo "     --work-dir ${CERT_DIR}/work \\"
echo "     --logs-dir ${CERT_DIR}/logs"
echo ""
echo "2. certbotが表示するTXTレコード値をムームードメインに設定してください："
echo "   - サブドメイン: _acme-challenge.remoteprompt"
echo "   - タイプ: TXT"
echo "   - 値: <certbotが表示する値>"
echo ""
echo "3. DNS伝播を確認してからEnterキーを押してください："
echo ""
echo "   dig TXT _acme-challenge.${DOMAIN} @8.8.8.8 +short"
echo ""
echo "4. 証明書取得後、サーバーを再起動してください："
echo ""
echo "   cd /Users/macstudio/Projects/RemotePrompt/remote-job-server"
echo "   lsof -ti:443 | xargs kill -9"
echo "   source .venv/bin/activate"
echo "   uvicorn main:app --host 0.0.0.0 --port 443 \\"
echo "     --ssl-keyfile certs/config/live/${DOMAIN}/privkey.pem \\"
echo "     --ssl-certfile certs/config/live/${DOMAIN}/fullchain.pem"
echo ""
echo "=== 現在の証明書有効期限 ==="
openssl x509 -in ${CERT_DIR}/config/live/${DOMAIN}/fullchain.pem -noout -dates
