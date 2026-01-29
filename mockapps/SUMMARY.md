# Mock Apps Summary: simple_process

## Generated: 2026-01-24

## Library Analyzed

- **Library:** simple_process v1.0.0
- **Core capability:** SCOOP-compatible process execution with output capture for Windows
- **Ecosystem position:** Foundation library for all process/command execution in simple_* ecosystem
- **Key Classes:**
  - `SIMPLE_PROCESS` - Synchronous command execution
  - `SIMPLE_ASYNC_PROCESS` - Asynchronous execution with monitoring/kill capability

---

## Mock Apps Designed

### 1. RunScheduler

- **Purpose:** Modern cron-like job scheduler for Windows with JSON configuration, logging, and notifications
- **Target:** DevOps engineers and system administrators needing reliable task scheduling
- **Ecosystem:** simple_process, simple_json, simple_logger, simple_datetime, simple_cli, simple_sql, simple_smtp (Pro), simple_http (Enterprise)
- **Revenue Model:** Free/Open Core, Pro $49/mo, Enterprise $199/mo
- **Effort:** 15 days
- **Status:** Design complete

**Key Features:**
- JSON-based job configuration (versionable)
- Cron expression scheduling
- Job dependencies and chaining
- Timeout handling via simple_async_process
- SQLite execution history
- Email/webhook notifications (Pro)
- Windows service support

---

### 2. DeployRunner

- **Purpose:** Lightweight deployment automation with rollback support, logging, and multi-environment management
- **Target:** Development teams deploying to Windows servers
- **Ecosystem:** simple_process, simple_yaml, simple_json, simple_logger, simple_datetime, simple_cli, simple_sql, simple_archive, simple_http (Pro)
- **Revenue Model:** Free/Open Core, Pro $99/mo, Enterprise $399/mo
- **Effort:** 17 days
- **Status:** Design complete

**Key Features:**
- YAML/JSON deployment manifests
- Step-by-step execution with rollback on failure
- Per-step rollback commands
- Health checks after deployment
- Environment-specific configuration
- Artifact packaging/extraction
- Deployment history audit trail
- Webhook notifications (Pro)

---

### 3. ProcessWatchdog

- **Purpose:** Process supervisor and health monitor that keeps services running with alerting and auto-restart
- **Target:** IT operations teams and SREs managing Windows servers
- **Ecosystem:** simple_process, simple_async_process, simple_json, simple_logger, simple_datetime, simple_cli, simple_sql, simple_http (Pro), simple_smtp (Pro)
- **Revenue Model:** Free/Open Core (5 processes), Pro $79/mo, Enterprise $249/mo
- **Effort:** 17 days
- **Status:** Design complete

**Key Features:**
- Multi-process supervision
- Crash detection (<5 seconds)
- Automatic restart with backoff
- HTTP, command, and port health checks
- Flapping detection
- Resource limits (memory, CPU)
- Email/Slack/webhook alerts (Pro)
- Prometheus metrics export (Enterprise)
- Windows service support

---

## Ecosystem Coverage

| simple_* Library | Used In | Purpose |
|------------------|---------|---------|
| simple_process | All 3 apps | Command execution, health checks |
| simple_async_process | RunScheduler, ProcessWatchdog | Timeout handling, process monitoring |
| simple_json | All 3 apps | Configuration parsing |
| simple_yaml | DeployRunner | Manifest parsing |
| simple_logger | All 3 apps | Event logging |
| simple_datetime | All 3 apps | Timestamps, scheduling, uptime |
| simple_cli | All 3 apps | Argument parsing |
| simple_sql | All 3 apps | History/event storage |
| simple_smtp | All 3 apps (Pro) | Email notifications |
| simple_http | All 3 apps (Pro/Enterprise) | Webhooks, health checks, metrics |
| simple_archive | DeployRunner | Artifact management |
| simple_file | DeployRunner, ProcessWatchdog | File operations |
| simple_config | Optional for all | Environment variable expansion |
| simple_uuid | Optional for all | Unique IDs |

