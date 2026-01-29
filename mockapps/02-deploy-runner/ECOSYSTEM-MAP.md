# DeployRunner - Ecosystem Integration

## simple_* Dependencies

### Required Libraries

| Library | Purpose | Integration Point |
|---------|---------|-------------------|
| simple_process | Script/command execution with output capture | Step executor |
| simple_json | JSON manifest parsing | Configuration layer |
| simple_yaml | YAML manifest parsing (preferred format) | Configuration layer |
| simple_logger | Deployment audit logging | Throughout application |
| simple_datetime | Timestamps, duration tracking | History, logging |
| simple_cli | Argument parsing, help generation | CLI interface |
| simple_sql | Deployment history database | Persistence layer |

### Optional Libraries

| Library | Purpose | When Needed |
|---------|---------|-------------|
| simple_archive | Artifact packaging/extraction | Artifact management |
| simple_http | Webhook notifications, REST API | Notifications, Enterprise |
| simple_config | Environment variable expansion | Advanced config |
| simple_file | File operations, backups | Snapshot management |
| simple_validation | Manifest validation | Extended validation |
| simple_uuid | Unique deployment IDs | Tracking |
| simple_template | Variable interpolation | Manifest templating |

## Integration Patterns

### simple_process Integration

**Purpose:** Execute deployment steps and capture output

**Usage:**
```eiffel
class DEPLOY_RUNNER_EXECUTOR

feature -- Execution

    execute_step (a_step: DEPLOY_RUNNER_STEP; a_env: DEPLOY_RUNNER_ENVIRONMENT): DEPLOY_STEP_RESULT
            -- Execute deployment step and return result
        local
            l_process: SIMPLE_PROCESS
            l_command: STRING_32
            l_output: STRING_32
            l_start: SIMPLE_DATE_TIME
        do
            create l_process.make
            l_process.set_show_window (False)

            -- Resolve variables in command
            l_command := a_env.resolve_variables (a_step.command)

            create l_start.make_now
            logger.info ("Executing step: " + a_step.name)
            logger.info ("Command: " + l_command)

            if attached a_step.working_directory as wd then
                l_output := l_process.output_of_command_in_directory (
                    l_command, a_env.resolve_variables (wd))
            else
                l_output := l_process.output_of_command (l_command)
            end

            create Result.make (
                a_step.name,
                l_process.was_successful,
                l_process.last_exit_code,
                l_output,
                l_start,
                create {SIMPLE_DATE_TIME}.make_now
            )

            logger.info ("Step completed: " + a_step.name +
                " (exit=" + Result.exit_code.out +
                ", duration=" + Result.duration_seconds.out + "s)")

            if not Result.was_successful then
                logger.error ("Step output: " + l_output)
            end
        end

feature {NONE} -- Implementation

    logger: SIMPLE_LOGGER
```

### simple_async_process Integration

**Purpose:** Execute steps with timeout enforcement

**Usage:**
```eiffel
feature -- Execution with Timeout

    execute_step_with_timeout (a_step: DEPLOY_RUNNER_STEP;
            a_env: DEPLOY_RUNNER_ENVIRONMENT): DEPLOY_STEP_RESULT
            -- Execute step with timeout, killing if exceeded
        local
            l_async: SIMPLE_ASYNC_PROCESS
            l_command: STRING_32
            l_finished: BOOLEAN
        do
            create l_async.make
            l_async.set_show_window (False)

            l_command := a_env.resolve_variables (a_step.command)

            logger.info ("Executing step with timeout: " + a_step.name +
                " (" + a_step.timeout_seconds.out + "s)")

            if attached a_step.working_directory as wd then
                l_async.start_in_directory (l_command, a_env.resolve_variables (wd))
            else
                l_async.start (l_command)
            end

            if l_async.is_started then
                -- Poll for completion with output streaming
                from
                until not l_async.is_running or l_async.elapsed_seconds > a_step.timeout_seconds
                loop
                    if attached l_async.read_available_output as chunk then
                        logger.debug (chunk)
                    end
                    sleep_ms (100)
                end

                if l_async.is_running then
                    logger.error ("Step timed out after " +
                        a_step.timeout_seconds.out + "s, killing process")
                    l_async.kill
                    create Result.make_timeout (a_step.name, a_step.timeout_seconds)
                else
                    create Result.make (
                        a_step.name,
                        l_async.exit_code = 0,
                        l_async.exit_code,
                        l_async.accumulated_output,
                        start_time,
                        create {SIMPLE_DATE_TIME}.make_now
                    )
                end

                l_async.close
            else
                create Result.make_failed (a_step.name, l_async.last_error)
            end
        end
```

### simple_yaml Integration

**Purpose:** Parse YAML deployment manifests

