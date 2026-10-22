"""Demo web application for the DevOps practical task.

Endpoints
  /               HTML status page (records a visit in MySQL)
  /health         liveness check used by the ALB target group (no external dependencies)
  /db-health      readiness: connects to RDS MySQL using credentials from Secrets Manager
  /storage-check  readiness: writes and reads an object in the application S3 bucket
  /api/status     JSON summary of the above
"""
import json
import os
import threading
import time
import urllib.request
from datetime import datetime, timezone

import boto3
import pymysql
import pymysql.cursors
from botocore.config import Config
from flask import Flask, jsonify, render_template_string

REGION = os.environ.get("AWS_REGION", "ap-south-1")
SECRET_ID = os.environ.get("DB_SECRET_ID", "")
APP_BUCKET = os.environ.get("APP_BUCKET", "")
APP_VERSION = os.environ.get("APP_VERSION", "dev")
DB_CA_BUNDLE = os.environ.get("DB_CA_BUNDLE", "")
SECRET_TTL_SECONDS = 300

app = Flask(__name__)

_boto_cfg = Config(
    region_name=REGION,
    retries={"max_attempts": 3, "mode": "standard"},
    connect_timeout=3,
    read_timeout=5,
)
_secrets = boto3.client("secretsmanager", config=_boto_cfg)
_s3 = boto3.client("s3", config=_boto_cfg)

_secret_cache = {"value": None, "expires": 0.0}
_secret_lock = threading.Lock()
_meta_cache = {}


# --------------------------------------------------------------------------- helpers
def _imds(path):
    """Read instance metadata using IMDSv2 (token required)."""
    token_req = urllib.request.Request(
        "http://169.254.169.254/latest/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "300"},
    )
    token = urllib.request.urlopen(token_req, timeout=2).read().decode()
    req = urllib.request.Request(
        f"http://169.254.169.254/latest/meta-data/{path}",
        headers={"X-aws-ec2-metadata-token": token},
    )
    return urllib.request.urlopen(req, timeout=2).read().decode()


def instance_meta(key, path):
    if key not in _meta_cache:
        try:
            _meta_cache[key] = _imds(path)
        except Exception:  # not running on EC2 (local dev / tests)
            return "unknown"
    return _meta_cache[key]


def get_db_secret(force_refresh=False):
    with _secret_lock:
        now = time.time()
        if force_refresh or _secret_cache["value"] is None or now >= _secret_cache["expires"]:
            resp = _secrets.get_secret_value(SecretId=SECRET_ID)
            _secret_cache["value"] = json.loads(resp["SecretString"])
            _secret_cache["expires"] = now + SECRET_TTL_SECONDS
        return _secret_cache["value"]


def db_connection():
    secret = get_db_secret()
    kwargs = dict(
        host=secret["host"],
        port=int(secret["port"]),
        user=secret["username"],
        password=secret["password"],
        database=secret["dbname"],
        connect_timeout=5,
        read_timeout=5,
        write_timeout=5,
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
    )
    if DB_CA_BUNDLE and os.path.exists(DB_CA_BUNDLE):
        kwargs.update(ssl_ca=DB_CA_BUNDLE, ssl_verify_cert=True, ssl_verify_identity=True)
    try:
        return pymysql.connect(**kwargs)
    except pymysql.err.OperationalError as exc:
        if exc.args and exc.args[0] == 1045:  # access denied: password may have been rotated
            get_db_secret(force_refresh=True)
        raise


def check_db(record_visit=False):
    started = time.perf_counter()
    try:
        conn = db_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT VERSION() AS v")
                version = cur.fetchone()["v"]
                visits = None
                if record_visit:
                    cur.execute(
                        "CREATE TABLE IF NOT EXISTS visits ("
                        "id BIGINT AUTO_INCREMENT PRIMARY KEY, "
                        "instance_id VARCHAR(64) NOT NULL, "
                        "visited_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
                    )
                    cur.execute(
                        "INSERT INTO visits (instance_id) VALUES (%s)",
                        (instance_meta("instance_id", "instance-id"),),
                    )
                    cur.execute("SELECT COUNT(*) AS c FROM visits")
                    visits = cur.fetchone()["c"]
        finally:
            conn.close()
        return {
            "ok": True,
            "mysql_version": version,
            "visits": visits,
            "latency_ms": round((time.perf_counter() - started) * 1000, 1),
        }
    except Exception as exc:
        app.logger.exception("database check failed")
        return {"ok": False, "error": type(exc).__name__}


