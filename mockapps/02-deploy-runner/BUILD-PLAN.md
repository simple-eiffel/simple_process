# DeployRunner - Build Plan

## Phase Overview

| Phase | Deliverable | Effort | Dependencies |
|-------|-------------|--------|--------------|
| Phase 1 | MVP CLI | 5 days | simple_process, simple_yaml, simple_logger |
| Phase 2 | Full Deployment + Rollback | 5 days | Phase 1 + simple_sql, simple_file |
| Phase 3 | Pro Features | 4 days | Phase 2 + simple_http, simple_archive |
| Phase 4 | Polish & Release | 3 days | Phase 3 complete |

**Total Estimated Effort:** 17 days

---

## Phase 1: MVP

### Objective

Demonstrate core deployment capability: parse YAML manifest, execute steps in sequence, log output, and fail gracefully on errors. Must successfully deploy a simple application with multiple steps.

### Deliverables

1. **DEPLOY_RUNNER_CLI** - Main CLI entry point
2. **DEPLOY_RUNNER_MANIFEST** - Manifest model class
3. **DEPLOY_RUNNER_STEP** - Step definition model
4. **DEPLOY_RUNNER_MANIFEST_LOADER** - YAML parser
5. **DEPLOY_RUNNER_EXECUTOR** - Step execution engine
6. **DEPLOY_RUNNER_ENGINE** - Orchestration coordinator
7. **Basic CLI** - `deploy`, `validate`, `init` commands

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T1.1 | Create project structure and ECF | Compiles with required libraries |
| T1.2 | Implement DEPLOY_RUNNER_MANIFEST | Model with name, steps, environments |
| T1.3 | Implement DEPLOY_RUNNER_STEP | Model with command, timeout, on_failure |
| T1.4 | Implement YAML manifest loader | Parse minimal manifest with steps |
| T1.5 | Implement DEPLOY_RUNNER_EXECUTOR | Execute step via simple_process |
| T1.6 | Implement DEPLOY_RUNNER_ENGINE | Sequence steps, handle failures |
| T1.7 | Implement basic CLI | deploy, validate, init commands |
| T1.8 | Add environment support | Select environment, resolve variables |
| T1.9 | Add logging integration | Log all steps and outcomes |
| T1.10 | Write MVP tests | Test manifest loading, execution |

### Test Cases

| Test | Input | Expected Output |
|------|-------|-----------------|
| Load valid manifest | Valid YAML with 3 steps | Manifest with 3 steps |
| Load invalid manifest | Missing 'steps' key | Validation error |
| Execute simple step | `echo hello` | Exit code 0, output "hello" |
| Execute failing step | `exit 1` | Exit code 1, deployment fails |
| Variable substitution | `{{ app_path }}` | Resolved to environment value |
| Validate command | Valid manifest | "Manifest is valid" |
| Init command | No arguments | Template manifest created |

### MVP Success Criteria

- [ ] `deploy-runner init` creates template manifest
- [ ] `deploy-runner validate manifest.yaml` validates
- [ ] `deploy-runner deploy manifest.yaml --env dev` executes
- [ ] Steps execute in sequence
- [ ] Failure stops deployment
- [ ] All actions logged to file

---

## Phase 2: Full Implementation

### Objective

Add rollback capability, deployment history (SQLite), timeout handling, health checks, and complete CLI commands.

### Deliverables

1. **DEPLOY_RUNNER_ROLLBACK** - Rollback coordinator
2. **DEPLOY_RUNNER_HISTORY** - SQLite-backed history
3. **DEPLOY_RUNNER_ENVIRONMENT** - Full environment management
4. **Timeout support** - Kill hung steps
5. **Health checks** - Verify step success with command
6. **Complete CLI** - rollback, status, history, diff commands

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T2.1 | Implement DEPLOY_RUNNER_ROLLBACK | Execute rollback steps in reverse |
| T2.2 | Add per-step rollback commands | Step-level rollback on failure |
| T2.3 | Implement DEPLOY_RUNNER_HISTORY | SQLite schema, record deployments |
| T2.4 | Add timeout handling | Use simple_async_process |
| T2.5 | Implement health checks | Post-step verification commands |
| T2.6 | Add --dry-run mode | Show what would execute |
| T2.7 | Implement status command | Current deployment state |
| T2.8 | Implement history command | Query past deployments |
| T2.9 | Implement rollback command | Rollback to named deployment |
| T2.10 | Implement diff command | Compare environments |
| T2.11 | Add --force flag | Skip confirmation prompts |
| T2.12 | Write comprehensive tests | Test rollback, history |

### Rollback Behavior

```
Step 1: success
Step 2: success
Step 3: FAILURE
  -> Execute Step 3 rollback (if defined)
  -> Execute Step 2 rollback
  -> Execute Step 1 rollback
  -> Mark deployment as "rolled_back"
```

---

## Phase 3: Pro Features

### Objective

Add artifact management, webhook notifications, and prepare for Enterprise features.

### Deliverables

1. **DEPLOY_RUNNER_ARTIFACT** - Pack/unpack deployment artifacts
2. **DEPLOY_RUNNER_NOTIFIER** - Webhook notifications
3. **File backup/restore** - Snapshot before deployment
4. **CI/CD integration examples** - Jenkins, GitHub Actions

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T3.1 | Implement DEPLOY_RUNNER_ARTIFACT | Create/extract zip artifacts |
| T3.2 | Add artifact pack command | `artifact pack ./release` |
| T3.3 | Add artifact unpack command | `artifact unpack pkg.zip` |
| T3.4 | Implement DEPLOY_RUNNER_NOTIFIER | Webhook POST on events |
| T3.5 | Add notification config | Per-manifest notification settings |
| T3.6 | Implement file backup | Snapshot target directory |
| T3.7 | Implement file restore | Restore from snapshot |
| T3.8 | Add Pro license check | Feature gating |
| T3.9 | Create CI/CD examples | Jenkins, GitHub, GitLab |
| T3.10 | Write notification tests | Test webhook dispatch |

