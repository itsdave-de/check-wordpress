#!/bin/bash
# check_wordpress_site.sh — Wrapper that reads site config and delegates to check_wordpress.sh
# Copyright (C) 2026 David Malinowski / itsdave.de
# https://github.com/itsdave-de/check-wordpress
# License: GPLv3 (see LICENSE file)
#
# Usage: check_wordpress_site.sh <sitename>
#
# Reads site parameters from /etc/check-wordpress/sites.conf
# and calls check_wordpress.sh with the appropriate arguments.
#
# Exit Codes: 0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN

CONFIG="/etc/check-wordpress/sites.conf"
CHECK="/usr/local/lib/nagios/plugins/check_wordpress.sh"
WP_CLI="/usr/local/bin/wp"

SITE_NAME="$1"

if [ -z "$SITE_NAME" ]; then
    echo "UNKNOWN - Usage: $0 <sitename>"
    exit 3
fi

if [ ! -f "$CONFIG" ]; then
    echo "UNKNOWN - Config file not found: $CONFIG"
    exit 3
fi

if [ ! -x "$CHECK" ]; then
    echo "UNKNOWN - Check script not found: $CHECK"
    exit 3
fi

# Find site in config (ignore comments and empty lines)
SITE_LINE=$(grep -v '^\s*#' "$CONFIG" | grep -v '^\s*$' | grep "^${SITE_NAME};")

if [ -z "$SITE_LINE" ]; then
    echo "UNKNOWN - Site '$SITE_NAME' not found in $CONFIG"
    exit 3
fi

# Parse: name;path;webuser;php-binary
IFS=';' read -r NAME WP_PATH WP_USER PHP_BIN <<< "$SITE_LINE"

if [ -z "$WP_PATH" ] || [ -z "$WP_USER" ] || [ -z "$PHP_BIN" ]; then
    echo "UNKNOWN - Incomplete config for site '$SITE_NAME': path=$WP_PATH user=$WP_USER php=$PHP_BIN"
    exit 3
fi

# Delegate to main check script
exec "$CHECK" -p "$WP_PATH" -u "$WP_USER" -P "$PHP_BIN" -w "$WP_CLI"
