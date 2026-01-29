# RunScheduler - Build Plan

## Phase Overview

| Phase | Deliverable | Effort | Dependencies |
|-------|-------------|--------|--------------|
| Phase 1 | MVP CLI | 5 days | simple_process, simple_json, simple_logger |
| Phase 2 | Full CLI + History | 4 days | Phase 1 + simple_sql, simple_datetime |
| Phase 3 | Pro Features | 3 days | Phase 2 + simple_smtp, simple_http |
| Phase 4 | Polish & Release | 3 days | Phase 3 complete |

**Total Estimated Effort:** 15 days

---

## Phase 1: MVP

### Objective

Demonstrate core scheduling capability: load jobs from JSON, execute on schedule, log output. Must be able to run as foreground daemon and execute at least one scheduled job successfully.

### Deliverables

1. **RUN_SCHEDULER_CLI** - Main CLI entry point with basic commands
2. **RUN_SCHEDULER_JOB** - Job definition model class
3. **RUN_SCHEDULER_CONFIG** - JSON configuration loader
4. **RUN_SCHEDULER_EXECUTOR** - Process execution wrapper
5. **RUN_SCHEDULER_ENGINE** - Basic scheduler loop
6. **Basic CLI** - `add`, `list`, `run`, `daemon` commands

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T1.1 | Create project structure and ECF | Compiles with simple_process, simple_json, simple_logger |
| T1.2 | Implement RUN_SCHEDULER_JOB | Model class with name, command, schedule, timeout |
| T1.3 | Implement RUN_SCHEDULER_CONFIG | Load job from JSON file, validate required fields |
| T1.4 | Implement RUN_SCHEDULER_EXECUTOR | Execute job via simple_process, capture output |
| T1.5 | Implement basic CLI parsing | Parse add/list/run/daemon commands |
| T1.6 | Implement RUN_SCHEDULER_ENGINE | Main loop checking schedule every minute |
| T1.7 | Implement cron expression parser | Parse "* * * * *" format, calculate next run |
| T1.8 | Add logging integration | Log job start/complete/fail to file |
| T1.9 | Write MVP tests | Test job loading, execution, cron parsing |

### Test Cases

| Test | Input | Expected Output |
|------|-------|-----------------|
| Load valid job | `{"name":"test","command":"echo hello","schedule":"* * * * *"}` | Job object with correct fields |
| Load invalid job | `{"name":"test"}` (missing command) | Validation error |
| Execute simple command | `echo hello` | Output "hello", exit code 0 |
| Parse cron wildcard | `* * * * *` | Matches any time |
| Parse cron specific | `30 14 * * *` | Matches 14:30 only |
| List empty | No jobs registered | "No jobs scheduled" |
| Add and list | Add job, then list | Job appears in list |

### MVP Success Criteria

- [ ] `run-scheduler add job.json` loads a job
- [ ] `run-scheduler list` shows loaded jobs
- [ ] `run-scheduler run jobname` executes immediately
- [ ] `run-scheduler daemon` runs scheduler loop
- [ ] Jobs execute at scheduled times
- [ ] Output logged to file

---

## Phase 2: Full Implementation

### Objective

Add persistence (job history in SQLite), proper cron expression support, job dependencies, timeout handling, and complete CLI.

### Deliverables

1. **RUN_SCHEDULER_HISTORY** - SQLite-backed execution history
2. **RUN_SCHEDULER_CRON** - Full cron expression parser
3. **Enhanced RUN_SCHEDULER_JOB** - Dependencies, retry, environment
4. **Timeout support** - Kill hung jobs via simple_async_process
5. **Complete CLI** - All commands: remove, status, history, validate

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T2.1 | Implement RUN_SCHEDULER_HISTORY | Create SQLite schema, record/query runs |
| T2.2 | Enhance cron parser | Support ranges (1-5), lists (1,3,5), steps (*/5) |
| T2.3 | Add job dependencies | depends_on field, skip if dependency failed |
| T2.4 | Implement timeout handling | Use simple_async_process, kill on timeout |
| T2.5 | Add retry logic | Retry failed jobs with delay |
| T2.6 | Add environment variables | Set env before execution |
| T2.7 | Implement status command | Show next run time, last run result |
| T2.8 | Implement history command | Query and display past runs |
| T2.9 | Implement validate command | Check JSON without adding |
| T2.10 | Implement remove command | Remove job by name |
| T2.11 | Add JSON output mode | --output json for all commands |
| T2.12 | Write comprehensive tests | Test all new features |

### Tasks Detail

**T2.2 - Enhanced Cron Parser:**
- `0 */2 * * *` - Every 2 hours
- `0 9-17 * * 1-5` - 9am-5pm weekdays
- `0 0 1,15 * *` - 1st and 15th of month

