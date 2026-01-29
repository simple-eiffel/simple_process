# DeployRunner - Technical Design

## Architecture

### Component Overview

```
+----------------------------------------------------------+
|                      DeployRunner                         |
+----------------------------------------------------------+
|  CLI Interface Layer                                      |
|    - Argument parsing (simple_cli)                        |
|    - Command routing (deploy/rollback/status/init)        |
|    - Output formatting (text/json)                        |
+----------------------------------------------------------+
|  Deployment Engine Layer                                  |
|    - Manifest parsing (simple_yaml/simple_json)           |
|    - Step sequencing                                      |
|    - Rollback coordination                                |
|    - Environment resolution                               |
+----------------------------------------------------------+
|  Execution Layer                                          |
|    - Script execution (simple_process)                    |
|    - Output capture and logging                           |
|    - Health checks                                        |
|    - Timeout management                                   |
+----------------------------------------------------------+
|  Artifact Layer                                           |
|    - Package extraction (simple_archive)                  |
|    - Version management                                   |
|    - Backup creation                                      |
+----------------------------------------------------------+
|  Persistence Layer                                        |
|    - Deployment history (simple_sql)                      |
|    - Audit logging (simple_logger)                        |
|    - State snapshots                                      |
+----------------------------------------------------------+
|  Notification Layer                                       |
|    - Webhook callbacks (simple_http)                      |
|    - Slack/Teams integration                              |
+----------------------------------------------------------+
```

### Class Design

| Class | Responsibility | Key Features |
|-------|----------------|--------------|
| DEPLOY_RUNNER_CLI | Command-line interface | parse_args, route_command, format_output |
| DEPLOY_RUNNER_ENGINE | Deployment orchestration | deploy, rollback, get_status |
| DEPLOY_RUNNER_MANIFEST | Manifest model | steps, environments, rollback_steps |
| DEPLOY_RUNNER_STEP | Individual step | command, working_dir, timeout, on_failure |
| DEPLOY_RUNNER_EXECUTOR | Step execution | run_step, capture_output, check_health |
| DEPLOY_RUNNER_ROLLBACK | Rollback coordinator | create_snapshot, restore_snapshot |
| DEPLOY_RUNNER_ENVIRONMENT | Environment config | resolve_variables, load_env_file |
| DEPLOY_RUNNER_HISTORY | Deployment history | record, get_history, compare |
| DEPLOY_RUNNER_ARTIFACT | Artifact management | extract, backup, restore |
| DEPLOY_RUNNER_NOTIFIER | Notification dispatch | notify_start, notify_complete, notify_failure |

### Command Structure

```bash
deploy-runner <command> [options] [arguments]

Commands:
  deploy <manifest>      Execute deployment from manifest
  rollback <deployment>  Rollback to previous state
  status                 Show current deployment status
  history [--count N]    Show deployment history
  init                   Initialize deployment manifest template
  validate <manifest>    Validate manifest without executing
  diff <env1> <env2>     Compare environments
  artifact pack <dir>    Create deployment artifact
  artifact unpack <pkg>  Extract deployment artifact

Global Options:
  --environment ENV      Target environment (dev|staging|prod)
  --dry-run              Show what would be executed
  --force                Skip confirmation prompts
  --config FILE          Configuration file
  --output FORMAT        Output format (text|json)
  --verbose              Verbose output
  --help                 Show help
  --version              Show version

Examples:
  deploy-runner deploy manifest.yaml --environment staging
  deploy-runner deploy manifest.yaml --environment prod --dry-run
  deploy-runner rollback last --environment prod
  deploy-runner rollback deploy-20260124-143022
  deploy-runner history --count 10
  deploy-runner artifact pack ./release --output myapp-v1.2.3.zip
```

### Data Flow

```
Manifest (YAML/JSON)
        |
        v
Manifest Parser --> Validation --> Step List
                                       |
                    +------------------+
                    |
                    v
            Environment Resolution
                    |
                    v
            Pre-Deploy Snapshot <-- Backup Manager
                    |
                    v
            +---------------+
            | Step Executor |<----+
            +-------+-------+     |
                    |             |
         +----------+----------+  |
         |          |          |  |
         v          v          v  |
      Success    Failure   Timeout|
         |          |          |  |
         |     +----+----+     |  |
         |     | Rollback|     |  |
         |     +---------+     |  |
         |          |          |  |
         +----------+----------+  |
                    |             |
                    v             |
              Next Step?----------+
                    |
                    v
            Post-Deploy Actions
                    |
                    v
            +---------------+
            | History Write |
            | Log Write     |
            | Notify        |
            +---------------+
```

### Manifest Schema (YAML)

