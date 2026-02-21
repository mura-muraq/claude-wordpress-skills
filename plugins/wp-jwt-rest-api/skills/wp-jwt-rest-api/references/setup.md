# Installation and Setup

## Install jq
If jq is not already installed:
```bash
brew install jq
```

## Install the Plugin
Install "JWT Authentication for WP REST API" on your WordPress site.

Plugin page and documentation:
https://wordpress.org/plugins/jwt-authentication-for-wp-rest-api/

## Edit .htaccess
Add the following block to `.htaccess` — place it before the WordPress directives, but after any access-restriction directives such as Basic Auth:

```
# JWT Authentication for WP REST API
RewriteEngine on
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteCond %{HTTP:X-Authorization} ^(.+)
RewriteRule .* - [E=HTTP_AUTHORIZATION:%1]
```

> Note: `X-Authorization` is used instead of `Authorization` to avoid conflicts with HTTP Basic Auth.

If the WordPress directives already contain an `HTTP_AUTHORIZATION` rule, comment it out:

```
#RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
```

## Edit wp-config.php
Add the following block to `wp-config.php` immediately after the authentication unique keys section, and replace `'your-top-secret-key'` with a long, random secret key:

```
//  JWT Authentication for WP REST API
define('JWT_AUTH_SECRET_KEY', 'your-top-secret-key');
```

## Example Prompts
- Fetch the WordPress settings via JWT REST API
- Fetch the list of installed plugins via JWT REST API
- Create a draft test post via JWT REST API
- Delete the latest draft post via JWT REST API
