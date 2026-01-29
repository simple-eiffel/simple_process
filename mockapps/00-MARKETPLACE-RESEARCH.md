# Marketplace Research: simple_process

**Generated:** 2026-01-24
**Library:** simple_process v1.0.0
**Status:** Production Ready (9 tests passing)

---

## Library Profile

### Core Capabilities

| Capability | Description | Business Value |
|------------|-------------|----------------|
| Command Execution | Run shell commands synchronously | Automate any CLI tool from Eiffel |
| Output Capture | Get stdout as STRING_32 | Parse and process command results |
| Async Execution | Non-blocking process launch with monitoring | Long-running operations without blocking |
| Exit Code Access | Retrieve process exit codes | Error detection and flow control |
| Error Handling | Detailed error messages on failure | Debugging and user feedback |
| Working Directory | Execute in specific directories | Project-based operations |
| PATH Lookup | Check if executable exists in PATH | Tool availability validation |
| Process Monitoring | Track elapsed time, kill hung processes | Timeout and health management |
| Window Visibility | Show/hide process windows | Background vs. interactive execution |

### API Surface

| Feature | Type | Use Case |
|---------|------|----------|
| `execute(command)` | Command | Run command and capture output |
| `execute_in_directory(cmd, dir)` | Command | Run in specific working directory |
| `output_of_command(cmd)` | Query | Execute and return output string |
| `was_successful` | Query | Check if last command succeeded |
| `last_exit_code` | Query | Get exit code for error handling |
| `last_error` | Query | Get error message on failure |
| `file_exists_in_path(name)` | Query | Validate tool availability |
| `start(command)` | Command | Async process launch |
| `is_running` | Query | Check if async process active |
| `elapsed_seconds` | Query | Monitor process duration |
| `kill` | Command | Terminate hung process |
| `read_available_output` | Query | Non-blocking output read |

### Classes

| Class | Purpose |
|-------|---------|
| SIMPLE_PROCESS | Synchronous command execution with output capture |
| SIMPLE_ASYNC_PROCESS | Non-blocking execution with monitoring and kill capability |

### Existing Dependencies

| simple_* Library | Purpose in this library |
|------------------|------------------------|
| simple_datetime | Timestamp tracking for elapsed time (SIMPLE_DATE_TIME) |

### Integration Points

- **Input formats:** Shell command strings, working directory paths
- **Output formats:** STRING_32 (stdout), INTEGER (exit codes), BOOLEAN (success/failure)
- **Data flow:** Command string -> Win32 API -> Pipe capture -> STRING_32 result

---

## Marketplace Analysis

### Industry Applications

| Industry | Application | Pain Point Solved |
|----------|-------------|-------------------|
| DevOps/CI | Build automation, test execution | Reliable process execution with output capture |
| System Admin | Scheduled task automation | Unified job management across tools |
| IT Operations | Health monitoring, service management | Process watchdog with timeout/kill |
| Development | Local development environment | Tool orchestration and build systems |
| Data Engineering | ETL pipeline execution | Chained process execution with error handling |
| Infrastructure | Deployment automation | Script runner with logging and reporting |

### Commercial Products (Competitors/Inspirations)

| Product | Price Point | Key Features | Gap We Could Fill |
|---------|-------------|--------------|-------------------|
| Redwood RunMyJobs | $50K+/year | Enterprise job scheduling | Lightweight CLI scheduler |
| Jenkins | Free/Enterprise | CI/CD automation | Simpler, focused task runner |
| Ansible | Free/Tower $10K+ | Infrastructure automation | Windows-native script runner |
| Monit | Free | Process supervisor | Eiffel-native watchdog |
| Task (Taskfile) | Free | Cross-platform build tool | Eiffel ecosystem integration |
| Supervisord | Free | Process manager | Windows-first approach |
| GitLab Runner | Free/Enterprise | CI job executor | Self-contained deployment |
| Windows Task Scheduler | Built-in | Basic cron jobs | Programmable CLI scheduler |

### Workflow Integration Points

| Workflow | Where This Library Fits | Value Added |
|----------|-------------------------|-------------|
| CI/CD Pipeline | Execute build/test commands | Reliable output capture for reporting |
| Deployment | Run deployment scripts | Error handling and rollback triggers |
| Monitoring | Check service health | Process timeout and restart capability |
| Data Processing | Execute ETL tools | Exit code chaining for pipelines |
| Development | Run local tooling | Unified interface across dev tools |
| Operations | Scheduled maintenance | Job tracking and notification |

### Target User Personas

| Persona | Role | Need | Willingness to Pay |
|---------|------|------|-------------------|
| DevOps Engineer | CI/CD automation | Reliable job runner with logging | HIGH |
| System Administrator | Task scheduling | Cron replacement with monitoring | MEDIUM |
| IT Manager | Operations visibility | Process health dashboard data | HIGH |
| Software Developer | Build automation | Simple task runner for projects | MEDIUM |
| Data Engineer | Pipeline execution | ETL orchestration with error handling | HIGH |
| SRE | Service reliability | Process watchdog with alerting | HIGH |