**Usage:**
```eiffel
class DEPLOY_RUNNER_MANIFEST_LOADER

feature -- Loading

    load_yaml (a_path: PATH): detachable DEPLOY_RUNNER_MANIFEST
            -- Load manifest from YAML file
        local
            l_yaml: SIMPLE_YAML
            l_content: STRING
        do
            create l_yaml.make
            l_content := file_content (a_path)

            if l_yaml.parse (l_content) then
                create Result.make

                Result.set_name (l_yaml.string_at ("name"))
                Result.set_version (l_yaml.string_at ("version"))
                Result.set_description (l_yaml.string_at ("description"))

                -- Load environments
                if attached l_yaml.object_at ("environments") as envs then
                    across envs.keys as env_name loop
                        Result.add_environment (
                            load_environment (env_name.item, envs.object_at (env_name.item)))
                    end
                end

                -- Load steps
                if attached l_yaml.array_at ("steps") as steps then
                    across steps as step loop
                        Result.add_step (load_step (step.item))
                    end
                end

                -- Load rollback steps
                if attached l_yaml.array_at ("rollback_steps") as rb_steps then
                    across rb_steps as step loop
                        Result.add_rollback_step (load_step (step.item))
                    end
                end
            end
        end

    load_step (a_yaml: SIMPLE_YAML_NODE): DEPLOY_RUNNER_STEP
        do
            create Result.make
            Result.set_name (a_yaml.string_at ("name"))
            Result.set_command (a_yaml.string_at ("command"))

            if a_yaml.has ("working_directory") then
                Result.set_working_directory (a_yaml.string_at ("working_directory"))
            end

            if a_yaml.has ("timeout") then
                Result.set_timeout (a_yaml.integer_at ("timeout"))
            end

            if a_yaml.has ("rollback") then
                Result.set_rollback_command (a_yaml.string_at ("rollback"))
            end

            if a_yaml.has ("continue_on_error") then
                Result.set_continue_on_error (a_yaml.boolean_at ("continue_on_error"))
            end
        end
```

### simple_archive Integration

**Purpose:** Create and extract deployment artifacts

**Usage:**
```eiffel
class DEPLOY_RUNNER_ARTIFACT

feature -- Packaging

    pack (a_source_dir: PATH; a_output: PATH): BOOLEAN
            -- Create deployment artifact from directory
        local
            l_archive: SIMPLE_ARCHIVE
        do
            create l_archive.make
            logger.info ("Creating artifact: " + a_output.name.out)

            Result := l_archive.create_zip (a_source_dir, a_output)

            if Result then
                logger.info ("Artifact created: " +
                    l_archive.last_size_bytes.out + " bytes")
            else
                logger.error ("Failed to create artifact: " + l_archive.last_error)
            end
        end

    unpack (a_artifact: PATH; a_target_dir: PATH): BOOLEAN
            -- Extract deployment artifact
        local
            l_archive: SIMPLE_ARCHIVE
        do
            create l_archive.make
            logger.info ("Extracting artifact: " + a_artifact.name.out +
                " to " + a_target_dir.out)

            Result := l_archive.extract_zip (a_artifact, a_target_dir)

            if Result then
                logger.info ("Artifact extracted: " +
                    l_archive.last_file_count.out + " files")
            else
                logger.error ("Failed to extract artifact: " + l_archive.last_error)
            end
        end
```

### simple_sql Integration

**Purpose:** Store deployment history for audit

**Usage:**
```eiffel
class DEPLOY_RUNNER_HISTORY

feature {NONE} -- Initialization

    make (a_db_path: STRING)
        do
            create db.make (a_db_path)
            ensure_schema
        end

    ensure_schema
        do
            db.execute ("
                CREATE TABLE IF NOT EXISTS deployments (
                    id TEXT PRIMARY KEY,
                    manifest_name TEXT NOT NULL,
                    environment TEXT NOT NULL,
                    start_time TEXT NOT NULL,
                    end_time TEXT,
                    status TEXT NOT NULL,
                    steps_completed INTEGER DEFAULT 0,
                    steps_total INTEGER NOT NULL,
                    triggered_by TEXT,
                    rollback_of TEXT
                )
            ")
            db.execute ("
                CREATE TABLE IF NOT EXISTS deployment_steps (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    deployment_id TEXT NOT NULL,
                    step_name TEXT NOT NULL,
                    start_time TEXT NOT NULL,
                    end_time TEXT,
                    exit_code INTEGER,
                    status TEXT NOT NULL,
                    output TEXT,
                    FOREIGN KEY (deployment_id) REFERENCES deployments(id)
                )
            ")
        end

feature -- Recording

    start_deployment (a_manifest: DEPLOY_RUNNER_MANIFEST;
            a_env: STRING; a_triggered_by: STRING): STRING
            -- Record deployment start, return deployment ID
        local
            l_id: STRING
        do
            l_id := generate_deployment_id
            db.execute_with_params ("
                INSERT INTO deployments (id, manifest_name, environment,
                    start_time, status, steps_total, triggered_by)
                VALUES (?, ?, ?, ?, 'running', ?, ?)
            ", <<l_id, a_manifest.name, a_env,
                create {SIMPLE_DATE_TIME}.make_now.to_iso8601,
                a_manifest.steps.count, a_triggered_by>>)
            Result := l_id
        end

    complete_deployment (a_id: STRING; a_status: STRING)
        do
            db.execute_with_params ("
                UPDATE deployments SET end_time = ?, status = ?
                WHERE id = ?
            ", <<create {SIMPLE_DATE_TIME}.make_now.to_iso8601, a_status, a_id>>)
        end
```

