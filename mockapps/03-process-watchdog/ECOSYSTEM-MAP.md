# ProcessWatchdog - Ecosystem Integration

## simple_* Dependencies

### Required Libraries

| Library | Purpose | Integration Point |
|---------|---------|-------------------|
| simple_process | Health check command execution | Health checker |
| simple_async_process | Process spawning and monitoring | Process monitor |
| simple_json | Configuration parsing | Config loader |
| simple_logger | Event logging with rotation | Throughout |
| simple_datetime | Uptime tracking, timestamps | Monitor, history |
| simple_cli | Argument parsing, help | CLI interface |
| simple_sql | Event history database | History storage |

### Optional Libraries

| Library | Purpose | When Needed |
|---------|---------|-------------|
| simple_http | HTTP health checks, webhooks, metrics server | Health checks, alerting, Enterprise |
| simple_smtp | Email alerts | Pro tier alerting |
| simple_config | Environment variable expansion | Advanced config |
| simple_file | Log file management | Log rotation |
| simple_uuid | Unique event IDs | Event tracking |
| simple_validation | Config validation | Extended validation |

## Integration Patterns

### simple_async_process Integration

**Purpose:** Spawn and monitor processes without blocking

**Usage:**
```eiffel
class WATCHDOG_MONITOR

feature {NONE} -- Initialization

    make (a_process: WATCHDOG_PROCESS; a_logger: SIMPLE_LOGGER)
        do
            process_config := a_process
            logger := a_logger
            create async.make
            async.set_show_window (a_process.show_window)
        end

feature -- Status

    is_running: BOOLEAN
            -- Is the process currently running?
        do
            if async.is_started then
                Result := async.is_running
            end
        end

    pid: NATURAL_32
            -- Process ID (0 if not running)
        do
            if is_running then
                Result := async.process_id
            end
        end

    uptime_seconds: INTEGER
            -- Seconds since process started
        do
            if is_running then
                Result := async.elapsed_seconds
            end
        end

feature -- Operations

    start: BOOLEAN
            -- Start the monitored process
        local
            l_command: STRING
        do
            if not is_running then
                l_command := process_config.command
                if attached process_config.arguments as args then
                    l_command := l_command + " " + args
                end

                logger.info ("Starting process: " + process_config.name)

                if attached process_config.working_directory as wd then
                    async.start_in_directory (l_command, wd)
                else
                    async.start (l_command)
                end

                if async.is_started and async.was_started_successfully then
                    logger.info ("Process started: " + process_config.name +
                        " (PID=" + pid.out + ")")
                    create start_time.make_now
                    restart_count := restart_count + 1
                    Result := True
                else
                    logger.error ("Failed to start: " + process_config.name)
                    if attached async.last_error as err then
                        logger.error ("Error: " + err)
                    end
                end
            end
        end

    stop: BOOLEAN
            -- Stop the monitored process
        do
            if is_running then
                logger.info ("Stopping process: " + process_config.name)
                Result := async.kill
                async.close
                if Result then
                    logger.info ("Process stopped: " + process_config.name)
                else
                    logger.error ("Failed to stop: " + process_config.name)
                end
            else
                Result := True -- Already stopped
            end
        end

    restart: BOOLEAN
            -- Restart the process (stop then start)
        do
            logger.info ("Restarting process: " + process_config.name)
            if stop then
                -- Brief delay before restart
                sleep_ms (1000)
                Result := start
            end
        end

    read_output: detachable STRING_32
            -- Read available output (non-blocking)
        do
            if async.is_started then
                Result := async.read_available_output
            end
        end

feature {NONE} -- Implementation

    async: SIMPLE_ASYNC_PROCESS
    process_config: WATCHDOG_PROCESS
    logger: SIMPLE_LOGGER
    start_time: detachable SIMPLE_DATE_TIME
    restart_count: INTEGER
```

### simple_process Integration

**Purpose:** Execute health check commands

**Usage:**
```eiffel
class WATCHDOG_HEALTH_CHECKER

feature -- Health Checks

    check_command (a_check: WATCHDOG_HEALTH_CHECK): BOOLEAN
            -- Execute command-based health check
        local
            l_proc: SIMPLE_PROCESS
            l_output: STRING_32
        do
            create l_proc.make
            l_proc.set_show_window (False)

            l_output := l_proc.output_of_command (a_check.command)

            if l_proc.was_successful then
                if attached a_check.expected_output as expected then
                    Result := l_output.has_substring (expected)
                else
                    Result := True -- Success if command succeeded
                end
            end

            logger.debug ("Health check (command): " +
                a_check.command + " = " + Result.out)
        end

    check_http (a_check: WATCHDOG_HEALTH_CHECK): BOOLEAN
            -- Execute HTTP health check
        local
            l_http: SIMPLE_HTTP
            l_response: STRING
        do
            create l_http.make
            l_http.set_timeout (a_check.timeout_seconds * 1000)

            if l_http.get (a_check.url) then
                if a_check.expected_status > 0 then
                    Result := l_http.status_code = a_check.expected_status
                else
                    Result := l_http.status_code >= 200 and l_http.status_code < 300
                end

                if Result and attached a_check.expected_body as body then
                    Result := l_http.response_body.has_substring (body)
                end
            end

            logger.debug ("Health check (http): " + a_check.url +
                " status=" + l_http.status_code.out + " = " + Result.out)
        end

    check_port (a_check: WATCHDOG_HEALTH_CHECK): BOOLEAN
            -- Check if TCP port is listening
        local
            l_proc: SIMPLE_PROCESS
            l_output: STRING_32
        do
            create l_proc.make
            -- Use netstat to check port
            l_output := l_proc.output_of_command (
                "netstat -an | findstr :" + a_check.port.out + " | findstr LISTENING")
            Result := l_proc.was_successful and not l_output.is_empty

            logger.debug ("Health check (port): " + a_check.port.out +
                " = " + Result.out)
        end
```

