#![doc = include_str!("../README.md")]
//! @behavior selvedge.operations.logging Project logging emits filtered structured stderr lines and typed errors through a single runtime.
//! @behavior selvedge.operations.logging.emit Project log emission writes filtered structured log lines with callsite metadata through the initialized logging runtime.
//! @behavior selvedge.operations.logging.runtime Logging preserves filtered structured output, caller metadata, and typed error behavior.

use std::{
    fmt::Display,
    io::{self, Write},
    sync::{Arc, LazyLock, Mutex, RwLock},
};

use selvedge_config::read;
use selvedge_config_model::LogFilter;

static RUNTIME: LazyLock<RwLock<RuntimeState>> =
    LazyLock::new(|| RwLock::new(RuntimeState::Uninitialized));

// @behavior selvedge.operations.logging.runtime.init Logging initialization installs the stderr runtime after configuration is readable.
pub fn init() -> Result<(), InitError> {
    validate_config_ready()?;
    let mut runtime = RUNTIME
        // @behavior selvedge.operations.logging.runtime.init.lock Logging initialization reports a runtime lock error when the runtime write lock is poisoned.
        .write()
        // @behavior selvedge.operations.logging.runtime.init.lock_poisoned Logging initialization maps a poisoned runtime write lock into InitError::RuntimeLockPoisoned.
        .map_err(|_| InitError::RuntimeLockPoisoned)?;

    if matches!(*runtime, RuntimeState::Initialized(_)) {
        // @behavior selvedge.operations.logging.runtime.init.already_initialized Logging initialization returns AlreadyInitialized when a runtime is already installed.
        return Err(InitError::AlreadyInitialized);
    }

    *runtime = RuntimeState::Initialized(Arc::new(StderrSink::default()));

    Ok(())
}

#[derive(Debug)]
// @behavior selvedge.operations.logging.runtime.init_error Logging initialization failures are reported as typed InitError values.
pub enum InitError {
    AlreadyInitialized,
    // @behavior selvedge.operations.logging.runtime.init_error.read_config Logging initialization preserves configuration read failures inside InitError::ReadConfig.
    ReadConfig(selvedge_config::ConfigError),
    RuntimeLockPoisoned,
}

impl Display for InitError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            // @behavior selvedge.operations.logging.runtime.init_error.already_initialized_message AlreadyInitialized displays a stable human-readable initialization error message.
            Self::AlreadyInitialized => formatter.write_str("logging has already been initialized"),
            Self::ReadConfig(error) => {
                write!(
                    formatter,
                    "failed to read logging config during init: {error}"
                )
            }
            // @behavior selvedge.operations.logging.runtime.init_error.runtime_lock_message RuntimeLockPoisoned displays a stable human-readable runtime lock error message.
            Self::RuntimeLockPoisoned => formatter.write_str("logging runtime lock poisoned"),
        }
    }
}

impl std::error::Error for InitError {}

impl From<selvedge_config::ConfigError> for InitError {
    fn from(error: selvedge_config::ConfigError) -> Self {
        Self::ReadConfig(error)
    }
}

#[derive(Debug)]
// @behavior selvedge.operations.logging.runtime.emit_error Log emission failures are reported as typed EmitError values.
pub enum EmitError {
    // @behavior selvedge.operations.logging.runtime.emit_error.read_config Log emission preserves configuration read failures inside EmitError::ReadConfig.
    ReadConfig(selvedge_config::ConfigError),
    NotInitialized,
    // @behavior selvedge.operations.logging.runtime.emit_error.reserved_field Log emission rejects caller fields that reuse reserved structured log keys.
    ReservedFieldName(String),
    RuntimeLockPoisoned,
    OutputLockPoisoned,
    // @behavior selvedge.operations.logging.runtime.emit_error.write Log emission preserves stderr write failures inside EmitError::Write.
    Write(io::Error),
}

impl Display for EmitError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ReadConfig(error) => write!(formatter, "failed to read logging config: {error}"),
            // @behavior selvedge.operations.logging.runtime.emit_error.not_initialized_message NotInitialized displays a stable human-readable missing runtime error message.
            Self::NotInitialized => formatter.write_str("logging has not been initialized"),
            Self::ReservedFieldName(field_name) => {
                write!(
                    formatter,
                    "reserved log field name is not allowed: {field_name}"
                )
            }
            // @behavior selvedge.operations.logging.runtime.emit_error.runtime_lock_message RuntimeLockPoisoned displays a stable human-readable runtime lock error message.
            Self::RuntimeLockPoisoned => formatter.write_str("logging runtime lock poisoned"),
            // @behavior selvedge.operations.logging.runtime.emit_error.output_lock_message OutputLockPoisoned displays a stable human-readable output lock error message.
            Self::OutputLockPoisoned => formatter.write_str("logging output lock poisoned"),
            Self::Write(error) => write!(formatter, "failed to write log output: {error}"),
        }
    }
}

