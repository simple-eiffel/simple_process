# DeployRunner

## Executive Summary

DeployRunner is a lightweight deployment automation tool that executes script sequences with rollback support, comprehensive logging, and multi-environment management. Unlike heavyweight tools like Ansible or Chef, DeployRunner focuses on the common case: running deployment scripts in sequence with proper error handling, logging, and the ability to roll back when things go wrong.

Built for Windows-first environments, DeployRunner uses YAML or JSON manifests to define deployment steps, environment variables, and rollback procedures. It integrates with the simple_* ecosystem, leveraging simple_process for script execution, simple_yaml/simple_json for configuration, simple_logger for audit trails, and simple_archive for artifact packaging.

The product follows a tiered model: free for single-server deployments, Pro for multi-server and rollback features, and Enterprise for RBAC and team collaboration.

## Problem Statement

**The problem:** Development teams deploying to Windows servers often use ad-hoc batch scripts or PowerShell without proper logging, error handling, or rollback capability. When deployments fail, there's no audit trail and no easy way to revert. Enterprise tools like Ansible require significant setup and learning curve.

**Current solutions:**
- Manual deployment: Error-prone, no audit trail
- Batch/PowerShell scripts: No standardization, poor error handling
- Ansible/Chef: Complex setup, primarily Linux-focused
- Octopus Deploy: Expensive ($45,000+/year), complex
- Azure DevOps: Requires Azure ecosystem
- GitHub Actions: Requires GitHub, complex for simple deployments

**Our approach:** A focused deployment tool that:
- Defines deployments as YAML/JSON manifests (versionable)
- Executes steps in sequence with automatic rollback on failure
- Logs every action for audit compliance
- Manages environment-specific configuration
- Works standalone or integrates with CI/CD pipelines
- Windows-native, simple to install and use

## Target Users

| User Type | Description | Key Needs |
|-----------|-------------|-----------|
| Primary | DevOps Engineers | Repeatable deployments, rollback, logging |
| Primary | Software Developers | Simple deployment for their apps |
| Secondary | System Administrators | Server configuration management |
| Secondary | Release Managers | Audit trail, approval workflows |

## Value Proposition

**For** development teams deploying to Windows servers
**Who** need reliable, repeatable deployments with rollback capability
**This app** provides a lightweight deployment tool with manifest-based configuration
**Unlike** complex enterprise tools or ad-hoc scripts
**We** offer simple setup, comprehensive logging, and built-in rollback in minutes, not days

## Revenue Model

| Model | Description | Price Point |
|-------|-------------|-------------|
| Free/Open Core | Single-server deployment, basic logging | $0 |
| Pro License | Multi-server, rollback, artifact management, webhooks | $99/month |
| Enterprise License | RBAC, approval workflows, Slack/Teams integration, API | $399/month |
| On-Premise Enterprise | Unlimited servers, custom SLA, training | $5,000/year |

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Deployment success rate | 95%+ with rollback | Successful deployments vs. total |
| Rollback reliability | 99%+ | Successful rollbacks when triggered |
| Time to first deployment | <30 minutes | New user to first successful deploy |
| Audit completeness | 100% | All actions logged with timestamp |
| CI/CD integration | 5 major platforms | Jenkins, GitHub, GitLab, Azure, TeamCity |