### simple_http Integration (Pro/Enterprise)

**Purpose:** Send webhook notifications

**Usage:**
```eiffel
class DEPLOY_RUNNER_NOTIFIER

feature -- Notification

    notify_webhook (a_url: STRING; a_message: STRING)
            -- Send webhook notification
        local
            l_http: SIMPLE_HTTP
            l_body: STRING
        do
            create l_http.make
            l_http.set_header ("Content-Type", "application/json")

            l_body := "{%"text%": %"" + escape_json (a_message) + "%"}"

            if l_http.post (a_url, l_body) then
                logger.debug ("Webhook sent: " + a_url)
            else
                logger.warning ("Webhook failed: " + l_http.last_error)
            end
        end

    notify_deployment_start (a_manifest: DEPLOY_RUNNER_MANIFEST;
            a_env: STRING)
        do
            if attached a_manifest.notifications.on_start as notifs then
                across notifs as n loop
                    if attached n.item.webhook_url as url then
                        notify_webhook (url, resolve_message (
                            n.item.message, a_manifest, a_env))
                    end
                end
            end
        end
```

## Dependency Graph

```
deploy_runner
    |
    +-- simple_process (required)
    |       +-- simple_datetime
    |
    +-- simple_json (required)
    |
    +-- simple_yaml (required)
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
    +-- simple_archive (optional - artifact mgmt)
    |
    +-- simple_file (optional - backup mgmt)
    |
    +-- simple_http (optional - Pro/Enterprise)
    |
    +-- simple_template (optional - variable expansion)
    |
    +-- simple_uuid (optional - deployment IDs)
    |
    +-- ISE base (required)
```

## ECF Configuration

```xml
<?xml version="1.0" encoding="utf-8"?>
<system name="deploy_runner" uuid="B2C3D4E5-F6A7-8901-BCDE-F12345678901"
        xmlns="http://www.eiffel.com/developers/xml/configuration-1-23-0">
    <description>DeployRunner - Lightweight deployment automation</description>

    <target name="deploy_runner">
        <root class="DEPLOY_RUNNER_CLI" feature="make"/>
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

        <!-- simple_* dependencies (required) -->
        <library name="simple_process"
                 location="$SIMPLE_EIFFEL/simple_process/simple_process.ecf"/>
        <library name="simple_json"
                 location="$SIMPLE_EIFFEL/simple_json/simple_json.ecf"/>
        <library name="simple_yaml"
                 location="$SIMPLE_EIFFEL/simple_yaml/simple_yaml.ecf"/>
        <library name="simple_logger"
                 location="$SIMPLE_EIFFEL/simple_logger/simple_logger.ecf"/>
        <library name="simple_datetime"
                 location="$SIMPLE_EIFFEL/simple_datetime/simple_datetime.ecf"/>
        <library name="simple_cli"
                 location="$SIMPLE_EIFFEL/simple_cli/simple_cli.ecf"/>
        <library name="simple_sql"
                 location="$SIMPLE_EIFFEL/simple_sql/simple_sql.ecf"/>

        <!-- Optional: Artifact management -->
        <library name="simple_archive"
                 location="$SIMPLE_EIFFEL/simple_archive/simple_archive.ecf"/>

        <!-- Optional: File operations -->
        <library name="simple_file"
                 location="$SIMPLE_EIFFEL/simple_file/simple_file.ecf"/>

        <!-- Optional: Pro tier webhooks -->
        <library name="simple_http"
                 location="$SIMPLE_EIFFEL/simple_http/simple_http.ecf"
                 readonly="false">
            <condition>
                <custom name="deploy_runner_pro" value="true"/>
            </condition>
        </library>

        <!-- ISE dependencies -->
        <library name="base" location="$ISE_LIBRARY/library/base/base.ecf"/>
        <library name="time" location="$ISE_LIBRARY/library/time/time.ecf"/>

        <!-- Application source -->
        <cluster name="src" location=".\src\" recursive="true"/>
    </target>

    <target name="deploy_runner_tests" extends="deploy_runner">
        <root class="TEST_APP" feature="make"/>
        <library name="simple_testing"
                 location="$SIMPLE_EIFFEL/simple_testing/simple_testing.ecf"/>
        <cluster name="tests" location=".\tests\" recursive="true"/>
    </target>
</system>
```