impl std::error::Error for EmitError {}

impl From<selvedge_config::ConfigError> for EmitError {
    fn from(error: selvedge_config::ConfigError) -> Self {
        Self::ReadConfig(error)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
// @behavior selvedge.operations.logging.runtime.level Log levels define the ordered severity values used by filtering and rendered output.
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct LogEvent {
    level: LogLevel,
    message: String,
    module_path: String,
    file: String,
    line: u32,
    fields: Vec<(String, String)>,
}

impl LogEvent {
    #[cfg(test)]
    fn field(&self, name: &str) -> Option<&str> {
        self.fields
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }
}

impl LogLevel {
    fn meets_filter(self, minimum_level: LogFilter) -> bool {
        self.rank() >= filter_rank(minimum_level)
    }

    fn rank(self) -> u8 {
        match self {
            Self::Trace => 0,
            Self::Debug => 1,
            Self::Info => 2,
            Self::Warn => 3,
            Self::Error => 4,
        }
    }
}

// @behavior selvedge.operations.logging.runtime.filter Log filtering compares event severity against the current default or longest matching module override.
fn should_emit(level: LogLevel, module_path: &str) -> Result<bool, EmitError> {
    read(|config| {
        let minimum_level = effective_filter_for_module(
            config.logging.level,
            &config.logging.module_levels,
            module_path,
        );

        level.meets_filter(minimum_level)
    })
    // @behavior selvedge.operations.logging.runtime.filter.config_error Log filtering returns a typed emit error when the current configuration cannot be read.
    .map_err(EmitError::from)
}

fn effective_filter_for_module(
    default_level: LogFilter,
    module_levels: &std::collections::BTreeMap<String, LogFilter>,
    module_path: &str,
) -> LogFilter {
    module_levels
        .iter()
        .filter(|(prefix, _)| matches_module_override(module_path, prefix))
        .max_by_key(|(prefix, _)| prefix.len())
        .map(|(_, level)| *level)
        .unwrap_or(default_level)
}

fn matches_module_override(module_path: &str, prefix: &str) -> bool {
    module_path == prefix
        || module_path
            .strip_prefix(prefix)
            .is_some_and(|suffix| suffix.starts_with("::"))
}

// @behavior selvedge.operations.logging.emit.lazy Lazy log emission evaluates message and fields only after the active filters allow the event.
pub fn emit_lazy<MessageFn, FieldsFn>(
    level: LogLevel,
    module_path: &'static str,
    file: &'static str,
    line: u32,
    message_fn: MessageFn,
    fields_fn: FieldsFn,
    // @behavior selvedge.operations.logging.emit.result Lazy log emission returns success, a typed filtering error, a validation error, or a sink write error to the caller.
) -> Result<(), EmitError>
where
    // @behavior selvedge.operations.logging.emit.message_factory The log message factory supplies the rendered message after filtering accepts the event.
    MessageFn: FnOnce() -> String,
    // @behavior selvedge.operations.logging.emit.fields_factory The log fields factory supplies structured fields after filtering accepts the event.
    FieldsFn: FnOnce() -> Vec<(String, String)>,
{
    let sink = current_sink()?;

    if !should_emit(level, module_path)? {
        return Ok(());
    }

    let fields = fields_fn();
    validate_field_names(&fields)?;

    let event = LogEvent {
        level,
        message: message_fn(),
        module_path: module_path.to_owned(),
        file: file.to_owned(),
        line,
        fields,
    };

    // @behavior selvedge.operations.logging.emit.sink_write Accepted log events are sent to the installed sink with level, message, callsite, and validated fields.
    sink.write(event)
}

#[macro_export]
macro_rules! selvedge_log {
    ($level:expr, $message:expr $(,)?) => {{
        $crate::emit_lazy(
            $level,
            module_path!(),
            file!(),
            line!(),
            || ::std::string::ToString::to_string(&$message),
            || ::std::vec::Vec::new(),
        )
    }};
    ($level:expr, $message:expr; $($key:ident = $value:expr),+ $(,)?) => {{
        $crate::emit_lazy(
            $level,
            module_path!(),
            file!(),
            line!(),
            || ::std::string::ToString::to_string(&$message),
            || {
                let mut fields = ::std::vec::Vec::new();
                $(
                    fields.push((
                        ::std::string::String::from(stringify!($key)),
                        ::std::format!("{}", $value),
                    ));
                )+
                fields
            },
        )
    }};
}

enum RuntimeState {
    Uninitialized,
    // @intent selvedge.operations.logging.runtime.installed_sink The initialized runtime stores the single sink used by subsequent project log emission.
    Initialized(Arc<dyn EventSink>),
}

// @intent selvedge.operations.logging.runtime.sink_trait The event sink abstraction lets production stderr output and tests share the same log emission contract.
trait EventSink: Send + Sync {
    fn write(&self, event: LogEvent) -> Result<(), EmitError>;
}

struct StderrSink {
    writer: Mutex<io::Stderr>,
}

impl Default for StderrSink {
    fn default() -> Self {
        Self {
            writer: Mutex::new(io::stderr()),
        }
    }
}

impl EventSink for StderrSink {
    fn write(&self, event: LogEvent) -> Result<(), EmitError> {
        // @behavior selvedge.operations.logging.runtime.stderr_write Project log emission writes one rendered line to stderr or returns a write-related logging error.
        let mut writer = self
            .writer
            .lock()
            // @behavior selvedge.operations.logging.runtime.stderr_write.output_lock Stderr log writing returns OutputLockPoisoned when the stderr mutex is poisoned.
            .map_err(|_| EmitError::OutputLockPoisoned)?;
        let rendered = render_event(&event);

        // @behavior selvedge.operations.logging.runtime.stderr_write.write_error Stderr log writing maps write failures into EmitError::Write.
        writeln!(writer, "{rendered}").map_err(EmitError::Write)
    }
}

// @behavior selvedge.operations.logging.runtime.config_ready Logging initialization checks that the current configuration can be read before installing a sink.
fn validate_config_ready() -> Result<(), InitError> {
    read(|config| {
        let _ = config.logging.level;
    })
    // @behavior selvedge.operations.logging.runtime.config_ready.error Logging initialization maps unreadable configuration into InitError::ReadConfig.
    .map_err(InitError::from)
}

// @intent selvedge.operations.logging.runtime.current_sink The current sink lookup exposes the installed runtime sink to each log emission.
fn current_sink() -> Result<Arc<dyn EventSink>, EmitError> {
    // @behavior selvedge.operations.logging.runtime.current_sink.lock_error Current sink lookup returns RuntimeLockPoisoned when the runtime read lock is poisoned.
    let runtime = RUNTIME.read().map_err(|_| EmitError::RuntimeLockPoisoned)?;

    match &*runtime {
        // @behavior selvedge.operations.logging.runtime.current_sink.missing Current sink lookup returns NotInitialized when no runtime has been installed.
        RuntimeState::Uninitialized => Err(EmitError::NotInitialized),
        RuntimeState::Initialized(sink) => Ok(sink.clone()),
    }
}

fn render_event(event: &LogEvent) -> String {
    let mut rendered = format!(
        "level={} module={} file={} line={} message={}",
        render_level(event.level),
        render_value(&event.module_path),
        render_value(&event.file),
        event.line,
        render_value(&event.message)
    );

    for (key, value) in &event.fields {
        rendered.push(' ');
        rendered.push_str(key);
        rendered.push('=');
        rendered.push_str(&render_value(value));
    }

    rendered
}

fn validate_field_names(fields: &[(String, String)]) -> Result<(), EmitError> {
    for (field_name, _) in fields {
        if is_reserved_field_name(field_name) {
            // @behavior selvedge.operations.logging.emit.reserved_field_error Reserved structured field names return EmitError::ReservedFieldName before any sink write occurs.
            return Err(EmitError::ReservedFieldName(field_name.clone()));
        }
    }

    Ok(())
}

fn is_reserved_field_name(field_name: &str) -> bool {
    matches!(field_name, "level" | "module" | "file" | "line" | "message")
}

fn render_level(level: LogLevel) -> &'static str {
    match level {
        LogLevel::Trace => "trace",
        LogLevel::Debug => "debug",
        LogLevel::Info => "info",
        LogLevel::Warn => "warn",
        LogLevel::Error => "error",
    }
}

fn filter_rank(level: LogFilter) -> u8 {
    match level {
        LogFilter::Trace => 0,
        LogFilter::Debug => 1,
        LogFilter::Info => 2,
        LogFilter::Warn => 3,
        LogFilter::Error => 4,
    }
}

fn render_value(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t");

    format!("\"{escaped}\"")
}

#[cfg(test)]
#[derive(Clone, Default)]
// @intent selvedge.operations.logging.tests Test logging helpers expose captured events and runtime installation for logging contract tests.
struct TestRecorder {
    events: Arc<Mutex<Vec<LogEvent>>>,
}

#[cfg(test)]
impl TestRecorder {
    fn clear(&self) {
        // @behavior selvedge.operations.logging.tests.recorder_clear Test log recorder clearing removes captured events before a test scenario emits new logs.
        let mut events = self.events.lock().expect("test recorder lock");
        events.clear();
    }

