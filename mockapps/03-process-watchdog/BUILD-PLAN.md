# ProcessWatchdog - Build Plan

## Phase Overview

| Phase | Deliverable | Effort | Dependencies |
|-------|-------------|--------|--------------|
| Phase 1 | MVP Supervisor | 5 days | simple_process, simple_async_process, simple_json, simple_logger |
| Phase 2 | Full Monitoring | 5 days | Phase 1 + simple_sql, simple_datetime |
| Phase 3 | Pro Features | 4 days | Phase 2 + simple_http, simple_smtp |
| Phase 4 | Polish & Release | 3 days | Phase 3 complete |

**Total Estimated Effort:** 17 days

---

## Phase 1: MVP

### Objective

Demonstrate core supervision capability: spawn processes, detect crashes, auto-restart, log events. Must successfully keep a process running despite simulated crashes.

### Deliverables

1. **WATCHDOG_CLI** - Main CLI entry point
2. **WATCHDOG_PROCESS** - Process definition model
3. **WATCHDOG_MONITOR** - Individual process monitor
4. **WATCHDOG_ENGINE** - Supervision loop
5. **WATCHDOG_CONFIG** - JSON configuration loader
6. **Basic CLI** - `daemon`, `start`, `stop`, `status` commands

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T1.1 | Create project structure and ECF | Compiles with required libraries |
| T1.2 | Implement WATCHDOG_PROCESS | Model with name, command, working_dir |
| T1.3 | Implement WATCHDOG_MONITOR | Spawn process via simple_async_process |
| T1.4 | Implement crash detection | Detect when process exits unexpectedly |
| T1.5 | Implement auto-restart | Restart crashed processes |
| T1.6 | Implement WATCHDOG_ENGINE | Main loop checking all processes |
| T1.7 | Implement WATCHDOG_CONFIG | Load processes from JSON |
| T1.8 | Implement basic CLI | daemon, start, stop, status commands |
| T1.9 | Add logging integration | Log all events to file |
| T1.10 | Write MVP tests | Test spawn, crash detection, restart |

### Test Cases

| Test | Input | Expected Output |
|------|-------|-----------------|
| Load valid config | JSON with 2 processes | Two process definitions |
| Start process | `start myapp` | Process running, PID logged |
| Detect crash | Process exits with code 1 | Crash detected, logged |
| Auto-restart | Crash detected | Process restarted within 5s |
| Stop process | `stop myapp` | Process terminated gracefully |
| Status running | Running process | "myapp: running (PID=1234, uptime=60s)" |
| Status stopped | Stopped process | "myapp: stopped" |

### MVP Success Criteria

- [ ] `process-watchdog daemon` runs supervisor loop
- [ ] Processes configured in JSON start automatically
- [ ] Crashed processes restart automatically
- [ ] `status` shows running/stopped state
- [ ] All events logged to file

---

## Phase 2: Full Implementation

### Objective

Add health checks, restart policies, event history (SQLite), resource limits, and complete CLI commands.

### Deliverables

1. **WATCHDOG_HEALTH_CHECKER** - Command and HTTP health checks
2. **WATCHDOG_RESTART_POLICY** - Backoff, max retries, flapping detection
3. **WATCHDOG_HISTORY** - SQLite event storage
4. **Resource monitoring** - Memory/CPU limits
5. **Complete CLI** - add, remove, reload, logs, history commands

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T2.1 | Implement command health check | Execute command, check output |
| T2.2 | Implement HTTP health check | GET endpoint, check status/body |
| T2.3 | Implement port health check | Check TCP port listening |
| T2.4 | Implement WATCHDOG_RESTART_POLICY | Backoff delays, max retries |
| T2.5 | Implement flapping detection | Detect rapid restart cycles |
| T2.6 | Implement WATCHDOG_HISTORY | SQLite event storage |
| T2.7 | Add resource monitoring | Memory usage via Win32 API |
| T2.8 | Implement add command | Add process from JSON file |
| T2.9 | Implement remove command | Remove process from supervision |
| T2.10 | Implement reload command | Reload config without restart |
| T2.11 | Implement logs command | Show process output logs |
| T2.12 | Implement history command | Query event history |
| T2.13 | Write comprehensive tests | Test health checks, policies |