### simple_json Integration

**Purpose:** Parse process and global configuration

**Usage:**
```eiffel
class WATCHDOG_CONFIG

feature -- Loading

    load (a_path: STRING): BOOLEAN
            -- Load configuration from JSON file
        local
            l_json: SIMPLE_JSON
            l_content: STRING
        do
            create l_json.make
            l_content := file_content (a_path)

            if l_json.parse (l_content) then
                -- Load global settings
                if attached l_json.object_at ("watchdog") as settings then
                    check_interval := settings.integer_at_or ("check_interval_seconds", 5)
                    log_directory := settings.string_at_or ("log_directory",
                        "C:\ProgramData\Watchdog\logs")
                    load_alert_config (settings.object_at ("alerts"))
                end

                -- Load processes
                if attached l_json.array_at ("processes") as procs then
                    across procs as p loop
                        add_process (load_process (p.item))
                    end
                end

                Result := True
            else
                last_error := "JSON parse error: " + l_json.last_error
            end
        end

    load_process (a_json: SIMPLE_JSON_NODE): WATCHDOG_PROCESS
        do
            create Result.make
            Result.set_name (a_json.string_at ("name"))
            Result.set_command (a_json.string_at ("command"))

            if a_json.has ("arguments") then
                Result.set_arguments (a_json.string_at ("arguments"))
            end

            if a_json.has ("working_directory") then
                Result.set_working_directory (a_json.string_at ("working_directory"))
            end

            -- Load health check
            if attached a_json.object_at ("health_check") as hc then
                Result.set_health_check (load_health_check (hc))
            end

            -- Load restart policy
            if attached a_json.object_at ("restart_policy") as rp then
                Result.set_restart_policy (load_restart_policy (rp))
            end

            Result.set_enabled (a_json.boolean_at_or ("enabled", True))
            Result.set_auto_start (a_json.boolean_at_or ("auto_start", True))
        end
```

### simple_sql Integration

**Purpose:** Store event history for reporting

**Usage:**
```eiffel
class WATCHDOG_HISTORY

feature {NONE} -- Initialization

    make (a_db_path: STRING)
        do
            create db.make (a_db_path)
            ensure_schema
        end

    ensure_schema
        do
            db.execute ("
                CREATE TABLE IF NOT EXISTS events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    process_name TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    message TEXT,
                    exit_code INTEGER,
                    pid INTEGER
                )
            ")
            db.execute ("CREATE INDEX IF NOT EXISTS idx_process ON events(process_name)")
            db.execute ("CREATE INDEX IF NOT EXISTS idx_timestamp ON events(timestamp)")
            db.execute ("CREATE INDEX IF NOT EXISTS idx_type ON events(event_type)")
        end

feature -- Recording

    record_start (a_name: STRING; a_pid: NATURAL_32)
        do
            record_event (a_name, "start", "Process started", 0, a_pid.to_integer_32)
        end

    record_stop (a_name: STRING; a_exit_code: INTEGER)
        do
            record_event (a_name, "stop", "Process stopped", a_exit_code, 0)
        end

    record_crash (a_name: STRING; a_exit_code: INTEGER)
        do
            record_event (a_name, "crash", "Process crashed unexpectedly",
                a_exit_code, 0)
        end

    record_restart (a_name: STRING; a_reason: STRING)
        do
            record_event (a_name, "restart", a_reason, 0, 0)
        end

    record_health_fail (a_name: STRING; a_message: STRING)
        do
            record_event (a_name, "health_fail", a_message, 0, 0)
        end

feature {NONE} -- Implementation

    record_event (a_name, a_type, a_message: STRING; a_exit_code, a_pid: INTEGER)
        do
            db.execute_with_params ("
                INSERT INTO events (timestamp, process_name, event_type,
                    message, exit_code, pid)
                VALUES (?, ?, ?, ?, ?, ?)
            ", <<create {SIMPLE_DATE_TIME}.make_now.to_iso8601,
                a_name, a_type, a_message, a_exit_code, a_pid>>)
        end

    db: SIMPLE_SQL
```

