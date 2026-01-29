# RunScheduler - Ecosystem Integration

## simple_* Dependencies

### Required Libraries

| Library | Purpose | Integration Point |
|---------|---------|-------------------|
| simple_process | Command execution with output capture | Job execution engine |
| simple_json | Job config and global config parsing | Configuration layer |
| simple_logger | Execution logging with rotation | Logging throughout |
| simple_datetime | Schedule calculation, timestamps | Cron parsing, history |
| simple_cli | Argument parsing, help generation | CLI interface |
| simple_sql | Job history, execution records | Persistence layer |

### Optional Libraries

| Library | Purpose | When Needed |
|---------|---------|-------------|
| simple_smtp | Email notifications | Pro tier with email alerts |
| simple_http | Webhook notifications, REST API | Webhook alerts, Enterprise API |
| simple_config | Environment variable expansion | Advanced config interpolation |
| simple_validation | Job config validation | Extended validation rules |
| simple_archive | Log compression | Log archival feature |
| simple_uuid | Unique job run IDs | Execution tracking |

## Integration Patterns

### simple_process Integration

**Purpose:** Execute scheduled commands and capture output

**Usage:**
```eiffel
class RUN_SCHEDULER_EXECUTOR

feature -- Execution

    execute_job (a_job: RUN_SCHEDULER_JOB): RUN_SCHEDULER_RESULT
            -- Execute job and return result with output
        local
            l_process: SIMPLE_PROCESS
            l_output: STRING_32
            l_start_time: SIMPLE_DATE_TIME
        do
            create l_process.make
            l_process.set_show_window (False)

            create l_start_time.make_now

            if attached a_job.working_directory as wd then
                l_output := l_process.output_of_command_in_directory (
                    a_job.command, wd)
            else
                l_output := l_process.output_of_command (a_job.command)
            end

            create Result.make (
                a_job.name,
                l_process.was_successful,
                l_process.last_exit_code,
                l_output,
                l_start_time
            )
        end
end
```

**Data flow:** Job command -> SIMPLE_PROCESS.output_of_command -> Result capture

### simple_async_process Integration

**Purpose:** Execute jobs with timeout enforcement

**Usage:**
```eiffel
feature -- Execution with Timeout

    execute_with_timeout (a_job: RUN_SCHEDULER_JOB): RUN_SCHEDULER_RESULT
            -- Execute job with timeout, killing if exceeded
        local
            l_async: SIMPLE_ASYNC_PROCESS
            l_finished: BOOLEAN
        do
            create l_async.make
            l_async.set_show_window (False)

            if attached a_job.working_directory as wd then
                l_async.start_in_directory (a_job.command, wd)
            else
                l_async.start (a_job.command)
            end

            if l_async.is_started then
                l_finished := l_async.wait_seconds (a_job.timeout_seconds)

                if not l_finished and l_async.is_running then
                    l_async.kill
                    create Result.make_timeout (a_job.name, a_job.timeout_seconds)
                else
                    create Result.make (
                        a_job.name,
                        l_async.exit_code = 0,
                        l_async.exit_code,
                        l_async.accumulated_output,
                        create {SIMPLE_DATE_TIME}.make_now
                    )
                end

                l_async.close
            else
                create Result.make_failed (a_job.name, l_async.last_error)
            end
        end
```

### simple_json Integration

**Purpose:** Parse and write job configuration files

**Usage:**
```eiffel
class RUN_SCHEDULER_CONFIG

feature -- Loading

    load_job (a_path: PATH): detachable RUN_SCHEDULER_JOB
            -- Load job from JSON file
        local
            l_json: SIMPLE_JSON
            l_content: STRING
        do
            create l_json.make
            l_content := file_content (a_path)

            if l_json.parse (l_content) then
                create Result.make
                Result.set_name (l_json.string_at ("name"))
                Result.set_command (l_json.string_at ("command"))
                Result.set_schedule (l_json.string_at ("schedule"))

                if l_json.has ("timeout_seconds") then
                    Result.set_timeout (l_json.integer_at ("timeout_seconds"))
                end

                if l_json.has ("working_directory") then
                    Result.set_working_directory (
                        l_json.string_at ("working_directory"))
                end

                -- Parse depends_on array
                if attached l_json.array_at ("depends_on") as deps then
                    across deps as dep loop
                        Result.add_dependency (dep.item.string_value)
                    end
                end
            end
        end
```