```yaml
name: myapp-deployment
version: "1.0"
description: "Deploy MyApp to production"

# Environment-specific configuration
environments:
  dev:
    server: dev-server.local
    app_path: C:\Apps\MyApp
    variables:
      LOG_LEVEL: debug
      API_URL: http://localhost:8080

  staging:
    server: staging.example.com
    app_path: C:\Apps\MyApp
    variables:
      LOG_LEVEL: info
      API_URL: https://api-staging.example.com

  prod:
    server: prod.example.com
    app_path: C:\Apps\MyApp
    requires_approval: true
    variables:
      LOG_LEVEL: warn
      API_URL: https://api.example.com

# Deployment steps (executed in order)
steps:
  - name: backup-current
    command: cmd /c backup.bat
    working_directory: "{{ app_path }}"
    timeout: 300
    on_failure: abort

  - name: stop-service
    command: net stop MyAppService
    continue_on_error: false
    rollback: net start MyAppService

  - name: extract-artifact
    command: 7z x myapp-latest.zip -o"{{ app_path }}" -y
    working_directory: C:\Artifacts
    timeout: 120

  - name: run-migrations
    command: cmd /c migrate.bat
    working_directory: "{{ app_path }}"
    timeout: 600
    on_failure: rollback

  - name: start-service
    command: net start MyAppService
    health_check:
      command: curl -s http://localhost:8080/health
      expected: "ok"
      retries: 5
      delay: 10

  - name: verify-deployment
    command: cmd /c smoke-test.bat
    timeout: 120
    on_failure: rollback

# Rollback steps (executed in reverse on failure)
rollback_steps:
  - name: restore-backup
    command: cmd /c restore.bat
    working_directory: "{{ app_path }}"

  - name: start-service
    command: net start MyAppService

# Notifications
notifications:
  on_start:
    - webhook: https://hooks.slack.com/...
      message: "Deployment starting: {{ name }} to {{ environment }}"
  on_success:
    - webhook: https://hooks.slack.com/...
      message: "Deployment complete: {{ name }} to {{ environment }}"
  on_failure:
    - webhook: https://hooks.slack.com/...
      message: "Deployment FAILED: {{ name }} to {{ environment }}"
```

### Manifest Schema (JSON equivalent)

```json
{
  "name": "myapp-deployment",
  "version": "1.0",
  "description": "Deploy MyApp to production",
  "environments": {
    "prod": {
      "server": "prod.example.com",
      "app_path": "C:\\Apps\\MyApp",
      "requires_approval": true,
      "variables": {
        "LOG_LEVEL": "warn"
      }
    }
  },
  "steps": [
    {
      "name": "stop-service",
      "command": "net stop MyAppService",
      "rollback": "net start MyAppService"
    },
    {
      "name": "deploy-files",
      "command": "robocopy source dest /MIR",
      "timeout": 300
    }
  ]
}
```

### Error Handling

| Error Type | Handling | User Message |
|------------|----------|--------------|
| Manifest not found | Return error code 1 | "Manifest file not found: path" |
| Invalid manifest | Validation errors | "Manifest error: missing required field 'steps'" |
| Step failed | Trigger rollback | "Step 'name' failed (exit=1). Rolling back..." |
| Rollback failed | Log and alert | "CRITICAL: Rollback failed. Manual intervention required." |
| Health check failed | Retry then rollback | "Health check failed after 5 retries. Rolling back..." |
| Timeout exceeded | Kill and rollback | "Step 'name' timed out after 300s. Rolling back..." |
| Approval required | Wait for input | "Production deployment requires approval. Proceed? [y/N]" |
| Network error | Retry with backoff | "Connection failed. Retrying in 5s... (2/3)" |

### State Machine: Deployment Lifecycle

```
                   +----------+
                   |  PENDING |
                   +----+-----+
                        |
                        v
                   +---------+
           +------>| RUNNING |<------+
           |       +----+----+       |
           |            |            |
           |     +------+------+     |
           |     v             v     |
       +---------+         +--------+
       | ROLLING |         | PAUSED |
       |  BACK   |         +--------+
       +----+----+              |
            |                   |
     +------+------+            |
     v             v            |
+---------+   +---------+       |
| FAILED  |   | ROLLED  |       |
| ROLLBACK|   |  BACK   |       |
+---------+   +---------+       |
     |             |            |
     +------+------+            |
            |                   |
            v                   |
       +----------+             |
       | COMPLETE |<------------+
       +----------+
           |
           v
       +--------+
       | LOGGED |
       +--------+
```

## GUI/TUI Future Path

**CLI foundation enables:**
- All deployment operations executable via CLI for CI/CD integration
- JSON output mode for building web dashboards
- Manifest-as-code enables GitOps workflows

**What would change for TUI:**
- Add simple_tui for interactive deployment monitoring
- Real-time step progress with output streaming
- Rollback confirmation dialogs
- Environment selector

**What would change for Web GUI:**
- Add simple_http for REST API
- Deployment dashboard with history
- Real-time WebSocket updates during deployment
- Approval workflow UI

**Shared components between CLI/GUI:**
- DEPLOY_RUNNER_ENGINE (core orchestration)
- DEPLOY_RUNNER_MANIFEST (manifest model)
- DEPLOY_RUNNER_EXECUTOR (step execution)
- DEPLOY_RUNNER_ROLLBACK (rollback logic)
- All business logic in shared library
