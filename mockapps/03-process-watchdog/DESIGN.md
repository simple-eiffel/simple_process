# ProcessWatchdog - Technical Design

## Architecture

### Component Overview

```
+----------------------------------------------------------+
|                    ProcessWatchdog                        |
+----------------------------------------------------------+
|  CLI Interface Layer                                      |
|    - Argument parsing (simple_cli)                        |
|    - Command routing (start/stop/status/add/remove)       |
|    - Output formatting (text/json/metrics)                |
+----------------------------------------------------------+
|  Supervisor Engine Layer                                  |
|    - Process monitoring loop                              |
|    - Health check orchestration                           |
|    - Restart decision engine                              |
|    - Resource limit enforcement                           |
+----------------------------------------------------------+
|  Process Management Layer                                 |
|    - Process spawning (simple_async_process)              |
|    - Process tracking (PID, uptime)                       |
|    - Process termination                                  |
|    - Output capture (stdout/stderr)                       |
+----------------------------------------------------------+
|  Health Check Layer                                       |
|    - HTTP health checks (simple_http)                     |
|    - Command-based checks (simple_process)                |
|    - TCP port checks                                      |
|    - File existence checks                                |
+----------------------------------------------------------+
|  Alerting Layer                                           |
|    - Email alerts (simple_smtp)                           |
|    - Webhook alerts (simple_http)                         |
|    - Slack/Teams integration                              |
|    - Flapping detection                                   |
+----------------------------------------------------------+
|  Persistence & Metrics Layer                              |
|    - Event logging (simple_logger)                        |
|    - Event history (simple_sql)                           |
|    - Prometheus metrics export                            |
+----------------------------------------------------------+
```

### Class Design

| Class | Responsibility | Key Features |
|-------|----------------|--------------|
| WATCHDOG_CLI | Command-line interface | parse_args, route_command, format_output |
| WATCHDOG_ENGINE | Main supervision loop | start, stop, check_all, restart_policy |
| WATCHDOG_PROCESS | Process definition | name, command, health_check, restart_policy |
| WATCHDOG_MONITOR | Individual process monitor | spawn, monitor, check_health, restart |
| WATCHDOG_HEALTH_CHECKER | Health check execution | http_check, command_check, port_check |
| WATCHDOG_RESTART_POLICY | Restart decision logic | should_restart, backoff, max_retries |
| WATCHDOG_ALERTER | Alert dispatch | alert_crash, alert_restart, alert_resource |
| WATCHDOG_CONFIG | Configuration management | load, validate, reload |
| WATCHDOG_METRICS | Prometheus metrics | export_metrics, register_metric |
| WATCHDOG_HISTORY | Event history | record_event, query_events |
| WATCHDOG_SERVICE | Windows service wrapper | install, uninstall, start, stop |

### Command Structure

```bash
process-watchdog <command> [options] [arguments]

Commands:
  daemon                Run supervisor in foreground
  start <name>          Start a specific process
  stop <name>           Stop a specific process
  restart <name>        Restart a specific process
  status [name]         Show status of all or specific process
  add <config.json>     Add process from configuration file
  remove <name>         Remove process from supervision
  reload                Reload configuration without restart
  logs <name> [--tail]  Show process logs
  metrics               Export Prometheus metrics
  service install       Install as Windows service
  service uninstall     Uninstall Windows service
  service start         Start the Windows service
  service stop          Stop the Windows service

Global Options:
  --config FILE         Configuration file (default: watchdog.json)
  --output FORMAT       Output format (text|json|prometheus)
  --verbose             Verbose output
  --quiet               Suppress non-error output
  --help                Show help
  --version             Show version

Examples:
  process-watchdog daemon --config /etc/watchdog/config.json
  process-watchdog status
  process-watchdog status myapp
  process-watchdog restart myapp
  process-watchdog logs myapp --tail 100
  process-watchdog metrics
  process-watchdog service install --start
```

### Data Flow

```
Configuration (JSON)
        |
        v
Config Loader --> Validation --> Process Registry
                                       |
                    +------------------+
                    |
                    v
            +---------------+
            | Monitor Loop  |<----+
            +-------+-------+     |
                    |             |
         +----------+----------+  |
         |          |          |  |
         v          v          v  |
    Check PID   Health     Resource |
    Running?    Check?     Limits?  |
         |          |          |  |
         +----------+----------+  |
                    |             |
         +----------+----------+  |
         |                     |  |
         v                     v  |
      HEALTHY              UNHEALTHY
         |                     |
         |              +------+------+
         |              |             |
         |              v             v
         |         Should        Alert +
         |         Restart?      Log
         |              |             |
         |              v             |
         |         Restart            |
         |         Process            |
         |              |             |
         +------+-------+-------------+
                |
                v
          Sleep Interval
                |
                +-----------------------> Loop
```

### Process Configuration Schema

```json
{
  "processes": [
    {
      "name": "myapp",
      "command": "C:\\Apps\\MyApp\\myapp.exe",
      "arguments": "--port 8080 --log-level info",
      "working_directory": "C:\\Apps\\MyApp",
      "environment": {
        "NODE_ENV": "production",
        "LOG_PATH": "C:\\Logs\\MyApp"
      },
      "user": "SYSTEM",
      "priority": "normal",

      "health_check": {
        "type": "http",
        "url": "http://localhost:8080/health",
        "expected_status": 200,
        "expected_body": "ok",
        "interval_seconds": 30,
        "timeout_seconds": 5,
        "retries": 3
      },

      "restart_policy": {
        "enabled": true,
        "max_retries": 5,
        "retry_window_seconds": 300,
        "backoff_seconds": [5, 10, 30, 60, 120],
        "on_failure": "alert"
      },

      "resource_limits": {
        "max_memory_mb": 512,
        "max_cpu_seconds": 3600,
        "action": "restart"
      },

      "alerts": {
        "on_crash": true,
        "on_restart": true,
        "on_resource_limit": true,
        "on_health_fail": true,
        "channels": ["email", "slack"]
      },

      "logging": {
        "stdout_file": "C:\\Logs\\MyApp\\stdout.log",
        "stderr_file": "C:\\Logs\\MyApp\\stderr.log",
        "rotate_size_mb": 10,
        "rotate_count": 5
      },

      "enabled": true,
      "auto_start": true,
      "depends_on": ["database", "redis"]
    }
  ]
}
```