### simple_logger Integration

**Purpose:** Log job executions, errors, and system events

**Usage:**
```eiffel
class RUN_SCHEDULER_ENGINE

feature {NONE} -- Initialization

    make
        do
            create logger.make_with_file ("run-scheduler.log")
            logger.set_level ({SIMPLE_LOG_LEVEL}.info)
            logger.enable_rotation (10_000_000) -- 10MB
        end

feature -- Execution

    run_job (a_job: RUN_SCHEDULER_JOB)
        do
            logger.info ("Starting job: " + a_job.name)

            if attached executor.execute_with_timeout (a_job) as result then
                if result.was_successful then
                    logger.info ("Job completed: " + a_job.name +
                        " (exit=" + result.exit_code.out + ")")
                else
                    logger.error ("Job failed: " + a_job.name +
                        " (exit=" + result.exit_code.out + ")")
                    logger.error ("Output: " + result.output)
                end

                history.record (result)
                notifier.maybe_notify (a_job, result)
            end
        end

feature {NONE} -- Implementation

    logger: SIMPLE_LOGGER
```

### simple_datetime Integration

**Purpose:** Schedule calculation and execution timestamps

**Usage:**
```eiffel
class RUN_SCHEDULER_CRON

feature -- Queries

    next_run_time (a_cron_expr: STRING; a_from: SIMPLE_DATE_TIME): SIMPLE_DATE_TIME
            -- Calculate next run time from cron expression
        local
            l_candidate: SIMPLE_DATE_TIME
        do
            l_candidate := a_from.plus_minutes (1)

            from until matches_cron (a_cron_expr, l_candidate) loop
                l_candidate := l_candidate.plus_minutes (1)
            end

            Result := l_candidate
        end

    matches_cron (a_expr: STRING; a_time: SIMPLE_DATE_TIME): BOOLEAN
            -- Does time match cron expression?
        do
            -- Parse "minute hour day month weekday"
            Result := matches_field (minute_field (a_expr), a_time.minute) and
                matches_field (hour_field (a_expr), a_time.hour) and
                matches_field (day_field (a_expr), a_time.day) and
                matches_field (month_field (a_expr), a_time.month) and
                matches_field (weekday_field (a_expr), a_time.day_of_week)
        end
```

### simple_sql Integration

**Purpose:** Store job execution history

**Usage:**
```eiffel
class RUN_SCHEDULER_HISTORY

feature {NONE} -- Initialization

    make (a_db_path: STRING)
        do
            create db.make (a_db_path)
            ensure_schema
        end

    ensure_schema
        do
            db.execute ("
                CREATE TABLE IF NOT EXISTS job_runs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    job_name TEXT NOT NULL,
                    start_time TEXT NOT NULL,
                    end_time TEXT NOT NULL,
                    exit_code INTEGER NOT NULL,
                    success INTEGER NOT NULL,
                    output TEXT,
                    error_message TEXT
                )
            ")
            db.execute ("CREATE INDEX IF NOT EXISTS idx_job_name ON job_runs(job_name)")
            db.execute ("CREATE INDEX IF NOT EXISTS idx_start_time ON job_runs(start_time)")
        end

feature -- Recording

    record (a_result: RUN_SCHEDULER_RESULT)
        do
            db.execute_with_params ("
                INSERT INTO job_runs (job_name, start_time, end_time,
                    exit_code, success, output)
                VALUES (?, ?, ?, ?, ?, ?)
            ", <<a_result.job_name, a_result.start_time.to_iso8601,
                a_result.end_time.to_iso8601, a_result.exit_code,
                a_result.was_successful.to_integer, a_result.output>>)
        end

feature {NONE} -- Implementation

    db: SIMPLE_SQL
```

### simple_smtp Integration (Pro Tier)

**Purpose:** Send email notifications on job success/failure