### Restart Policy Behavior

```
Restart 1: Wait 5 seconds
Restart 2: Wait 10 seconds
Restart 3: Wait 30 seconds
Restart 4: Wait 60 seconds
Restart 5: Wait 120 seconds
Restart 6: FLAPPING DETECTED - disable auto-restart, alert
```

---

## Phase 3: Pro Features

### Objective

Add alerting (email, Slack, webhook), Prometheus metrics export, and prepare for Enterprise features.

### Deliverables

1. **WATCHDOG_ALERTER** - Multi-channel alert dispatch
2. **Email notifications** - Via simple_smtp
3. **Slack/Webhook notifications** - Via simple_http
4. **Prometheus metrics** - Via simple_http server
5. **Process groups** - Manage related processes together

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T3.1 | Implement WATCHDOG_ALERTER | Dispatch to configured channels |
| T3.2 | Add email support | Send via simple_smtp |
| T3.3 | Add Slack webhook support | POST to Slack webhook |
| T3.4 | Add generic webhook support | POST JSON to URL |
| T3.5 | Implement Prometheus metrics | /metrics endpoint |
| T3.6 | Add metrics for all processes | up, uptime, restarts, health |
| T3.7 | Implement process groups | Group start/stop/restart |
| T3.8 | Add alert throttling | Prevent alert storms |
| T3.9 | Add Pro license check | Feature gating |
| T3.10 | Write alerting tests | Test email/webhook dispatch |

---

## Phase 4: Production Polish

### Objective

Windows service support, documentation, packaging, and final testing.

### Deliverables

1. **WATCHDOG_SERVICE** - Windows service wrapper
2. **Error handling hardening** - All edge cases covered
3. **Help documentation** - `--help` for all commands
4. **README.md** - Installation and usage guide
5. **Installer** - INNO Setup package
6. **Grafana dashboard** - Example dashboard JSON

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T4.1 | Implement Windows service | install/uninstall/start/stop |
| T4.2 | Add comprehensive --help | Every command has detailed help |
| T4.3 | Error handling review | Graceful handling of all errors |
| T4.4 | Performance testing | Monitor 50 processes without lag |
| T4.5 | Write README.md | Installation, configuration, usage |
| T4.6 | Create example configs | Real-world process configs |
| T4.7 | Create Grafana dashboard | Dashboard for Prometheus metrics |
| T4.8 | Create INNO installer | Single-file Windows installer |
| T4.9 | Final integration tests | End-to-end scenario testing |
| T4.10 | Code review and cleanup | Consistent style, no debug code |

---

## ECF Target Structure

```xml
<!-- Library target (reusable by other apps) -->
<target name="watchdog_lib">
    <root all_classes="true" />
    <!-- All dependencies and clusters except CLI -->
</target>

<!-- CLI executable target -->
<target name="process_watchdog" extends="watchdog_lib">
    <root class="WATCHDOG_CLI" feature="make"/>
    <cluster name="cli" location=".\src\cli\"/>
</target>

<!-- Test target -->
<target name="process_watchdog_tests" extends="watchdog_lib">
    <root class="TEST_APP" feature="make"/>
    <library name="simple_testing"
             location="$SIMPLE_EIFFEL/simple_testing/simple_testing.ecf"/>
    <cluster name="tests" location=".\tests\"/>
</target>
```

---

## Build Commands