    fn take(&self) -> Vec<LogEvent> {
        // @behavior selvedge.operations.logging.tests.recorder_take Test log recorder taking returns all captured events and leaves the recorder empty.
        let mut events = self.events.lock().expect("test recorder lock");

        std::mem::take(&mut *events)
    }
}

#[cfg(test)]
impl EventSink for TestRecorder {
    fn write(&self, event: LogEvent) -> Result<(), EmitError> {
        // @behavior selvedge.operations.logging.tests.recorder_write Test log recorder writing stores accepted log events for caller-visible assertions.
        let mut events = self.events.lock().expect("test recorder lock");
        events.push(event);
        Ok(())
    }
}

#[cfg(test)]
fn init_for_test(recorder: TestRecorder) -> Result<(), InitError> {
    validate_config_ready()?;
    install_test_runtime(recorder)
}

#[cfg(test)]
fn install_test_runtime(recorder: TestRecorder) -> Result<(), InitError> {
    let mut runtime = RUNTIME
        // @behavior selvedge.operations.logging.tests.install_runtime_lock Test runtime installation reports InitError::RuntimeLockPoisoned when the runtime write lock is poisoned.
        .write()
        // @behavior selvedge.operations.logging.tests.install_runtime_error Test runtime installation maps a poisoned runtime write lock into InitError::RuntimeLockPoisoned.
        .map_err(|_| InitError::RuntimeLockPoisoned)?;
    *runtime = RuntimeState::Initialized(Arc::new(recorder));
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{
        process::Command,
        sync::{Arc, Mutex, OnceLock},
    };

    use selvedge_config::init_with_home;
    use selvedge_config_model::LogFilter;
    use tempfile::TempDir;

    use super::{LogEvent, LogLevel, TestRecorder, init_for_test};

    static TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    static CONFIG_INIT: OnceLock<()> = OnceLock::new();

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn macro_uses_callsite_module_without_manual_module_name() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();

        init_for_test(recorder.clone()).expect("init test logger");
        selvedge_config::update_runtime("logging.level", "info").expect("set log level");
        recorder.clear();

        selvedge_log!(LogLevel::Info, "router started").expect("emit router started");

        let events = recorder.take();
        let event = events.first().expect("captured event");

        // @verifies selvedge.operations.logging
        assert_eq!(event.level, LogLevel::Info);
        // @verifies selvedge.operations.logging
        assert_eq!(event.message, "router started");
        // @verifies selvedge.operations.logging
        assert!(event.module_path.contains("selvedge_logging"));
        // @verifies selvedge.operations.logging
        assert!(event.fields.is_empty());
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn macro_accepts_optional_fields_without_requiring_role() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();

        init_for_test(recorder.clone()).expect("init test logger");
        selvedge_config::update_runtime("logging.level", "info").expect("set log level");
        recorder.clear();

        selvedge_log!(LogLevel::Warn, "target thread not found"; thread = "worker-2", target = "indexer")
            .expect("emit warn event");

        let events = recorder.take();
        let event = events.first().expect("captured event");

        // @verifies selvedge.operations.logging
        assert_eq!(event.level, LogLevel::Warn);
        // @verifies selvedge.operations.logging
        assert_eq!(event.message, "target thread not found");
        // @verifies selvedge.operations.logging
        assert_eq!(event.field("thread"), Some("worker-2"));
        // @verifies selvedge.operations.logging
        assert_eq!(event.field("target"), Some("indexer"));
        // @verifies selvedge.operations.logging
        assert!(event.field("role").is_none());
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn changed_config_applies_to_next_log_call_without_reinit() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();

        init_for_test(recorder.clone()).expect("init test logger");
        selvedge_config::update_runtime("logging.level", "info").expect("set info");
        recorder.clear();

        selvedge_log!(LogLevel::Debug, "debug should be filtered")
            .expect("debug event should evaluate cleanly");
        // @verifies selvedge.operations.logging
        assert!(recorder.take().is_empty());

        selvedge_config::update_runtime("logging.level", "debug").expect("set debug");
        selvedge_log!(LogLevel::Debug, "debug should pass").expect("emit debug event");

        let events = recorder.take();
        let event = events.first().expect("captured event");
        // @verifies selvedge.operations.logging
        assert_eq!(event.message, "debug should pass");
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn module_override_requires_exact_path_or_descendant_boundary() {
        assert_eq!(
            super::effective_filter_for_module(
                LogFilter::Warn,
                &std::collections::BTreeMap::from([(
                    "selvedge::router".to_owned(),
                    LogFilter::Debug,
                )]),
                "selvedge::router",
            ),
            LogFilter::Debug
        );
        // @verifies selvedge.operations.logging
        assert_eq!(
            super::effective_filter_for_module(
                LogFilter::Warn,
                &std::collections::BTreeMap::from([(
                    "selvedge::router".to_owned(),
                    LogFilter::Debug,
                )]),
                "selvedge::router::dispatch",
            ),
            LogFilter::Debug
        );
        // @verifies selvedge.operations.logging
        assert_eq!(
            super::effective_filter_for_module(
                LogFilter::Warn,
                &std::collections::BTreeMap::from([(
                    "selvedge::router".to_owned(),
                    LogFilter::Debug,
                )]),
                "selvedge::router_worker",
            ),
            LogFilter::Warn
        );
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn concurrent_logging_keeps_messages_distinct() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();

        init_for_test(recorder.clone()).expect("init test logger");
        selvedge_config::update_runtime("logging.level", "info").expect("set log level");
        recorder.clear();

        let threads = (0..4)
            .map(|index| {
                std::thread::spawn(move || {
                    selvedge_log!(LogLevel::Info, "worker event"; worker = index)
                        .expect("emit worker event");
                })
            })
            .collect::<Vec<_>>();

        for thread in threads {
            thread.join().expect("join logging thread");
        }

        let events = recorder.take();

        // @verifies selvedge.operations.logging
        assert_eq!(events.len(), 4);
        // @verifies selvedge.operations.logging
        assert!(events.iter().all(|event| event.message == "worker event"));
        // @verifies selvedge.operations.logging
        assert_eq!(unique_workers(&events), vec!["0", "1", "2", "3"]);
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn log_macro_returns_error_when_config_is_missing() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::missing_config_child_reports_error")
            .env("SELVEDGE_LOGGING_MISSING_CONFIG_CHILD", "1")
            .output()
            .expect("run missing config child test");

        // @verifies selvedge.operations.logging
        assert!(output.status.success(), "child test failed: {output:?}");
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn log_macro_returns_error_when_runtime_is_missing() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::missing_runtime_child_reports_error")
            .env("SELVEDGE_LOGGING_MISSING_RUNTIME_CHILD", "1")
            .output()
            .expect("run missing runtime child test");

        // @verifies selvedge.operations.logging
        assert!(output.status.success(), "child test failed: {output:?}");
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn init_returns_error_when_config_is_missing() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::missing_config_init_child_reports_error")
            .env("SELVEDGE_LOGGING_MISSING_CONFIG_INIT_CHILD", "1")
            .output()
            .expect("run missing config init child test");

        // @verifies selvedge.operations.logging
        assert!(output.status.success(), "child test failed: {output:?}");
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn filtered_log_does_not_evaluate_message_or_fields() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();
        let message_counter = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let field_counter = Arc::new(std::sync::atomic::AtomicUsize::new(0));

        init_for_test(recorder.clone()).expect("init test logger");
        selvedge_config::update_runtime("logging.level", "warn").expect("set warn level");
        recorder.clear();

        let message_counter_for_log = Arc::clone(&message_counter);
        let field_counter_for_log = Arc::clone(&field_counter);
        selvedge_log!(
            LogLevel::Info,
            counted_message(&message_counter_for_log);
            worker = counted_field(&field_counter_for_log)
        )
        .expect("filtered log should still return ok");

        // @verifies selvedge.operations.logging
        assert_eq!(message_counter.load(std::sync::atomic::Ordering::SeqCst), 0);
        // @verifies selvedge.operations.logging
        assert_eq!(field_counter.load(std::sync::atomic::Ordering::SeqCst), 0);
        // @verifies selvedge.operations.logging
        assert!(recorder.take().is_empty());
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn log_macro_rejects_reserved_field_names() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();

        init_for_test(recorder.clone()).expect("init test logger");
        selvedge_config::update_runtime("logging.level", "info").expect("set log level");
        recorder.clear();

        let error = selvedge_log!(LogLevel::Info, "router started"; message = "duplicate key")
            .expect_err("reserved field names should return an error");

        // @verifies selvedge.operations.logging
        assert!(matches!(
            error,
            super::EmitError::ReservedFieldName(field_name) if field_name == "message"
        ));
        // @verifies selvedge.operations.logging
        assert!(recorder.take().is_empty());
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn render_event_escapes_special_characters() {
        let event = LogEvent {
            level: LogLevel::Info,
            message: "hello \"quoted\"\nnext".to_owned(),
            module_path: "selvedge::router".to_owned(),
            file: "src/main.rs".to_owned(),
            line: 42,
            fields: vec![("detail".to_owned(), "two words\tand more".to_owned())],
        };

        let rendered = super::render_event(&event);

        // @verifies selvedge.operations.logging
        assert!(rendered.contains("message=\"hello \\\"quoted\\\"\\nnext\""));
        // @verifies selvedge.operations.logging
        assert!(rendered.contains("detail=\"two words\\tand more\""));
    }

    fn ensure_test_config() {
        CONFIG_INIT.get_or_init(|| {
            let tempdir = Arc::new(TempDir::new().expect("tempdir"));
            let config_home = tempdir.path().join(".selvedge");
            let config_path = config_home.join("config.toml");

            std::fs::create_dir_all(&config_home).expect("create config home");

            std::fs::write(
                &config_path,
                r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000

[logging]
level = "info"
"#,
            )
            .expect("write config");

            let _ = Arc::into_raw(tempdir);
            init_with_home(config_home).expect("init config");
        });
    }

    fn unique_workers(events: &[LogEvent]) -> Vec<&str> {
        let mut workers = events
            .iter()
            .filter_map(|event| event.field("worker"))
            .collect::<Vec<_>>();

        workers.sort_unstable();
        workers
    }

    fn test_lock() -> &'static Mutex<()> {
        TEST_LOCK.get_or_init(|| Mutex::new(()))
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn missing_config_child_reports_error() {
        if std::env::var_os("SELVEDGE_LOGGING_MISSING_CONFIG_CHILD").is_none() {
            return;
        }

        super::install_test_runtime(TestRecorder::default()).expect("install test logger");
        let error = super::selvedge_log!(LogLevel::Info, "missing config")
            .expect_err("missing config should return an error");

        // @verifies selvedge.operations.logging
        assert!(matches!(
            error,
            super::EmitError::ReadConfig(selvedge_config::ConfigError::NotInitialized)
        ));
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn missing_runtime_child_reports_error() {
        if std::env::var_os("SELVEDGE_LOGGING_MISSING_RUNTIME_CHILD").is_none() {
            return;
        }

        let tempdir = TempDir::new().expect("tempdir");
        let config_home = tempdir.path().join(".selvedge");
        let config_path = config_home.join("config.toml");
        std::fs::create_dir_all(&config_home).expect("create config home");
        std::fs::write(
            &config_path,
            r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000

[logging]
level = "info"
"#,
        )
        .expect("write config");

        init_with_home(config_home).expect("init config");
        let error = super::selvedge_log!(LogLevel::Info, "missing runtime")
            .expect_err("missing runtime should return an error");

        // @verifies selvedge.operations.logging
        assert!(matches!(error, super::EmitError::NotInitialized));
    }

    // @verifies selvedge.operations.logging.emit
    #[test]
    fn missing_config_init_child_reports_error() {
        if std::env::var_os("SELVEDGE_LOGGING_MISSING_CONFIG_INIT_CHILD").is_none() {
            return;
        }

        let error = super::init().expect_err("missing config should fail logging init");

        assert!(matches!(
            error,
            super::InitError::ReadConfig(selvedge_config::ConfigError::NotInitialized)
        ));
    }

    fn counted_message(counter: &std::sync::atomic::AtomicUsize) -> String {
        counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        "filtered message".to_owned()
    }

    fn counted_field(counter: &std::sync::atomic::AtomicUsize) -> usize {
        counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        7
    }
}