### simple_http Integration (Pro/Enterprise)

**Purpose:** HTTP health checks, webhook alerts, Prometheus metrics

**Usage:**
```eiffel
class WATCHDOG_ALERTER

feature -- Alerting

    alert_crash (a_name: STRING; a_exit_code: INTEGER)
            -- Send alert for process crash
        local
            l_message: STRING
        do
            l_message := "Process '" + a_name + "' crashed with exit code " +
                a_exit_code.out

            if email_enabled then
                send_email ("Process Crash: " + a_name, l_message)
            end

            if slack_enabled then
                send_slack (l_message)
            end

            if webhook_enabled then
                send_webhook ("crash", a_name, l_message)
            end
        end

    send_slack (a_message: STRING)
            -- Send Slack notification via webhook
        local
            l_http: SIMPLE_HTTP
            l_body: STRING
        do
            create l_http.make
            l_http.set_header ("Content-Type", "application/json")

            l_body := "{%"text%": %"" + escape_json (a_message) + "%"}"

            if not l_http.post (slack_webhook_url, l_body) then
                logger.warning ("Slack alert failed: " + l_http.last_error)
            end
        end

class WATCHDOG_METRICS_SERVER

feature -- Metrics

    start_server (a_port: INTEGER)
            -- Start Prometheus metrics server
        local
            l_http: SIMPLE_HTTP_SERVER
        do
            create l_http.make (a_port)
            l_http.add_route ("/metrics", agent handle_metrics)
            l_http.start
        end

    handle_metrics: STRING
            -- Generate Prometheus metrics
        do
            create Result.make_empty
            across processes as p loop
                Result.append (generate_process_metrics (p.item))
            end
        end

    generate_process_metrics (a_monitor: WATCHDOG_MONITOR): STRING
        local
            l_name: STRING
        do
            l_name := a_monitor.name
            create Result.make_empty

            -- Up/down gauge
            Result.append ("watchdog_process_up{name=%"" + l_name + "%"} ")
            Result.append (a_monitor.is_running.to_integer.out + "%N")

            -- Uptime gauge
            Result.append ("watchdog_process_uptime_seconds{name=%"" + l_name + "%"} ")
            Result.append (a_monitor.uptime_seconds.out + "%N")

            -- Restart counter
            Result.append ("watchdog_process_restarts_total{name=%"" + l_name + "%"} ")
            Result.append (a_monitor.restart_count.out + "%N")
        end
```

## Dependency Graph

```
process_watchdog
    |
    +-- simple_async_process (required)
    |       +-- simple_datetime
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
    +-- simple_http (optional - Pro/Enterprise)
    |
    +-- simple_smtp (optional - Pro)
    |
    +-- simple_file (optional - log mgmt)
    |
    +-- ISE base (required)
```

## ECF Configuration

```xml
<?xml version="1.0" encoding="utf-8"?>
<system name="process_watchdog" uuid="C3D4E5F6-A7B8-9012-CDEF-123456789012"
        xmlns="http://www.eiffel.com/developers/xml/configuration-1-23-0">
    <description>ProcessWatchdog - Windows process supervisor</description>

    <target name="process_watchdog">
        <root class="WATCHDOG_CLI" feature="make"/>
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
        <library name="simple_logger"
                 location="$SIMPLE_EIFFEL/simple_logger/simple_logger.ecf"/>
        <library name="simple_datetime"
                 location="$SIMPLE_EIFFEL/simple_datetime/simple_datetime.ecf"/>
        <library name="simple_cli"
                 location="$SIMPLE_EIFFEL/simple_cli/simple_cli.ecf"/>
        <library name="simple_sql"
                 location="$SIMPLE_EIFFEL/simple_sql/simple_sql.ecf"/>

        <!-- Optional: Pro tier -->
        <library name="simple_http"
                 location="$SIMPLE_EIFFEL/simple_http/simple_http.ecf"
                 readonly="false">
            <condition>
                <custom name="watchdog_pro" value="true"/>
            </condition>
        </library>
        <library name="simple_smtp"
                 location="$SIMPLE_EIFFEL/simple_smtp/simple_smtp.ecf"
                 readonly="false">
            <condition>
                <custom name="watchdog_pro" value="true"/>
            </condition>
        </library>

        <!-- ISE dependencies -->
        <library name="base" location="$ISE_LIBRARY/library/base/base.ecf"/>
        <library name="time" location="$ISE_LIBRARY/library/time/time.ecf"/>

        <!-- Application source -->
        <cluster name="src" location=".\src\" recursive="true"/>
    </target>

    <target name="process_watchdog_tests" extends="process_watchdog">
        <root class="TEST_APP" feature="make"/>
        <library name="simple_testing"
                 location="$SIMPLE_EIFFEL/simple_testing/simple_testing.ecf"/>
        <cluster name="tests" location=".\tests\" recursive="true"/>
    </target>
</system>
```
