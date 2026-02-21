#!/bin/bash
set -eo pipefail

# WordPress REST API client with JWT authentication
# Usage: wjcurl.sh [--jwt-user WP_USER:WP_PASS] [--jwt-file TOKEN_FILE] [curl options] <URL>
# --jwt-user: optional "username:password" for WordPress JWT authentication.
# --jwt-file: optional path to a file for storing/reading the JWT token (default: /tmp/.jwt_wp_token_<hash>).
# All other arguments are passed directly to curl.
# If the URL contains /wp-json/, it is treated as a REST API endpoint and curl is called after authentication.
# If the URL does not contain /wp-json/, it is treated as a bare site URL: JWT authentication is performed only.
# If --jwt-user is omitted, a cached token must exist and be valid; otherwise the command fails.
#
# Tokens are cached per site in /tmp/.jwt_wp_token_<hash> (or --jwt-file if specified)

# ---- Parse all arguments: extract --jwt-user, --jwt-file, URL, Basic Auth, and curl args ----
wp_user=""
wp_pass=""
jwt_file=""
url=""
basic_auth_args=()
curl_args=()
args=("$@")

for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    --jwt-user)
      jwt_creds="${args[i + 1]}"
      wp_user="${jwt_creds%%:*}"
      wp_pass="${jwt_creds#*:}"
      ((i++))
      ;;
    --jwt-user=*)
      jwt_creds="${args[i]#--jwt-user=}"
      wp_user="${jwt_creds%%:*}"
      wp_pass="${jwt_creds#*:}"
      ;;
    --jwt-file)
      jwt_file="${args[i + 1]}"
      ((i++))
      ;;
    --jwt-file=*)
      jwt_file="${args[i]#--jwt-file=}"
      ;;
    -u|--user)
      basic_auth_args=("-u" "${args[i + 1]}")
      curl_args+=("${args[i]}" "${args[i + 1]}")
      ((i++))
      ;;
    -u*)
      basic_auth_args=("${args[i]}")
      curl_args+=("${args[i]}")
      ;;
    --user=*)
      basic_auth_args=("${args[i]}")
      curl_args+=("${args[i]}")
      ;;
    --url)
      url="${args[i + 1]}"
      curl_args+=("${args[i]}" "${args[i + 1]}")
      ((i++))
      ;;
    --url=*)
      url="${args[i]#--url=}"
      curl_args+=("${args[i]}")
      ;;
    *)
      if [[ -z "$url" && "${args[i]}" =~ ^https?:// ]]; then
        url="${args[i]}"
      fi
      curl_args+=("${args[i]}")
      ;;
  esac
done

if [[ -z "$url" ]]; then
  echo "Error: no URL specified" >&2
  exit 1
fi

# ---- Extract the site URL (everything before /wp-json/) ----
# If the URL contains /wp-json/, treat it as a REST API endpoint.
# Otherwise, treat it as a bare site URL and skip the REST API call.
if [[ "$url" == *"/wp-json/"* ]]; then
  site_url="${url%%/wp-json/*}"
  is_rest_api=true
else
  site_url="${url%/}"
  is_rest_api=false
fi

# ---- Token cache file ----
# Use --jwt-file path if specified; otherwise use a temp file scoped to site and system user
if [[ -n "$jwt_file" ]]; then
  token_cache="$jwt_file"
else
  site_hash=$(echo -n "$site_url $USER" | md5sum 2>/dev/null | cut -d' ' -f1 \
           || echo -n "$site_url $USER" | md5 2>/dev/null | cut -d' ' -f1)
  token_cache="/tmp/.jwt_wp_token_${site_hash}"
fi

# ---- Acquire JWT token ----
# Use cached token if available, otherwise fetch a new one
token=""

if [[ -f "$token_cache" ]]; then
  token=$(cat "$token_cache")

  # Validate the cached token
  validate_endpoint="${site_url}/wp-json/jwt-auth/v1/token/validate"
  validate_args=(-s -w "\n%{http_code}" -X POST -H "X-Authorization: Bearer ${token}")
  if [[ ${#basic_auth_args[@]} -gt 0 ]]; then
    validate_args+=("${basic_auth_args[@]}")
  fi
  validate_args+=("$validate_endpoint")

  v_response=$(curl "${validate_args[@]}")
  v_http_code="${v_response##*$'\n'}"
  v_body="${v_response%$'\n'*}"
  v_code=$(echo "$v_body" | jq -r '.code // empty' 2>/dev/null)

  if [[ "$v_code" == "jwt_auth_valid_token" ]]; then
    : # Token is valid, proceed
  elif [[ "$v_code" == "jwt_auth_invalid_token" ]]; then
    # Expired or invalid — re-fetch a new token
    token=""
    echo "Cached token is invalid; re-fetching a new token" >&2
  else
    echo "Error: token validation failed (HTTP $v_http_code)" >&2
    echo "$v_body" >&2
    exit 1
  fi
fi

if [[ -z "$token" ]]; then
  if [[ -z "$wp_user" ]]; then
    echo "Error: no cached token available and --jwt-user not specified" >&2
    exit 1
  fi

  jwt_endpoint="${site_url}/wp-json/jwt-auth/v1/token"

  # Build the JSON payload safely with jq
  payload=$(jq -n --arg u "$wp_user" --arg p "$wp_pass" \
    '{username: $u, password: $p}')

  # Request a JWT token (include Basic Auth credentials if provided)
  jwt_curl_args=(-s -w "\n%{http_code}")
  if [[ ${#basic_auth_args[@]} -gt 0 ]]; then
    jwt_curl_args+=("${basic_auth_args[@]}")
  fi
  jwt_curl_args+=(
    -X POST
    -H "Content-Type: application/json"
    -d "$payload"
    "$jwt_endpoint"
  )

  response=$(curl "${jwt_curl_args[@]}")
  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_code" != "200" ]]; then
    echo "Error: failed to obtain JWT token (HTTP $http_code)" >&2
    echo "$body" >&2
    exit 1
  fi

  token=$(echo "$body" | jq -r '.token // empty')
  if [[ -z "$token" ]]; then
    echo "Error: token not found in response" >&2
    echo "$body" >&2
    exit 1
  fi

  # Save token to cache file
  echo -n "$token" > "$token_cache"
  chmod 600 "$token_cache"
  echo "JWT token obtained successfully" >&2
fi

# ---- Call the REST API with the token (skipped when only a site URL was provided) ----
# X-Authorization is used instead of Authorization to avoid conflicts with Basic Auth
if [[ "$is_rest_api" == true ]]; then
  exec curl -H "X-Authorization: Bearer ${token}" "${curl_args[@]}"
fi