**T2.4 - Timeout Handling:**
```eiffel
-- Use SIMPLE_ASYNC_PROCESS for timeout capability
if not async.wait_seconds (job.timeout) then
    async.kill
    result.set_timed_out (True)
end
```

---

## Phase 3: Pro Features

### Objective

Add notification system (email, webhooks) for Pro tier. Prepare for Enterprise features.

### Deliverables

1. **RUN_SCHEDULER_NOTIFIER** - Notification dispatch engine
2. **Email notifications** - Via simple_smtp
3. **Webhook notifications** - Via simple_http
4. **Job chaining** - Run job B after job A succeeds
5. **Log export** - Export history to CSV/JSON

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T3.1 | Implement RUN_SCHEDULER_NOTIFIER | Dispatch to configured channels |
| T3.2 | Add email support | Send via simple_smtp on success/failure |
| T3.3 | Add webhook support | POST to URL via simple_http |
| T3.4 | Implement job chains | Execute dependent jobs on success |
| T3.5 | Add notification config | Per-job notification settings |
| T3.6 | Implement log export | `history export --format csv` |
| T3.7 | Add Pro license check | Feature gating for Pro features |
| T3.8 | Write notification tests | Test email/webhook dispatch |

---

## Phase 4: Production Polish

### Objective

Windows service support, documentation, packaging, and final testing.

### Deliverables

1. **RUN_SCHEDULER_SERVICE** - Windows service wrapper
2. **Error handling hardening** - All edge cases covered
3. **Help documentation** - `--help` for all commands
4. **README.md** - Installation and usage guide
5. **Installer** - INNO Setup package

### Tasks

| Task | Description | Acceptance Criteria |
|------|-------------|---------------------|
| T4.1 | Implement Windows service | install/uninstall/start/stop |
| T4.2 | Add comprehensive --help | Every command has detailed help |
| T4.3 | Error handling review | Graceful handling of all errors |
| T4.4 | Performance testing | Handle 100+ jobs without lag |
| T4.5 | Write README.md | Installation, configuration, usage |
| T4.6 | Create INNO installer | Single-file Windows installer |
| T4.7 | Final integration tests | End-to-end scenario testing |
| T4.8 | Code review and cleanup | Remove debug code, consistent style |

---

## ECF Target Structure

```xml
<!-- Library target (reusable by other apps) -->
<target name="run_scheduler_lib">
    <root all_classes="true" />
    <!-- All dependencies and clusters except CLI -->
</target>

<!-- CLI executable target -->
<target name="run_scheduler" extends="run_scheduler_lib">
    <root class="RUN_SCHEDULER_CLI" feature="make"/>
    <cluster name="cli" location=".\src\cli\"/>
</target>

<!-- Test target -->
<target name="run_scheduler_tests" extends="run_scheduler_lib">
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
ec.exe -batch -config run_scheduler.ecf -target run_scheduler -c_compile

# Compile CLI (production)
ec.exe -batch -config run_scheduler.ecf -target run_scheduler -finalize -c_compile

# Run tests
ec.exe -batch -config run_scheduler.ecf -target run_scheduler_tests -c_compile
./EIFGENs/run_scheduler_tests/W_code/run_scheduler.exe

# Run finalized tests
ec.exe -batch -config run_scheduler.ecf -target run_scheduler_tests -finalize -c_compile
./EIFGENs/run_scheduler_tests/F_code/run_scheduler.exe
```

---

## Success Criteria

| Criterion | Measure | Target |
|-----------|---------|--------|
| Compiles | Zero errors, zero warnings | 100% |
| Tests pass | All test cases | 100% |
| CLI works | All commands functional | Pass |
| Performance | List 100 jobs | <100ms |
| Service | Install/start/stop | Works |
| Documentation | README complete | Yes |
| Packaging | INNO installer | Builds |

---

## Directory Structure

```
run_scheduler/
├── run_scheduler.ecf
├── README.md
├── CHANGELOG.md
├── LICENSE
├── Clib/                    # Any C dependencies
├── src/
│   ├── cli/
│   │   └── run_scheduler_cli.e
│   ├── engine/
│   │   ├── run_scheduler_engine.e
│   │   ├── run_scheduler_cron.e
│   │   └── run_scheduler_executor.e
│   ├── model/
│   │   ├── run_scheduler_job.e
│   │   └── run_scheduler_result.e
│   ├── config/
│   │   └── run_scheduler_config.e
│   ├── persistence/
│   │   └── run_scheduler_history.e
│   ├── notification/
│   │   └── run_scheduler_notifier.e
│   └── service/
│       └── run_scheduler_service.e
├── tests/
│   ├── test_app.e
│   ├── test_job.e
│   ├── test_cron.e
│   ├── test_executor.e
│   └── test_history.e
├── examples/
│   ├── backup-job.json
│   ├── cleanup-job.json
│   └── config.json
└── installer/
    └── run_scheduler.iss
```
