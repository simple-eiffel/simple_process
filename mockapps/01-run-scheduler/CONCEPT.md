# RunScheduler

## Executive Summary

RunScheduler is a modern, cron-like job scheduler built for Windows environments. Unlike the clunky Windows Task Scheduler, RunScheduler provides a clean CLI interface with JSON-based configuration, comprehensive logging, and notification support. It runs as either a Windows service or standalone daemon, executing scheduled jobs with full output capture, error handling, and job chaining capabilities.

Built on the simple_* ecosystem, RunScheduler leverages simple_process for reliable command execution, simple_json for configuration, simple_logger for audit trails, and simple_smtp for notifications. It targets DevOps teams and system administrators who need programmatic control over scheduled tasks without the complexity of enterprise job schedulers.

The product follows a freemium model with an open-core free tier for basic scheduling, a Pro tier adding notifications and job chains, and an Enterprise tier with audit logging and API access.

## Problem Statement

**The problem:** Windows Task Scheduler has a clunky GUI, limited CLI support (schtasks.exe is verbose and hard to use), no native JSON configuration, poor logging, and no built-in notification capabilities. Developers and ops teams want to define scheduled jobs as code, track them in version control, and receive alerts on failures.

**Current solutions:**
- Windows Task Scheduler: GUI-focused, XML config, limited CLI
- PowerShell scheduled jobs: Windows-only, requires PS expertise
- Jenkins: Overkill for simple scheduling, complex setup
- cron (WSL): Requires WSL, not native Windows
- Enterprise schedulers (RunMyJobs, Control-M): Expensive, complex

**Our approach:** A native Windows CLI tool with:
- JSON configuration files (versionable, human-readable)
- Simple CLI: `run-scheduler add job.json`, `run-scheduler list`, `run-scheduler run jobname`
- Built-in logging with rotation
- Email/webhook notifications on success/failure
- Job chaining (run job B after job A succeeds)
- Run as service or foreground daemon

## Target Users

| User Type | Description | Key Needs |
|-----------|-------------|-----------|
| Primary | DevOps Engineers | Config-as-code, CI/CD integration, notification on failure |
| Primary | System Administrators | Reliable scheduling, logging, easy management |
| Secondary | Software Developers | Local automation, build scheduling |
| Secondary | Data Engineers | ETL job scheduling, dependency chains |

## Value Proposition

**For** DevOps engineers and system administrators
**Who** need to schedule and automate tasks on Windows servers
**This app** provides a modern, CLI-first job scheduler with JSON configuration
**Unlike** Windows Task Scheduler or expensive enterprise solutions
**We** offer simple configuration, comprehensive logging, and built-in notifications in a lightweight package

## Revenue Model

| Model | Description | Price Point |
|-------|-------------|-------------|
| Free/Open Core | Basic scheduling, logging, CLI management | $0 |
| Pro License | Email notifications, job chains, webhook alerts, log export | $49/month |
| Enterprise License | LDAP auth, audit logging, REST API, priority support | $199/month |
| On-Premise Enterprise | Unlimited servers, custom SLA | $2,000/year |

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Job execution reliability | 99.9% success rate | Jobs completed vs. scheduled |
| Configuration adoption | 80% JSON config | Users defining jobs in JSON vs. CLI |
| Notification delivery | <30 seconds | Time from job completion to alert |
| Log retention | 30 days default | Searchable history available |
| CLI response time | <100ms | Time to list/query jobs |