---

## Phase 4: Production Polish

### Objective

Error handling hardening, documentation, packaging, and final testing.

### Deliverables

1. **Error handling** - All edge cases covered
2. **Help documentation** - `--help` for all commands
3. **README.md** - Installation and usage guide
4. **Example manifests** - Real-world deployment examples
5. **Installer** - INNO Setup package

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T4.1 | Error handling review | Graceful handling of all errors |
| T4.2 | Add comprehensive --help | Every command has detailed help |
| T4.3 | Performance testing | Deploy 50-step manifest <5s |
| T4.4 | Write README.md | Installation, configuration, usage |
| T4.5 | Create example manifests | IIS, .NET, Node.js deployments |
| T4.6 | Create INNO installer | Single-file Windows installer |
| T4.7 | Final integration tests | End-to-end scenario testing |
| T4.8 | Code review and cleanup | Consistent style, no debug code |

---

## ECF Target Structure

```xml
<!-- Library target (reusable by other apps) -->
<target name="deploy_runner_lib">
    <root all_classes="true" />
    <!-- All dependencies and clusters except CLI -->
</target>

<!-- CLI executable target -->
<target name="deploy_runner" extends="deploy_runner_lib">
    <root class="DEPLOY_RUNNER_CLI" feature="make"/>
    <cluster name="cli" location=".\src\cli\"/>
</target>

<!-- Test target -->
<target name="deploy_runner_tests" extends="deploy_runner_lib">
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
ec.exe -batch -config deploy_runner.ecf -target deploy_runner -c_compile

# Compile CLI (production)
ec.exe -batch -config deploy_runner.ecf -target deploy_runner -finalize -c_compile

# Run tests
ec.exe -batch -config deploy_runner.ecf -target deploy_runner_tests -c_compile
./EIFGENs/deploy_runner_tests/W_code/deploy_runner.exe

# Run finalized tests
ec.exe -batch -config deploy_runner.ecf -target deploy_runner_tests -finalize -c_compile
./EIFGENs/deploy_runner_tests/F_code/deploy_runner.exe
```

---

## Success Criteria

| Criterion | Measure | Target |
|-----------|---------|--------|
| Compiles | Zero errors, zero warnings | 100% |
| Tests pass | All test cases | 100% |
| CLI works | All commands functional | Pass |
| Rollback | Automatic on step failure | Works |
| Performance | 50-step manifest | <5s |
| Documentation | README complete | Yes |
| Examples | 3+ real-world manifests | Yes |

---

## Directory Structure

```
deploy_runner/
├── deploy_runner.ecf
├── README.md
├── CHANGELOG.md
├── LICENSE
├── src/
│   ├── cli/
│   │   └── deploy_runner_cli.e
│   ├── engine/
│   │   ├── deploy_runner_engine.e
│   │   ├── deploy_runner_executor.e
│   │   └── deploy_runner_rollback.e
│   ├── model/
│   │   ├── deploy_runner_manifest.e
│   │   ├── deploy_runner_step.e
│   │   ├── deploy_runner_environment.e
│   │   └── deploy_step_result.e
│   ├── loader/
│   │   └── deploy_runner_manifest_loader.e
│   ├── persistence/
│   │   └── deploy_runner_history.e
│   ├── artifact/
│   │   └── deploy_runner_artifact.e
│   └── notification/
│       └── deploy_runner_notifier.e
├── tests/
│   ├── test_app.e
│   ├── test_manifest.e
│   ├── test_executor.e
│   ├── test_rollback.e
│   └── test_history.e
├── examples/
│   ├── iis-deploy.yaml
│   ├── dotnet-deploy.yaml
│   ├── nodejs-deploy.yaml
│   └── simple-deploy.yaml
└── installer/
    └── deploy_runner.iss
```

---

## Example Manifest: Simple .NET Deployment

```yaml
name: myapp-deploy
version: "1.0"
description: "Deploy MyApp to IIS"

environments:
  staging:
    app_path: C:\inetpub\wwwroot\myapp
    pool_name: MyAppPool
    service_url: http://localhost:8080

  prod:
    app_path: C:\inetpub\wwwroot\myapp
    pool_name: MyAppPool
    service_url: http://localhost:80
    requires_approval: true

steps:
  - name: backup
    command: robocopy "{{ app_path }}" "{{ app_path }}.backup" /MIR /NFL /NDL
    timeout: 300

  - name: stop-pool
    command: cmd /c "%windir%\system32\inetsrv\appcmd.exe" stop apppool /apppool.name:{{ pool_name }}
    rollback: cmd /c "%windir%\system32\inetsrv\appcmd.exe" start apppool /apppool.name:{{ pool_name }}

  - name: deploy-files
    command: robocopy artifacts "{{ app_path }}" /MIR /NFL /NDL /XD logs
    timeout: 120
    on_failure: rollback

  - name: start-pool
    command: cmd /c "%windir%\system32\inetsrv\appcmd.exe" start apppool /apppool.name:{{ pool_name }}

  - name: health-check
    command: curl -s "{{ service_url }}/health"
    health_check:
      expected: "healthy"
      retries: 5
      delay: 5
    on_failure: rollback

rollback_steps:
  - name: restore-backup
    command: robocopy "{{ app_path }}.backup" "{{ app_path }}" /MIR /NFL /NDL

  - name: start-pool
    command: cmd /c "%windir%\system32\inetsrv\appcmd.exe" start apppool /apppool.name:{{ pool_name }}
```