**Total unique libraries leveraged:** 14

---

## Comparison Matrix

| Feature | RunScheduler | DeployRunner | ProcessWatchdog |
|---------|--------------|--------------|-----------------|
| Primary Use | Task scheduling | Deployment automation | Process supervision |
| Config Format | JSON | YAML/JSON | JSON |
| Execution Mode | Scheduled | On-demand | Continuous |
| Rollback | No | Yes | N/A (restart) |
| Health Checks | No | Yes | Yes |
| Multi-server | Enterprise | Pro | Enterprise |
| Metrics Export | No | No | Enterprise |
| Estimated Effort | 15 days | 17 days | 17 days |
| Market Comparison | cron, Task Scheduler | Ansible, Octopus | Supervisord, Monit |

---

## Implementation Priority

**Recommended Order:**

1. **ProcessWatchdog** - Highest unique value (Windows process supervisor gap)
2. **RunScheduler** - Clear market need (Windows Task Scheduler pain)
3. **DeployRunner** - More competition (Ansible, Octopus exist)

**Rationale:**
- ProcessWatchdog fills a clear gap (no good Windows-native process supervisor)
- RunScheduler modernizes a painful experience (Windows Task Scheduler)
- DeployRunner has strong competition but still valuable for the ecosystem

---

## Next Steps

1. **Select Mock App** - Choose one to implement based on priority
2. **Create ECF** - Add app target to simple_process.ecf or create standalone project
3. **Phase 1 (MVP)** - Implement using Eiffel Spec Kit workflow:
   - `/eiffel.intent` - Capture intent
   - `/eiffel.contracts` - Generate class skeletons
   - `/eiffel.review` - AI review chain
   - `/eiffel.tasks` - Break into tasks
   - `/eiffel.implement` - Write feature bodies
   - `/eiffel.verify` - Run tests
4. **Iterate** - Complete phases 2-4

---

## Files Generated

```
D:\prod\simple_process\mockapps\
├── 00-MARKETPLACE-RESEARCH.md
├── 01-run-scheduler\
│   ├── CONCEPT.md
│   ├── DESIGN.md
│   ├── BUILD-PLAN.md
│   └── ECOSYSTEM-MAP.md
├── 02-deploy-runner\
│   ├── CONCEPT.md
│   ├── DESIGN.md
│   ├── BUILD-PLAN.md
│   └── ECOSYSTEM-MAP.md
├── 03-process-watchdog\
│   ├── CONCEPT.md
│   ├── DESIGN.md
│   ├── BUILD-PLAN.md
│   └── ECOSYSTEM-MAP.md
└── SUMMARY.md
```

---

## Research Sources

- [Cflow - Business Process Automation Trends 2026](https://www.cflowapps.com/business-process-automation-trends/)
- [Spacelift - Open-Source Automation Tools 2025](https://spacelift.io/blog/open-source-automation-tools)
- [KVY Technology - Task Runners & Build Automation](https://kvytechnology.com/blog/software/task-runners-and-build-automation-tools/)
- [Redwood - Windows Job Scheduling](https://www.redwood.com/workload-automation/job-scheduling/windows/)
- [Last9 - Cron Jobs in Windows](https://last9.io/blog/manage-cron-jobs-in-windows/)
- [Monit - Process Monitoring](https://mmonit.com/monit/)
- [Functionize - Automated Deployment Tools 2025](https://www.functionize.com/automated-testing/best-automated-deployment-tools)
- [AttuneOps - DevOps Automation Tools 2025](https://attuneops.io/devops-automation-tools/)
- [GitLab Runner Documentation](https://docs.gitlab.com/runner/)
- [Gartner - BPA Tools Reviews 2026](https://www.gartner.com/reviews/market/business-process-automation-tools)
