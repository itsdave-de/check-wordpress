#!/bin/bash
# check_wordpress.sh — Nagios/NRPE-compatible WordPress monitoring via WP-CLI
# Copyright (C) 2026 David Malinowski / itsdave.de
# https://github.com/itsdave-de/check-wordpress
# License: GPLv3 (see LICENSE file)
#
# Usage: check_wordpress.sh -p /path/to/wordpress [-u webuser] [-P /usr/bin/php] [-w /usr/local/bin/wp]
#
# Exit Codes: 0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN
# WARNING:  Plugin or theme updates available
# CRITICAL: Core update available, site health critical issues, or database error

VERSION="1.0.0"

# Defaults
WP_PATH=""
WP_USER=""
PHP_BIN="php"
WP_CLI="/usr/local/bin/wp"

usage() {
    echo "Usage: $0 -p <wordpress-path> [-u <webuser>] [-P <php-binary>] [-w <wp-cli-path>]"
    echo ""
    echo "  -p  Path to WordPress installation (required)"
    echo "  -u  Run WP-CLI as this user via sudo (optional, recommended)"
    echo "  -P  PHP binary path (default: php)"
    echo "  -w  WP-CLI path (default: /usr/local/bin/wp)"
    echo "  -h  Show this help"
    exit 3
}

while getopts "p:u:P:w:h" opt; do
    case $opt in
        p) WP_PATH="$OPTARG" ;;
        u) WP_USER="$OPTARG" ;;
        P) PHP_BIN="$OPTARG" ;;
        w) WP_CLI="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

[ -z "$WP_PATH" ] && usage

# Verify WordPress installation exists
if [ ! -f "$WP_PATH/wp-config.php" ]; then
    echo "UNKNOWN - wp-config.php not found in $WP_PATH"
    exit 3
fi

# Build WP-CLI command prefix
if [ -n "$WP_USER" ]; then
    WP_CMD="sudo -u $WP_USER $PHP_BIN $WP_CLI --path=$WP_PATH --no-color"
else
    WP_CMD="$PHP_BIN $WP_CLI --path=$WP_PATH --no-color"
fi

# Collect results
EXIT_CODE=0
MESSAGES=()
PERFDATA=()