### Global Configuration Schema

```json
{
  "watchdog": {
    "check_interval_seconds": 5,
    "log_directory": "C:\\ProgramData\\Watchdog\\logs",
    "log_level": "info",
    "history_database": "C:\\ProgramData\\Watchdog\\history.db",
    "history_retention_days": 30,

    "metrics": {
      "enabled": true,
      "port": 9100,
      "path": "/metrics"
    },

    "alerts": {
      "email": {
        "enabled": true,
        "smtp_host": "smtp.example.com",
        "smtp_port": 587,
        "smtp_user": "alerts@example.com",
        "smtp_password_env": "SMTP_PASSWORD",
        "from": "ProcessWatchdog <alerts@example.com>",
        "to": ["ops@example.com"]
      },
      "slack": {
        "enabled": true,
        "webhook_url_env": "SLACK_WEBHOOK_URL",
        "channel": "#alerts"
      },
      "webhook": {
        "enabled": false,
        "url": "https://hooks.example.com/alerts",
        "headers": {
          "Authorization": "Bearer ${WEBHOOK_TOKEN}"
        }
      }
    },

    "flapping_detection": {
      "enabled": true,
      "window_seconds": 300,
      "max_restarts": 5,
      "cooldown_seconds": 600
    }
  }
}
```

### Error Handling

| Error Type | Handling | User Message |
|------------|----------|--------------|
| Process not found | Log warning | "Process 'name' not found in configuration" |
| Failed to start | Alert, retry with backoff | "Failed to start 'name': access denied" |
| Health check failed | Retry, then restart | "Health check failed for 'name' (3/3). Restarting..." |
| Resource limit exceeded | Kill and restart | "Process 'name' exceeded memory limit (512MB). Restarting..." |
| Flapping detected | Disable auto-restart | "Process 'name' is flapping (5 restarts in 300s). Disabling auto-restart." |
| Alert delivery failed | Log error, continue | "Failed to send Slack alert: connection timeout" |
| Config reload error | Keep old config | "Configuration error at line 15. Keeping current config." |

### State Machine: Process Lifecycle

```
                   +----------+
                   | DISABLED |
                   +----+-----+
                        |
                        | (enable)
                        v
                   +----------+
                   | STOPPED  |
                   +----+-----+
                        |
                        | (start)
                        v
                   +---------+
           +------>| STARTING|
           |       +----+----+
           |            |
           |            v
           |       +---------+
           |       | RUNNING |<------+
           |       +----+----+       |
           |            |            |
           |     +------+------+     |
           |     |             |     |
           |     v             v     |
           | +--------+   +---------+|
           | | HEALTHY|   |UNHEALTHY||
           | +--------+   +----+----+|
           |                   |     |
           |                   v     |
           |            +----------+ |
           |            |RESTARTING|-+
           |            +----+-----+
           |                 |
           |          +------+------+
           |          |             |
           |          v             v
           |     +---------+   +---------+
           |     | STOPPED |   | FAILED  |
           |     +---------+   +----+----+
           |                        |
           +------------------------+
                    (manual restart)
```

### Prometheus Metrics

```
# HELP watchdog_process_up Process is running (1=up, 0=down)
# TYPE watchdog_process_up gauge
watchdog_process_up{name="myapp"} 1

# HELP watchdog_process_uptime_seconds Process uptime in seconds
# TYPE watchdog_process_uptime_seconds gauge
watchdog_process_uptime_seconds{name="myapp"} 3600

# HELP watchdog_process_restarts_total Total number of restarts
# TYPE watchdog_process_restarts_total counter
watchdog_process_restarts_total{name="myapp"} 3

# HELP watchdog_process_memory_bytes Current memory usage in bytes
# TYPE watchdog_process_memory_bytes gauge
watchdog_process_memory_bytes{name="myapp"} 134217728

# HELP watchdog_health_check_duration_seconds Health check duration
# TYPE watchdog_health_check_duration_seconds histogram
watchdog_health_check_duration_seconds_bucket{name="myapp",le="0.1"} 95

# HELP watchdog_health_check_status Health check status (1=pass, 0=fail)
# TYPE watchdog_health_check_status gauge
watchdog_health_check_status{name="myapp"} 1
```

## GUI/TUI Future Path

**CLI foundation enables:**
- All process management via CLI for scripting and automation
- JSON output mode for building dashboards
- Prometheus metrics for Grafana integration

**What would change for TUI:**
- Add simple_tui for real-time process dashboard
- Live log streaming in split pane
- Interactive start/stop/restart
- Alert acknowledgment

**What would change for Web GUI:**
- Add simple_http for REST API server
- Process status and control endpoints
- WebSocket for real-time updates
- Configuration editor

**Shared components between CLI/GUI:**
- WATCHDOG_ENGINE (core supervision logic)
- WATCHDOG_MONITOR (process monitoring)
- WATCHDOG_HEALTH_CHECKER (health checks)
- WATCHDOG_ALERTER (alert dispatch)
- All business logic in shared library