def check_storage():
    started = time.perf_counter()
    try:
        instance_id = instance_meta("instance_id", "instance-id")
        key = f"data/heartbeat/{instance_id}.json"
        payload = {"instance_id": instance_id, "written_at": datetime.now(timezone.utc).isoformat()}
        _s3.put_object(Bucket=APP_BUCKET, Key=key, Body=json.dumps(payload).encode())
        body = _s3.get_object(Bucket=APP_BUCKET, Key=key)["Body"].read()
        return {
            "ok": json.loads(body) == payload,
            "bucket": APP_BUCKET,
            "key": key,
            "latency_ms": round((time.perf_counter() - started) * 1000, 1),
        }
    except Exception as exc:
        app.logger.exception("storage check failed")
        return {"ok": False, "error": type(exc).__name__}


@app.after_request
def security_headers(resp):
    resp.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Cache-Control"] = "no-store"
    return resp


# --------------------------------------------------------------------------- routes
PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DevOps Task - AWS Deployment</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; margin: 0; padding: 2rem; }
    main { max-width: 720px; margin: 0 auto; }
    h1 { margin: 0 0 .25rem; font-size: 1.6rem; }
    p.sub { margin: 0 0 1.5rem; color: #94a3b8; }
    .card { background: #1e293b; border-radius: 10px; padding: 1rem 1.25rem; margin-bottom: 1rem; }
    .row { display: flex; justify-content: space-between; padding: .3rem 0; border-bottom: 1px solid #334155; }
    .row:last-child { border-bottom: 0; }
    .k { color: #94a3b8; }
    .ok { color: #4ade80; font-weight: 600; }
    .bad { color: #f87171; font-weight: 600; }
    code { background: #0f172a; padding: .1rem .4rem; border-radius: 4px; }
  </style>
</head>
<body>
<main>
  <h1>Deployed with Terraform on AWS</h1>
  <p class="sub">Internet &rarr; ALB (HTTPS) &rarr; Auto Scaling EC2 &rarr; RDS MySQL</p>

  <div class="card">
    <div class="row"><span class="k">Served by instance</span><code>{{ instance_id }}</code></div>
    <div class="row"><span class="k">Availability Zone</span><code>{{ az }}</code></div>
    <div class="row"><span class="k">App version</span><code>{{ version }}</code></div>
  </div>

  <div class="card">
    <div class="row"><span class="k">RDS MySQL</span>
      {% if db.ok %}<span class="ok">connected (MySQL {{ db.mysql_version }}, {{ db.latency_ms }} ms)</span>
      {% else %}<span class="bad">unreachable ({{ db.error }})</span>{% endif %}</div>
    {% if db.ok %}<div class="row"><span class="k">Total page visits stored in RDS</span><code>{{ db.visits }}</code></div>{% endif %}
    <div class="row"><span class="k">S3 application bucket</span>
      {% if storage.ok %}<span class="ok">read/write OK ({{ storage.latency_ms }} ms)</span>
      {% else %}<span class="bad">failed ({{ storage.error or 'mismatch' }})</span>{% endif %}</div>
  </div>

  <p class="sub">Refresh a few times: the instance and AZ change as the ALB balances traffic.<br>
  Probes: <code>/health</code> <code>/db-health</code> <code>/storage-check</code> <code>/api/status</code></p>
</main>
</body>
</html>
"""


@app.route("/")
def index():
    return render_template_string(
        PAGE,
        instance_id=instance_meta("instance_id", "instance-id"),
        az=instance_meta("az", "placement/availability-zone"),
        version=APP_VERSION,
        db=check_db(record_visit=True),
        storage=check_storage(),
    )


@app.route("/health")
def health():
    return jsonify(status="ok", version=APP_VERSION), 200


@app.route("/db-health")
def db_health():
    result = check_db()
    return jsonify(result), (200 if result["ok"] else 503)


@app.route("/storage-check")
def storage_check():
    result = check_storage()
    return jsonify(result), (200 if result["ok"] else 503)


@app.route("/api/status")
def api_status():
    db = check_db()
    storage = check_storage()
    body = {
        "status": "ok" if db["ok"] and storage["ok"] else "degraded",
        "version": APP_VERSION,
        "instance_id": instance_meta("instance_id", "instance-id"),
        "availability_zone": instance_meta("az", "placement/availability-zone"),
        "database": db,
        "storage": storage,
    }
    return jsonify(body), (200 if body["status"] == "ok" else 503)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("APP_PORT", "8080")))
