#!/usr/bin/env sh
set -eu

namespace="${1:-${CENTRAL_NAMESPACE:-}}"
publishing_type="${CENTRAL_PUBLISHING_TYPE:-user_managed}"
base_url="${CENTRAL_OSSRH_STAGING_API_URL:-https://ossrh-staging-api.central.sonatype.com}"

if [ -z "$namespace" ]; then
  printf 'usage: %s <central-namespace>\n' "$0" >&2
  printf 'or set CENTRAL_NAMESPACE\n' >&2
  exit 2
fi

if [ -n "${CENTRAL_BEARER_TOKEN:-}" ]; then
  bearer="$CENTRAL_BEARER_TOKEN"
else
  token_user="${CENTRAL_TOKEN_USERNAME:-${SONATYPE_USERNAME:-}}"
  token_password="${CENTRAL_TOKEN_PASSWORD:-${SONATYPE_PASSWORD:-}}"
  if [ -z "$token_user" ] || [ -z "$token_password" ]; then
    printf 'set CENTRAL_BEARER_TOKEN, or CENTRAL_TOKEN_USERNAME/CENTRAL_TOKEN_PASSWORD\n' >&2
    exit 2
  fi
  bearer="$(printf '%s:%s' "$token_user" "$token_password" | base64 | tr -d '\n')"
fi

case "$publishing_type" in
  user_managed|automatic|portal_api)
    ;;
  *)
    printf 'CENTRAL_PUBLISHING_TYPE must be user_managed, automatic, or portal_api\n' >&2
    exit 2
    ;;
esac

curl -fsS \
  -X POST \
  -H "Authorization: Bearer $bearer" \
  "$base_url/manual/upload/defaultRepository/$namespace?publishing_type=$publishing_type"