---

## Mock App Candidates

### Candidate 1: RunScheduler

**One-liner:** Cron-like job scheduler for Windows with JSON configuration, logging, and notification support.

**Target market:** Windows system administrators and DevOps teams needing reliable task scheduling beyond Windows Task Scheduler.

**Revenue model:**
- Open core: Basic scheduler free
- Pro: $49/month - Email notifications, job chains, web dashboard data export
- Enterprise: $199/month - LDAP auth, audit logging, API access

**Ecosystem leverage:**
- simple_process (core execution)
- simple_json (configuration)
- simple_logger (job logging)
- simple_datetime (scheduling)
- simple_email/simple_smtp (notifications)
- simple_sql (job history database)

**CLI-first value:** Run as Windows service or standalone CLI. Configure via JSON files. Full control from command line for DevOps pipelines.

**GUI/TUI potential:** Web dashboard showing job status, next run times, history. TUI for interactive job management.

**Viability:** HIGH - Windows Task Scheduler is clunky; market needs modern CLI scheduler.

---

### Candidate 2: DeployRunner

**One-liner:** Deployment automation tool that executes script sequences with rollback, logging, and multi-server support.

**Target market:** Development teams and DevOps engineers managing deployments to Windows servers.

**Revenue model:**
- Open core: Single-server deployment free
- Pro: $99/month - Multi-server, rollback, SSH/WinRM support
- Enterprise: $399/month - RBAC, audit trail, Slack/Teams integration

**Ecosystem leverage:**
- simple_process (script execution)
- simple_json (deployment manifests)
- simple_yaml (alternative config format)
- simple_logger (deployment logs)
- simple_http (webhook notifications)
- simple_sql (deployment history)
- simple_archive (artifact packaging)
- simple_config (environment management)

**CLI-first value:** `deploy run staging`, `deploy rollback production`. Perfect for CI/CD integration. Deployment manifests as code.

**GUI/TUI potential:** Deployment dashboard showing server status, recent deployments, rollback history.

**Viability:** HIGH - Ansible/Chef are overkill for many teams; need lightweight Windows-first deployment tool.

---

### Candidate 3: ProcessWatchdog

**One-liner:** Process supervisor and health monitor that keeps services running, with alerting and auto-restart.

**Target market:** IT operations teams and SREs managing Windows services and background processes.

**Revenue model:**
- Open core: Basic monitoring and restart free
- Pro: $79/month - Email/Slack alerts, resource thresholds, process groups
- Enterprise: $249/month - Multi-server, API, custom health checks

**Ecosystem leverage:**
- simple_process / simple_async_process (process monitoring)
- simple_json (configuration)
- simple_logger (health logs)
- simple_datetime (uptime tracking)
- simple_http (webhook alerts)
- simple_email (alert notifications)
- simple_sql (health history database)

**CLI-first value:** `watchdog start myapp`, `watchdog status`, `watchdog restart myapp`. Run as service or foreground. Export metrics for Prometheus/Grafana.

**GUI/TUI potential:** Real-time process dashboard, health graphs, alert configuration UI.

**Viability:** HIGH - Supervisord/Monit are Linux-focused; Windows needs native process supervisor.

---

## Selection Rationale

These three Mock Apps were selected because:

1. **All solve real pain points:** Windows ecosystem lacks modern CLI tools for task scheduling, deployment automation, and process supervision.

2. **Market validation:** Each has successful Linux-equivalent products (cron, Ansible, Supervisord) proving market demand.

3. **Ecosystem leverage:** Each uses 5+ simple_* libraries, demonstrating the power of the ecosystem.

4. **CLI-first natural fit:** All three are fundamentally CLI tools that benefit from programmatic access.

5. **Revenue potential:** Clear path from free tier to enterprise licensing for each product.

6. **Differentiation:** Windows-native, Eiffel-powered, SCOOP-compatible - unique positioning in market.

---

## Research Sources

- [Cflow - Business Process Automation Trends](https://www.cflowapps.com/business-process-automation-trends/)
- [Spacelift - Open-Source Automation Tools](https://spacelift.io/blog/open-source-automation-tools)
- [Gartner - BPA Tools Reviews](https://www.gartner.com/reviews/market/business-process-automation-tools)
- [KVY Technology - Task Runners & Build Automation](https://kvytechnology.com/blog/software/task-runners-and-build-automation-tools/)
- [TechTarget - Task Automation Tools](https://www.techtarget.com/searchitoperations/tip/Task-automation-tools-to-increase-productivity)
- [Redwood - Windows Job Scheduling](https://www.redwood.com/workload-automation/job-scheduling/windows/)
- [Last9 - Cron Jobs in Windows](https://last9.io/blog/manage-cron-jobs-in-windows/)
- [Monit - Process Monitoring](https://mmonit.com/monit/)
- [AttuneOps - DevOps Automation Tools](https://attuneops.io/devops-automation-tools/)
- [Functionize - Automated Deployment Tools](https://www.functionize.com/automated-testing/best-automated-deployment-tools)
