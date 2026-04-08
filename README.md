# check-wordpress

Nagios/NRPE-compatible WordPress monitoring via WP-CLI. Checks core, plugin and theme updates, site health, and database status — locally on the server, without storing any credentials on the monitoring system.

## What it checks

| Check | OK | WARNING | CRITICAL |
|-------|-----|---------|----------|
| Core updates | Up to date | — | Update available |
| Plugin updates | Up to date | Updates available | — |
| Theme updates | Up to date | Updates available | — |
| Site Health | No critical issues | — | Critical issues found |
| Database | Reachable | — | Connection/table error |

## Output

Standard Nagios plugin output with performance data:

```
WORDPRESS OK - Core 6.7.2 up to date, Plugins up to date, Themes up to date, Site Health: 2 recommendation(s), PHP 8.3.15 | core_updates=0 plugin_updates=0 theme_updates=0 plugins_active=5 plugins_inactive=1 health_critical=0 health_recommended=2 health_good=14 db_ok=1
```

### Performance data

| Metric | Description |
|--------|-------------|
| `core_updates` | Number of available core updates (0 or 1) |
| `plugin_updates` | Number of plugins with available updates |
| `theme_updates` | Number of themes with available updates |
| `plugins_active` | Number of active plugins |
| `plugins_inactive` | Number of inactive plugins |
| `health_critical` | Site Health tests with critical status |
| `health_recommended` | Site Health tests with recommended status |
| `health_good` | Site Health tests with good status |
| `db_ok` | Database check passed (1) or failed (0) |

## Requirements

- [WP-CLI](https://wp-cli.org/) installed on the WordPress server
- PHP (the version WordPress uses)
- `sudo` access for the monitoring user to run WP-CLI as the web server user
- Bash 4+

## Installation

### 1. Copy scripts

```bash
cp check_wordpress.sh /usr/local/lib/nagios/plugins/
cp check_wordpress_site.sh /usr/local/lib/nagios/plugins/
chmod +x /usr/local/lib/nagios/plugins/check_wordpress.sh
chmod +x /usr/local/lib/nagios/plugins/check_wordpress_site.sh
```

### 2. Create site configuration

```bash
mkdir -p /etc/check-wordpress
cp sites.conf.example /etc/check-wordpress/sites.conf
```

Edit `/etc/check-wordpress/sites.conf` and add your WordPress sites:

```
mysite;/var/www/mysite.example.com/web;www-data;php8.3
blog;/var/www/blog.example.com/htdocs;web101;php8.2
```

Format: `name;path;webuser;php-binary`

### 3. Configure sudo

Create `/etc/sudoers.d/check-wordpress`:

```
nagios ALL=(ALL) NOPASSWD: /usr/bin/php*, /usr/local/bin/wp
```

> Adjust the user (`nagios`) and PHP paths to match your setup. You can restrict the target users further, e.g., `(www-data,web101)` instead of `(ALL)`.

Validate with `visudo -c`.

### 4. Test

```bash
# Direct check (single site)
/usr/local/lib/nagios/plugins/check_wordpress.sh \
  -p /var/www/mysite.example.com/web \
  -u www-data \
  -P php8.3

# Via site config
/usr/local/lib/nagios/plugins/check_wordpress_site.sh mysite
```

## NRPE configuration

### Option A: Generic command with argument

In `/etc/nagios/nrpe.cfg`:

```
command[check_wp]=/usr/local/lib/nagios/plugins/check_wordpress_site.sh $ARG1$
```

From the monitoring server:

```
check_nrpe -H webserver -c check_wp -a mysite
```

### Option B: One command per site

```
command[check_wp_mysite]=/usr/local/lib/nagios/plugins/check_wordpress_site.sh mysite
command[check_wp_blog]=/usr/local/lib/nagios/plugins/check_wordpress_site.sh blog
```

## openITcockpit Agent

Add as a custom check in the agent configuration:

```json
{
  "customchecks": {
    "check_wp_mysite": {
      "command": "/usr/local/lib/nagios/plugins/check_wordpress_site.sh mysite",
      "interval": 300,
      "timeout": 120,
      "enabled": true
    }
  }
}
```

## How it works

The check scripts run **locally on the WordPress server**. No remote API calls, no stored credentials on the monitoring system.

1. `check_wordpress_site.sh` reads the site name, looks up path/user/PHP in the config file
2. It delegates to `check_wordpress.sh` which uses WP-CLI to query WordPress
3. WP-CLI runs as the web server user (via `sudo`) and accesses the local database using credentials from `wp-config.php`
4. Site Health tests are executed via `wp eval` using WordPress's built-in `WP_Site_Health` class — no extra WP-CLI packages required
5. Results are formatted as standard Nagios plugin output

## Direct usage (without config file)

You can also use `check_wordpress.sh` directly without the config wrapper:

```bash
check_wordpress.sh -p /var/www/mysite/web -u www-data -P php8.3

# Options:
#   -p  Path to WordPress installation (required)
#   -u  Run WP-CLI as this user via sudo
#   -P  PHP binary (default: php)
#   -w  WP-CLI path (default: /usr/local/bin/wp)
```

## Authors

- [David Malinowski](https://github.com/itsdave-de) / [itsdave.de](https://itsdave.de)

## License

GPLv3 — see [LICENSE](LICENSE) for details.
