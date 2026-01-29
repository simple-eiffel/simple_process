# RunScheduler - Technical Design

## Architecture

### Component Overview

```
+----------------------------------------------------------+
|                     RunScheduler                          |
+----------------------------------------------------------+
|  CLI Interface Layer                                      |
|    - Argument parsing (simple_cli)                        |
|    - Command routing (add/remove/list/run/status/daemon)  |
|    - Output formatting (text/json)                        |
+----------------------------------------------------------+
|  Scheduler Engine Layer                                   |
|    - Cron expression parser                               |
|    - Job queue management                                 |
|    - Execution timing                                     |
|    - Job dependency resolution                            |
+----------------------------------------------------------+
|  Job Execution Layer                                      |
|    - Process spawning (simple_process)                    |
|    - Output capture                                       |
|    - Exit code handling                                   |
|    - Timeout management (simple_async_process)            |
+----------------------------------------------------------+
|  Persistence Layer                                        |
|    - Job configuration (simple_json)                      |
|    - Execution history (simple_sql)                       |
|    - Log files (simple_logger)                            |
+----------------------------------------------------------+
|  Notification Layer                                       |
|    - Email alerts (simple_smtp)                           |
|    - Webhook callbacks (simple_http)                      |
+----------------------------------------------------------+
```

### Class Design

| Class | Responsibility | Key Features |
|-------|----------------|--------------|
| RUN_SCHEDULER_CLI | Command-line interface | parse_args, route_command, format_output |
| RUN_SCHEDULER_ENGINE | Core scheduler loop | start, stop, next_job, execute_job |
| RUN_SCHEDULER_JOB | Job definition | name, command, schedule, timeout, depends_on |
| RUN_SCHEDULER_CRON | Cron expression parsing | parse, next_run_time, matches_time |
| RUN_SCHEDULER_EXECUTOR | Job execution | run_job, capture_output, handle_timeout |
| RUN_SCHEDULER_CONFIG | Configuration management | load_jobs, save_job, validate_config |
| RUN_SCHEDULER_HISTORY | Execution history | record_run, get_history, prune_old |
| RUN_SCHEDULER_NOTIFIER | Notification dispatch | notify_success, notify_failure, send_webhook |
| RUN_SCHEDULER_SERVICE | Windows service wrapper | install, uninstall, start, stop |

### Command Structure

```bash
run-scheduler <command> [options] [arguments]

Commands:
  add <job.json>       Add a job from JSON file
  remove <job-name>    Remove a job by name
  list                 List all scheduled jobs
  status [job-name]    Show job status and next run time
  run <job-name>       Execute a job immediately
  history [job-name]   Show execution history
  daemon               Run scheduler in foreground
  service install      Install as Windows service
  service uninstall    Uninstall Windows service
  service start        Start the service
  service stop         Stop the service
  validate <job.json>  Validate job configuration

Global Options:
  --config FILE        Configuration file (default: ~/.run-scheduler/config.json)
  --output FORMAT      Output format (text|json)
  --verbose            Verbose output
  --quiet              Suppress non-error output
  --help               Show help
  --version            Show version

Examples:
  run-scheduler add backup-job.json
  run-scheduler list --output json
  run-scheduler run database-backup
  run-scheduler history --last 10
  run-scheduler daemon --verbose
```

### Data Flow

```
Job Definition (JSON)
        |
        v
Configuration Loader --> Validation --> Job Registry
                                              |
                                              v
                         Scheduler Loop <-- Timer Check
                              |
                              v
                         Job Executor --> simple_process
                              |                  |
                              v                  v
                         Result Handler    Output Capture
                              |                  |
                              v                  v
                    +--------------------+
                    |   History Writer   |
                    |   Log Writer       |
                    |   Notifier         |
                    +--------------------+
```

### Job Configuration Schema

