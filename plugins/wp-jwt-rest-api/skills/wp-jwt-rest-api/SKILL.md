---
name: wp-jwt-rest-api
description: A CLI bash script for calling the WordPress REST API with JWT (JSON Web Token) authentication. Automatically authenticates via JWT before running curl. Works behind HTTP Basic Auth as well.
allowed-tools: Read, Bash, Glob, Grep
---

# Calling the WordPress REST API with JWT authentication

## Script
WordPress REST API client with JWT authentication: `scripts/wjcurl.sh`

## Usage
```bash
~/.claude/skills/wp-jwt-rest-api/scripts/wjcurl.sh [--jwt-user WP_USER:WP_PASS] [--jwt-file TOKEN_FILE] [curl options] <URL>
```
- `--jwt-user "username:password"` is optional; if omitted, a valid cached token must exist
- `--jwt-file TOKEN_FILE` is optional; specifies a file path for storing/reading the JWT token (default: `/tmp/.jwt_wp_token_<hash>`)
- If the URL contains `/wp-json/`, it is treated as a REST API endpoint and curl is called after authentication
- If the URL does not contain `/wp-json/`, it is treated as a bare site URL: JWT authentication is performed only, no REST API call is made
- All other arguments are curl-compatible
- stdout: curl response body (empty when only site URL is provided)
- stderr: JWT authentication status, curl errors

## Examples

### With JWT authentication
Fetch a list of draft posts
```bash
~/.claude/skills/wp-jwt-rest-api/scripts/wjcurl.sh --jwt-user "$WP_USER_NAME:$WP_USER_PASS" -s "https://example.com/wp-json/wp/v2/posts?status=draft&per_page=10" | jq '[.[] | {id, status, title: .title.rendered}]'
```

### Using cached token (no credentials needed)
```bash
~/.claude/skills/wp-jwt-rest-api/scripts/wjcurl.sh -s "https://example.com/wp-json/wp/v2/posts?status=draft&per_page=10" | jq '[.[] | {id, status, title: .title.rendered}]'
```

### With JWT authentication behind Basic Auth
Create a new post
```bash
~/.claude/skills/wp-jwt-rest-api/scripts/wjcurl.sh --jwt-user "$WP_USER_NAME:$WP_USER_PASS" -s -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASS" -X POST -H "Content-Type: application/json" -d '{"title":"Test post","content":"<p>This is a test post via REST API.</p>","status":"draft"}' "https://example.com/wp-json/wp/v2/posts"
```

### JWT authentication only (no REST API call), saving token to a file
Authenticate and save the token to a specified file without making a REST API call.
```bash
~/.claude/skills/wp-jwt-rest-api/scripts/wjcurl.sh --jwt-user "$WP_USER_NAME:$WP_USER_PASS" --jwt-file /tmp/my-token "https://example.com"
```

### Using a token file to fetch WordPress settings
```bash
~/.claude/skills/wp-jwt-rest-api/scripts/wjcurl.sh --jwt-file /tmp/my-token -s "https://example.com/wp-json/wp/v2/settings" | jq .
```

## Installation and Setup
Before running the script, install the JWT Authentication for WP REST API plugin and configure `.htaccess` and `wp-config.php`.
See: `references/setup.md`
