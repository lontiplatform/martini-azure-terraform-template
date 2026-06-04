#!/usr/bin/env bash
# Idempotent cert-issuance trigger for keyvault-acmebot.
#
# Called from null_resource.issue_cert.local-exec. Reads its inputs from env
# (set by the Terraform resource):
#   DOMAIN        — FQDN to issue (e.g. cooper.external.lonti.com)
#   CERT_NAME     — Key Vault certificate name (dots-as-dashes form)
#   FUNCTION_HOST — Acmebot Function App default hostname
#   FUNCTION_KEY  — Acmebot default Functions API key
#   KV_NAME       — Key Vault name
#   ACME_ENDPOINT — ACME directory URL (used to detect staging↔prod mismatch)
#
# Behaviour:
#   1. If a cert with CERT_NAME already exists in KV, has >30 days of validity,
#      AND its issuer matches the configured ACME endpoint (staging vs prod),
#      exit 0 — Acmebot's own renewal handles the rest.
#   2. Otherwise POST to /api/certificate to request issuance.
#   3. Poll KV for up to 10 min until the cert appears (or update).
#
# Re-runs on triggers (domain / endpoint / vault) change.

set -euo pipefail

: "${DOMAIN:?DOMAIN is required}"
: "${CERT_NAME:?CERT_NAME is required}"
: "${FUNCTION_HOST:?FUNCTION_HOST is required}"
: "${FUNCTION_KEY:?FUNCTION_KEY is required}"
: "${KV_NAME:?KV_NAME is required}"
: "${ACME_ENDPOINT:?ACME_ENDPOINT is required}"

case "$ACME_ENDPOINT" in
  *staging*) want_staging=1 ;;
  *)         want_staging=0 ;;
esac

log() { printf '[issue-cert] %s\n' "$*" >&2; }

need_issue=1
existing_expires=""

# Inspect the current cert (if any). `az keyvault certificate show` exits
# non-zero when the cert does not exist; suppress and treat as "need issue".
if existing_expires=$(az keyvault certificate show \
    --vault-name "$KV_NAME" \
    --name "$CERT_NAME" \
    --query "attributes.expires" \
    -o tsv 2>/dev/null); then
  if [[ -n "$existing_expires" ]]; then
    # Both BSD and GNU date accept ISO-8601 with a Z suffix; on macOS, use -j -f.
    if expires_epoch=$(date -u -d "$existing_expires" +%s 2>/dev/null) \
       || expires_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "${existing_expires%+*}" +%s 2>/dev/null) \
       || expires_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${existing_expires%+*}" +%s 2>/dev/null); then
      now_epoch=$(date -u +%s)
      days_left=$(( (expires_epoch - now_epoch) / 86400 ))
      log "existing cert '$CERT_NAME' expires $existing_expires (${days_left}d left)"
      if (( days_left > 30 )); then
        # Check issuer matches the configured ACME endpoint (staging vs prod).
        cert_pem=$(mktemp)
        if az keyvault certificate download \
            --vault-name "$KV_NAME" \
            --name "$CERT_NAME" \
            --file "$cert_pem" \
            --encoding PEM >/dev/null 2>&1; then
          issuer=$(openssl x509 -in "$cert_pem" -noout -issuer 2>/dev/null || true)
          rm -f "$cert_pem"
          case "$issuer" in
            *STAGING*|*Fake*) cert_staging=1 ;;
            *)                cert_staging=0 ;;
          esac
          if (( cert_staging == want_staging )); then
            log "skipping issuance — cert has >30 days validity and matches configured ACME endpoint"
            need_issue=0
          else
            log "cert is $([[ $cert_staging == 1 ]] && echo staging || echo production) but ACME_ENDPOINT is $([[ $want_staging == 1 ]] && echo staging || echo production) — will re-issue"
          fi
        else
          rm -f "$cert_pem"
          log "could not download cert to check issuer — will re-issue to be safe"
        fi
      fi
    else
      log "could not parse existing cert expiry '$existing_expires' — will re-issue"
    fi
  fi
else
  log "no existing cert '$CERT_NAME' in vault '$KV_NAME' — will issue"
fi

if (( need_issue == 0 )); then
  exit 0
fi

endpoint="https://${FUNCTION_HOST}/api/certificate"
# Acmebot v5 CertificatePolicyItem requires keyType (+ keySize for RSA).
# See Acmebot.App/Models/CertificatePolicyItem.cs in shibayan/keyvault-acmebot.
payload=$(printf '{"certificateName":"%s","dnsNames":["%s"],"keyType":"RSA","keySize":2048}' \
  "$CERT_NAME" "$DOMAIN")
log "POST ${endpoint} for domain ${DOMAIN}"

response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

http_code=""
for attempt in 1 2 3 4 5; do
  set +e
  http_code=$(curl -sS -o "$response_file" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "x-functions-key: ${FUNCTION_KEY}" \
    --data "$payload" \
    "$endpoint")
  curl_rc=$?
  set -e
  if (( curl_rc == 0 )) && [[ "$http_code" =~ ^2|^4 ]]; then
    break
  fi
  log "attempt $attempt: curl_rc=$curl_rc http_code=$http_code — retrying in 15s"
  sleep 15
done

log "Acmebot response (HTTP $http_code):"
cat "$response_file" >&2 || true
printf '\n' >&2

case "$http_code" in
  2*) log "issuance accepted — polling Key Vault" ;;
  409) log "Acmebot reports cert already exists/in-progress — polling Key Vault" ;;
  *)   log "Acmebot returned HTTP $http_code — aborting"; exit 1 ;;
esac

# Poll for the cert to appear (or update) in KV. Max 10 minutes.
deadline=$(( $(date -u +%s) + 600 ))
while (( $(date -u +%s) < deadline )); do
  if new_expires=$(az keyvault certificate show \
      --vault-name "$KV_NAME" \
      --name "$CERT_NAME" \
      --query "attributes.expires" \
      -o tsv 2>/dev/null); then
    if [[ -n "$new_expires" && "$new_expires" != "$existing_expires" ]]; then
      log "cert '$CERT_NAME' present in KV — expires $new_expires"
      exit 0
    fi
  fi
  sleep 15
done

log "timed out waiting for cert '$CERT_NAME' in vault '$KV_NAME'"
exit 1