**Usage:**
```eiffel
class RUN_SCHEDULER_NOTIFIER

feature -- Notification

    notify_failure (a_job: RUN_SCHEDULER_JOB; a_result: RUN_SCHEDULER_RESULT)
        local
            l_smtp: SIMPLE_SMTP
            l_body: STRING
        do
            if config.email_enabled and a_job.notify_on_failure then
                create l_smtp.make (config.smtp_host, config.smtp_port)
                l_smtp.set_credentials (config.smtp_user, config.smtp_password)

                l_body := "Job '" + a_job.name + "' failed.%N%N"
                l_body.append ("Exit code: " + a_result.exit_code.out + "%N")
                l_body.append ("Output:%N" + a_result.output)

                l_smtp.send (
                    config.from_email,
                    config.to_emails,
                    "RunScheduler: Job '" + a_job.name + "' FAILED",
                    l_body
                )
            end
        end
```

## Dependency Graph

```
run_scheduler
    |
    +-- simple_process (required)
    |       +-- simple_datetime
    |
    +-- simple_json (required)
    |
    +-- simple_logger (required)
    |
    +-- simple_datetime (required)
    |
    +-- simple_cli (required)
    |
    +-- simple_sql (required)
    |       +-- simple_file
    |
    +-- simple_smtp (optional - Pro)
    |
    +-- simple_http (optional - Enterprise)
    |
    +-- simple_config (optional)
    |
    +-- simple_uuid (optional)
    |
    +-- ISE base (required)
```

## ECF Configuration

```xml
<?xml version="1.0" encoding="utf-8"?>
<system name="run_scheduler" uuid="A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        xmlns="http://www.eiffel.com/developers/xml/configuration-1-23-0">
    <description>RunScheduler - Modern job scheduler for Windows</description>

    <target name="run_scheduler">
        <root class="RUN_SCHEDULER_CLI" feature="make"/>
        <version major="1" minor="0" release="0" build="1"/>

        <file_rule>
            <exclude>/EIFGENs$</exclude>
            <exclude>/\.git$</exclude>
        </file_rule>

        <option warning="warning" manifest_array_type="mismatch_warning">
            <assertions precondition="true" postcondition="true"
                        check="true" invariant="true"/>
        </option>

        <setting name="console_application" value="true"/>
        <setting name="concurrency" value="scoop"/>
        <setting name="dead_code_removal" value="feature"/>

        <capability>
            <concurrency support="scoop"/>
            <void_safety support="all"/>
        </capability>

        <!-- simple_* dependencies -->
        <library name="simple_process"
                 location="$SIMPLE_EIFFEL/simple_process/simple_process.ecf"/>
        <library name="simple_json"
                 location="$SIMPLE_EIFFEL/simple_json/simple_json.ecf"/>
        <library name="simple_logger"
                 location="$SIMPLE_EIFFEL/simple_logger/simple_logger.ecf"/>
        <library name="simple_datetime"
                 location="$SIMPLE_EIFFEL/simple_datetime/simple_datetime.ecf"/>
        <library name="simple_cli"
                 location="$SIMPLE_EIFFEL/simple_cli/simple_cli.ecf"/>
        <library name="simple_sql"
                 location="$SIMPLE_EIFFEL/simple_sql/simple_sql.ecf"/>

        <!-- Optional: Pro tier -->
        <library name="simple_smtp"
                 location="$SIMPLE_EIFFEL/simple_smtp/simple_smtp.ecf"
                 readonly="false">
            <condition>
                <custom name="run_scheduler_pro" value="true"/>
            </condition>
        </library>

        <!-- Optional: Enterprise tier -->
        <library name="simple_http"
                 location="$SIMPLE_EIFFEL/simple_http/simple_http.ecf"
                 readonly="false">
            <condition>
                <custom name="run_scheduler_enterprise" value="true"/>
            </condition>
        </library>

        <!-- ISE dependencies (only when no simple_* alternative) -->
        <library name="base" location="$ISE_LIBRARY/library/base/base.ecf"/>
        <library name="time" location="$ISE_LIBRARY/library/time/time.ecf"/>

        <!-- Application source -->
        <cluster name="src" location=".\src\" recursive="true"/>
    </target>

    <target name="run_scheduler_tests" extends="run_scheduler">
        <root class="TEST_APP" feature="make"/>
        <library name="simple_testing"
                 location="$SIMPLE_EIFFEL/simple_testing/simple_testing.ecf"/>
        <cluster name="tests" location=".\tests\" recursive="true"/>
    </target>
</system>
```
