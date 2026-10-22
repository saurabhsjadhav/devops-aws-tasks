#!/usr/bin/env bash
# End-to-end deployment validation.
# Usage: scripts/validate-deployment.sh https://app.example.com
# Env:   RETRIES (default 40) and SLEEP seconds between attempts (default 15)
set -uo pipefail

BASE_URL="${1:?usage: $0 https://your-domain}"
BASE_URL="${BASE_URL%/}"
HOST="${BASE_URL#https://}"
RETRIES="${RETRIES:-40}"
SLEEP="${SLEEP:-15}"

pass=0
fail=0

# Poll a URL until it returns the expected status code (instances need a few minutes to boot).
wait_for_status() {
  local url="$1" expected="$2" code=""
  for i in $(seq 1 "$RETRIES"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
    [ "$code" = "$expected" ] && return 0
    echo "    attempt $i/$RETRIES: $url -> ${code:-no response}"
    sleep "$SLEEP"
  done
  return 1
}

http_redirects_to_https() {
  local code location
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$HOST/")
  location=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 10 "http://$HOST/")
  [ "$code" = "301" ] && [[ "$location" == https://* ]]
}

tls_certificate_valid() {
  # curl verifies the chain and hostname by default; -f fails on HTTP errors.
  curl -fsS --max-time 10 -o /dev/null "$BASE_URL/health"
}

hsts_header_present() {
  curl -fsS --max-time 10 -D - -o /dev/null "$BASE_URL/health" | grep -qi '^strict-transport-security:'
}

run() {
  local name="$1"
  shift
  echo "==> $name"
  if "$@"; then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "FAIL  $name"
    fail=$((fail + 1))
  fi
}

echo "Validating $BASE_URL"
run "ALB target health: GET /health returns 200 over HTTPS" wait_for_status "$BASE_URL/health" 200
run "HTTP :80 redirects to HTTPS (301)" http_redirects_to_https
run "TLS certificate is valid for $HOST" tls_certificate_valid
run "HSTS header present" hsts_header_present
run "RDS connectivity: GET /db-health returns 200" wait_for_status "$BASE_URL/db-health" 200
run "S3 access: GET /storage-check returns 200" wait_for_status "$BASE_URL/storage-check" 200

echo
echo "Sample response from $BASE_URL/api/status:"
curl -sS --max-time 10 "$BASE_URL/api/status" || true
echo
echo
echo "Result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