```json
{
  "name": "database-backup",
  "description": "Daily database backup to S3",
  "command": "cmd /c backup-db.bat",
  "working_directory": "C:\\scripts\\backup",
  "schedule": "0 2 * * *",
  "timezone": "America/New_York",
  "timeout_seconds": 3600,
  "retry_count": 3,
  "retry_delay_seconds": 60,
  "depends_on": ["check-disk-space"],
  "environment": {
    "BACKUP_BUCKET": "my-backups",
    "AWS_REGION": "us-east-1"
  },
  "notifications": {
    "on_success": false,
    "on_failure": true,
    "channels": ["email", "webhook"]
  },
  "enabled": true,
  "tags": ["backup", "database", "production"]
}
```

### Global Configuration Schema

```json
{
  "run_scheduler": {
    "data_directory": "C:\\ProgramData\\RunScheduler",
    "log_directory": "C:\\ProgramData\\RunScheduler\\logs",
    "log_retention_days": 30,
    "history_retention_days": 90,
    "default_timeout_seconds": 300,
    "max_concurrent_jobs": 10,
    "smtp": {
      "host": "smtp.example.com",
      "port": 587,
      "username": "alerts@example.com",
      "password_env": "SMTP_PASSWORD",
      "from": "RunScheduler <alerts@example.com>",
      "to": ["admin@example.com"]
    },
    "webhook": {
      "url": "https://hooks.slack.com/...",
      "headers": {
        "Authorization": "Bearer ${SLACK_TOKEN}"
      }
    }
  }
}
```

### Error Handling

| Error Type | Handling | User Message |
|------------|----------|--------------|
| Job not found | Return error code 1 | "Job 'name' not found. Use 'list' to see available jobs." |
| Invalid JSON config | Validation error with line number | "Configuration error at line 15: invalid cron expression" |
| Command execution failure | Log error, notify if configured | "Job 'name' failed with exit code 1. See logs for details." |
| Timeout exceeded | Kill process, log timeout | "Job 'name' exceeded timeout of 300 seconds and was terminated." |
| Notification failure | Log warning, continue | "Warning: Failed to send email notification. Job completed successfully." |
| Dependency failure | Skip job, log reason | "Job 'name' skipped: dependency 'other' failed." |
| Permission denied | Return error code 2 | "Permission denied. Run as administrator to modify service." |

### State Machine: Job Lifecycle

```
                    +----------+
                    |  PENDING |
                    +----+-----+
                         |
         (dependency)    v    (schedule trigger)
         +----------> WAITING <-----------+
         |           +---+---+            |
         |               |                |
         |               v                |
         |          +--------+            |
         +--------- | QUEUED | -----------+
                    +---+----+
                        |
                        v
                   +---------+
                   | RUNNING |
                   +----+----+
                        |
          +-------------+-------------+
          |             |             |
          v             v             v
     +---------+   +---------+   +---------+
     | SUCCESS |   | FAILURE |   | TIMEOUT |
     +---------+   +---------+   +---------+
          |             |             |
          +-------------+-------------+
                        |
                        v
                   +---------+
                   |  LOGGED |
                   +---------+
```

## GUI/TUI Future Path

**CLI foundation enables:**
- All job management operations accessible via CLI, enabling scripting and CI/CD integration
- JSON output mode allows building web dashboards that call the CLI
- Service architecture allows headless operation with separate UI layer

**What would change for TUI:**
- Add simple_tui integration for interactive job management
- Real-time job status display with refresh
- Log streaming in split pane
- Job creation wizard

**What would change for Web GUI:**
- Add simple_http for REST API server
- Expose job CRUD, status, and history endpoints
- Web dashboard consumes API
- WebSocket for real-time updates

**Shared components between CLI/GUI:**
- RUN_SCHEDULER_ENGINE (core scheduling logic)
- RUN_SCHEDULER_JOB (job model)
- RUN_SCHEDULER_EXECUTOR (execution logic)
- RUN_SCHEDULER_HISTORY (history queries)
- All business logic remains in shared library
