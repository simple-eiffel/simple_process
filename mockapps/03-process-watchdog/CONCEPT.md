# ProcessWatchdog

## Executive Summary

ProcessWatchdog is a process supervisor and health monitor that keeps critical services running on Windows. It monitors configured processes, automatically restarts them if they crash, enforces resource limits, and sends alerts when problems occur. Unlike Linux-focused tools like Supervisord or Monit, ProcessWatchdog is built Windows-first with native Win32 integration.

The tool solves a common operations problem: ensuring that background processes and services stay running without manual intervention. When a monitored process crashes or becomes unresponsive, ProcessWatchdog detects the issue, logs the event, restarts the process, and notifies operators via email or webhook.

Built on simple_process and simple_async_process, ProcessWatchdog leverages the full simple_* ecosystem for configuration (simple_json), logging (simple_logger), alerting (simple_smtp, simple_http), and history (simple_sql).

## Problem Statement

**The problem:** Windows servers run many critical background processes (application servers, workers, agents) that can crash or hang. Without monitoring, these failures go unnoticed until users complain. Windows services provide basic restart capability, but lack health checks, resource monitoring, and flexible alerting.

**Current solutions:**
- Windows Services: Basic, limited health checks, no flexible alerting
- Supervisord: Linux-focused, runs under WSL on Windows
- Monit: Excellent but Linux-only
- NSSM (Non-Sucking Service Manager): Basic, no health checks
- Uptime Robot/Pingdom: External monitoring, no process restart
- Custom scripts: Ad-hoc, unreliable, no standardization

**Our approach:** A dedicated process supervisor that:
- Monitors multiple processes defined in JSON configuration
- Automatically restarts crashed or hung processes
- Performs custom health checks (HTTP, command output)
- Enforces resource limits (memory, CPU time)
- Sends configurable alerts (email, webhook, Slack)
- Logs all events for audit and debugging
- Runs as Windows service or foreground daemon
- Exports metrics for Prometheus/Grafana integration

## Target Users

| User Type | Description | Key Needs |
|-----------|-------------|-----------|
| Primary | Site Reliability Engineers | Process monitoring, alerting, metrics |
| Primary | IT Operations Teams | Keep services running, reduce downtime |
| Secondary | DevOps Engineers | Application monitoring in pipelines |
| Secondary | System Administrators | Server management, compliance |

## Value Proposition

**For** operations teams managing Windows servers
**Who** need to ensure critical processes stay running
**This app** provides a process supervisor with health checks and alerting
**Unlike** Linux-focused tools or basic Windows services
**We** offer Windows-native monitoring with modern alerting and metrics in a single binary

## Revenue Model

| Model | Description | Price Point |
|-------|-------------|-------------|
| Free/Open Core | Monitor 5 processes, basic restart, file logging | $0 |
| Pro License | Unlimited processes, email/Slack alerts, resource limits | $79/month |
| Enterprise License | Multi-server, Prometheus metrics, API, priority support | $249/month |
| On-Premise Enterprise | Unlimited servers, custom SLA | $3,000/year |

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Crash detection | <5 seconds | Time from crash to detection |
| Auto-restart success | 99%+ | Successful restarts vs. attempts |
| Alert delivery | <30 seconds | Time from event to notification |
| Uptime improvement | 50%+ reduction in downtime | Before/after comparison |
| Metric export | Real-time | Prometheus scrape latency <1s |
