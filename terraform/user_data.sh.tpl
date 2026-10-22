#!/bin/bash
# Rendered by Terraform templatefile(): only the dollar-brace placeholders are substituted.
set -euxo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1

APP_DIR=/opt/app

dnf install -y python3 python3-pip unzip

# 1. Fetch the application release from S3 (instance role, via the S3 gateway endpoint)
mkdir -p "$APP_DIR"
aws s3 cp "s3://${app_bucket}/${app_package_key}" /tmp/app.zip --region "${aws_region}"
unzip -o /tmp/app.zip -d "$APP_DIR"

# 2. RDS CA bundle, so the app can verify the database certificate (TLS is mandatory)
curl -fsSL -o "$APP_DIR/rds-ca-bundle.pem" https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# 3. Python dependencies in an isolated virtualenv
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --no-cache-dir -r "$APP_DIR/requirements.txt"

# 4. Run as an unprivileged system user
id webapp >/dev/null 2>&1 || useradd --system --no-create-home --shell /sbin/nologin webapp
chown -R webapp:webapp "$APP_DIR"

# 5. systemd service. Only the secret NAME is passed in; the credentials are read from
#    Secrets Manager at runtime and never written to disk.
cat > /etc/systemd/system/webapp.service <<'UNIT'
[Unit]
Description=DevOps task demo web application
After=network-online.target
Wants=network-online.target

[Service]
User=webapp
Group=webapp
WorkingDirectory=/opt/app
Environment=AWS_REGION=${aws_region}
Environment=AWS_DEFAULT_REGION=${aws_region}
Environment=DB_SECRET_ID=${secret_id}
Environment=APP_BUCKET=${app_bucket}
Environment=APP_VERSION=${app_version}
Environment=DB_CA_BUNDLE=/opt/app/rds-ca-bundle.pem
ExecStart=/opt/app/venv/bin/gunicorn --bind 0.0.0.0:${app_port} --workers 2 --access-logfile - app:app
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now webapp.service