# --- Core Version & Updates ---
CORE_VERSION=$($WP_CMD core version 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "UNKNOWN - WP-CLI failed to read WordPress at $WP_PATH"
    exit 3
fi

CORE_UPDATES=$($WP_CMD core check-update --format=count 2>/dev/null)
if [ -z "$CORE_UPDATES" ] || [ "$CORE_UPDATES" = "0" ]; then
    CORE_UPDATES=0
else
    if ! [[ "$CORE_UPDATES" =~ ^[0-9]+$ ]]; then
        CORE_UPDATES=$($WP_CMD core check-update --format=json 2>/dev/null | grep -c '"version"')
    fi
fi

if [ "$CORE_UPDATES" -gt 0 ] 2>/dev/null; then
    MESSAGES+=("Core update available (current: $CORE_VERSION)")
    [ $EXIT_CODE -lt 2 ] && EXIT_CODE=2
else
    MESSAGES+=("Core $CORE_VERSION up to date")
fi
PERFDATA+=("core_updates=$CORE_UPDATES")

# --- Plugin Updates ---
PLUGIN_UPDATE_COUNT=$($WP_CMD plugin list --update=available --format=count 2>/dev/null)
[ -z "$PLUGIN_UPDATE_COUNT" ] && PLUGIN_UPDATE_COUNT=0

if [ "$PLUGIN_UPDATE_COUNT" -gt 0 ] 2>/dev/null; then
    PLUGIN_NAMES=$($WP_CMD plugin list --update=available --field=name 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
    MESSAGES+=("$PLUGIN_UPDATE_COUNT plugin update(s): $PLUGIN_NAMES")
    [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
else
    MESSAGES+=("Plugins up to date")
fi
PERFDATA+=("plugin_updates=$PLUGIN_UPDATE_COUNT")

# --- Theme Updates ---
THEME_UPDATE_COUNT=$($WP_CMD theme list --update=available --format=count 2>/dev/null)
[ -z "$THEME_UPDATE_COUNT" ] && THEME_UPDATE_COUNT=0

if [ "$THEME_UPDATE_COUNT" -gt 0 ] 2>/dev/null; then
    THEME_NAMES=$($WP_CMD theme list --update=available --field=name 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
    MESSAGES+=("$THEME_UPDATE_COUNT theme update(s): $THEME_NAMES")
    [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
else
    MESSAGES+=("Themes up to date")
fi
PERFDATA+=("theme_updates=$THEME_UPDATE_COUNT")

# --- Plugin Counts ---
PLUGIN_ACTIVE=$($WP_CMD plugin list --status=active --format=count 2>/dev/null)
PLUGIN_INACTIVE=$($WP_CMD plugin list --status=inactive --format=count 2>/dev/null)
PERFDATA+=("plugins_active=${PLUGIN_ACTIVE:-0}" "plugins_inactive=${PLUGIN_INACTIVE:-0}")

# --- Site Health (via wp eval, no extra WP-CLI package needed) ---
HEALTH_OUTPUT=$($WP_CMD eval '
require_once ABSPATH . "wp-admin/includes/class-wp-site-health.php";
$health = WP_Site_Health::get_instance();
$tests = WP_Site_Health::get_tests();
$counts = ["good" => 0, "recommended" => 0, "critical" => 0];
$critical_labels = [];
foreach ($tests["direct"] as $key => $test) {
    $cb = $test["test"];
    if (is_string($cb) && method_exists($health, "get_test_" . $cb)) {
        $result = call_user_func([$health, "get_test_" . $cb]);
    } elseif (is_callable($cb)) {
        $result = call_user_func($cb);
    } else {
        continue;
    }
    $status = $result["status"] ?? "unknown";
    if (isset($counts[$status])) {
        $counts[$status]++;
        if ($status === "critical") {
            $critical_labels[] = $result["label"] ?? $key;
        }
    }
}
echo json_encode(["counts" => $counts, "critical_labels" => $critical_labels]);
' 2>/dev/null)

if [ -n "$HEALTH_OUTPUT" ] && echo "$HEALTH_OUTPUT" | grep -q '"counts"'; then
    HEALTH_CRITICAL=$(echo "$HEALTH_OUTPUT" | grep -o '"critical":[0-9]*' | grep -o '[0-9]*')
    HEALTH_RECOMMENDED=$(echo "$HEALTH_OUTPUT" | grep -o '"recommended":[0-9]*' | grep -o '[0-9]*')
    HEALTH_GOOD=$(echo "$HEALTH_OUTPUT" | grep -o '"good":[0-9]*' | grep -o '[0-9]*')

    PERFDATA+=("health_critical=${HEALTH_CRITICAL:-0}" "health_recommended=${HEALTH_RECOMMENDED:-0}" "health_good=${HEALTH_GOOD:-0}")

    if [ "${HEALTH_CRITICAL:-0}" -gt 0 ] 2>/dev/null; then
        CRIT_LABELS=$(echo "$HEALTH_OUTPUT" | grep -o '"critical_labels":\[.*\]' | sed 's/"critical_labels":\[//;s/\]//;s/"//g')
        MESSAGES+=("Site Health: $HEALTH_CRITICAL critical ($CRIT_LABELS)")
        [ $EXIT_CODE -lt 2 ] && EXIT_CODE=2
    elif [ "${HEALTH_RECOMMENDED:-0}" -gt 0 ] 2>/dev/null; then
        MESSAGES+=("Site Health: $HEALTH_RECOMMENDED recommendation(s)")
    else
        MESSAGES+=("Site Health: OK")
    fi
else
    MESSAGES+=("Site Health: unavailable")
    PERFDATA+=("health_critical=0" "health_recommended=0" "health_good=0")
fi

# --- PHP Version ---
PHP_VERSION=$($WP_CMD eval 'echo PHP_VERSION;' 2>/dev/null)
if [ -n "$PHP_VERSION" ]; then
    MESSAGES+=("PHP $PHP_VERSION")
fi

# --- Database Check ---
$WP_CMD db check --no-defaults >/dev/null 2>&1
if [ $? -eq 0 ]; then
    PERFDATA+=("db_ok=1")
else
    MESSAGES+=("Database error")
    PERFDATA+=("db_ok=0")
    [ $EXIT_CODE -lt 2 ] && EXIT_CODE=2
fi

# --- Build Output ---
case $EXIT_CODE in
    0) STATUS="OK" ;;
    1) STATUS="WARNING" ;;
    2) STATUS="CRITICAL" ;;
    *) STATUS="UNKNOWN" ;;
esac

MSG_STR=$(IFS=', '; echo "${MESSAGES[*]}")
PERF_STR=$(IFS=' '; echo "${PERFDATA[*]}")

echo "WORDPRESS $STATUS - $MSG_STR | $PERF_STR"
exit $EXIT_CODE