```bash
# Compile CLI (development)
ec.exe -batch -config process_watchdog.ecf -target process_watchdog -c_compile

# Compile CLI (production)
ec.exe -batch -config process_watchdog.ecf -target process_watchdog -finalize -c_compile

# Run tests
ec.exe -batch -config process_watchdog.ecf -target process_watchdog_tests -c_compile
./EIFGENs/process_watchdog_tests/W_code/process_watchdog.exe

# Run finalized tests
ec.exe -batch -config process_watchdog.ecf -target process_watchdog_tests -finalize -c_compile
./EIFGENs/process_watchdog_tests/F_code/process_watchdog.exe
```

---

## Success Criteria

| Criterion | Measure | Target |
|-----------|---------|--------|
| Compiles | Zero errors, zero warnings | 100% |
| Tests pass | All test cases | 100% |
| CLI works | All commands functional | Pass |
| Crash detection | Time to detect | <5s |
| Auto-restart | Reliability | 99%+ |
| Metrics | Prometheus format | Valid |
| Performance | Monitor 50 processes | <1% CPU |
| Documentation | README complete | Yes |

---

## Directory Structure

```
process_watchdog/
├── process_watchdog.ecf
├── README.md
├── CHANGELOG.md
├── LICENSE
├── src/
│   ├── cli/
│   │   └── watchdog_cli.e
│   ├── engine/
│   │   ├── watchdog_engine.e
│   │   ├── watchdog_monitor.e
│   │   └── watchdog_restart_policy.e
│   ├── model/
│   │   ├── watchdog_process.e
│   │   ├── watchdog_health_check.e
│   │   └── watchdog_event.e
│   ├── health/
│   │   └── watchdog_health_checker.e
│   ├── config/
│   │   └── watchdog_config.e
│   ├── persistence/
│   │   └── watchdog_history.e
│   ├── alerting/
│   │   └── watchdog_alerter.e
│   ├── metrics/
│   │   └── watchdog_metrics.e
│   └── service/
│       └── watchdog_service.e
├── tests/
│   ├── test_app.e
│   ├── test_monitor.e
│   ├── test_health_checker.e
│   ├── test_restart_policy.e
│   └── test_history.e
├── examples/
│   ├── simple-config.json
│   ├── webserver-config.json
│   ├── workers-config.json
│   └── grafana-dashboard.json
└── installer/
    └── process_watchdog.iss
```

---

## Example Configuration: Web Server Monitoring

```json
{
  "watchdog": {
    "check_interval_seconds": 5,
    "log_directory": "C:\\ProgramData\\Watchdog\\logs"
  },
  "processes": [
    {
      "name": "nginx",
      "command": "C:\\nginx\\nginx.exe",
      "working_directory": "C:\\nginx",
      "health_check": {
        "type": "http",
        "url": "http://localhost:80/health",
        "expected_status": 200,
        "interval_seconds": 30,
        "timeout_seconds": 5
      },
      "restart_policy": {
        "enabled": true,
        "max_retries": 5,
        "backoff_seconds": [5, 10, 30, 60, 120]
      },
      "alerts": {
        "on_crash": true,
        "on_restart": true,
        "channels": ["slack"]
      },
      "auto_start": true
    },
    {
      "name": "api-server",
      "command": "node",
      "arguments": "server.js",
      "working_directory": "C:\\Apps\\API",
      "environment": {
        "NODE_ENV": "production",
        "PORT": "3000"
      },
      "health_check": {
        "type": "http",
        "url": "http://localhost:3000/api/health",
        "expected_body": "ok",
        "interval_seconds": 15
      },
      "resource_limits": {
        "max_memory_mb": 1024,
        "action": "restart"
      },
      "depends_on": ["nginx"],
      "auto_start": true
    },
    {
      "name": "worker",
      "command": "C:\\Apps\\Worker\\worker.exe",
      "arguments": "--queue=jobs",
      "health_check": {
        "type": "command",
        "command": "C:\\Apps\\Worker\\check-queue.bat",
        "expected_output": "queue_healthy"
      },
      "restart_policy": {
        "enabled": true,
        "max_retries": 10
      },
      "auto_start": true
    }
  ]
}
```
