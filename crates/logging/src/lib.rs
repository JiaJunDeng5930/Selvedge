#![doc = include_str!("../README.md")]

use std::{
    fmt::Display,
    io::{self, Write},
    sync::{Arc, LazyLock, Mutex, RwLock},
};

use selvedge_config::read;
use selvedge_config_model::LogFilter;

static RUNTIME: LazyLock<RwLock<RuntimeState>> =
    LazyLock::new(|| RwLock::new(RuntimeState::Uninitialized));

pub fn init() -> Result<(), InitError> {
    validate_config_ready()?;
    let mut runtime = RUNTIME
        .write()
        .map_err(|_| InitError::RuntimeLockPoisoned)?;

    if matches!(*runtime, RuntimeState::Initialized(_)) {
        return Err(InitError::AlreadyInitialized);
    }

    *runtime = RuntimeState::Initialized(Arc::new(StderrSink::default()));

    Ok(())
}

#[derive(Debug)]
pub enum InitError {
    AlreadyInitialized,
    ReadConfig(selvedge_config::ConfigError),
    RuntimeLockPoisoned,
}

impl Display for InitError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::AlreadyInitialized => formatter.write_str("logging has already been initialized"),
            Self::ReadConfig(error) => {
                write!(
                    formatter,
                    "failed to read logging config during init: {error}"
                )
            }
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
pub enum EmitError {
    ReadConfig(selvedge_config::ConfigError),
    NotInitialized,
    RuntimeLockPoisoned,
    OutputLockPoisoned,
    Write(io::Error),
}

impl Display for EmitError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ReadConfig(error) => write!(formatter, "failed to read logging config: {error}"),
            Self::NotInitialized => formatter.write_str("logging has not been initialized"),
            Self::RuntimeLockPoisoned => formatter.write_str("logging runtime lock poisoned"),
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
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LogEvent {
    pub level: LogLevel,
    pub message: String,
    pub module_path: String,
    pub file: String,
    pub line: u32,
    pub fields: Vec<(String, String)>,
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

pub fn should_emit(level: LogLevel, module_path: &str) -> Result<bool, EmitError> {
    read(|config| {
        let minimum_level = effective_filter_for_module(
            config.logging.level,
            &config.logging.module_levels,
            module_path,
        );

        level.meets_filter(minimum_level)
    })
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

pub fn emit(
    level: LogLevel,
    message: impl Display,
    module_path: &'static str,
    file: &'static str,
    line: u32,
    fields: Vec<(String, String)>,
) -> Result<(), EmitError> {
    let sink = current_sink()?;

    if !should_emit(level, module_path)? {
        return Ok(());
    }

    let event = LogEvent {
        level,
        message: message.to_string(),
        module_path: module_path.to_owned(),
        file: file.to_owned(),
        line,
        fields,
    };

    sink.write(event)
}

pub fn emit_lazy<MessageFn, FieldsFn>(
    level: LogLevel,
    module_path: &'static str,
    file: &'static str,
    line: u32,
    message_fn: MessageFn,
    fields_fn: FieldsFn,
) -> Result<(), EmitError>
where
    MessageFn: FnOnce() -> String,
    FieldsFn: FnOnce() -> Vec<(String, String)>,
{
    let sink = current_sink()?;

    if !should_emit(level, module_path)? {
        return Ok(());
    }

    let event = LogEvent {
        level,
        message: message_fn(),
        module_path: module_path.to_owned(),
        file: file.to_owned(),
        line,
        fields: fields_fn(),
    };

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
    Initialized(Arc<dyn EventSink>),
}

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
        let mut writer = self
            .writer
            .lock()
            .map_err(|_| EmitError::OutputLockPoisoned)?;
        let rendered = render_event(&event);

        writeln!(writer, "{rendered}").map_err(EmitError::Write)
    }
}

fn validate_config_ready() -> Result<(), InitError> {
    read(|config| {
        let _ = config.logging.level;
    })
    .map_err(InitError::from)
}

fn current_sink() -> Result<Arc<dyn EventSink>, EmitError> {
    let runtime = RUNTIME.read().map_err(|_| EmitError::RuntimeLockPoisoned)?;

    match &*runtime {
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
struct TestRecorder {
    events: Arc<Mutex<Vec<LogEvent>>>,
}

#[cfg(test)]
impl TestRecorder {
    fn clear(&self) {
        let mut events = self.events.lock().expect("test recorder lock");
        events.clear();
    }

    fn take(&self) -> Vec<LogEvent> {
        let mut events = self.events.lock().expect("test recorder lock");

        std::mem::take(&mut *events)
    }
}

#[cfg(test)]
impl EventSink for TestRecorder {
    fn write(&self, event: LogEvent) -> Result<(), EmitError> {
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
        .write()
        .map_err(|_| InitError::RuntimeLockPoisoned)?;
    *runtime = RuntimeState::Initialized(Arc::new(recorder));
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{
        collections::BTreeMap,
        process::Command,
        sync::{Arc, Mutex, OnceLock},
    };

    use selvedge_config::init_with_path;
    use selvedge_config_model::LogFilter;
    use tempfile::TempDir;

    use super::{LogEvent, LogLevel, TestRecorder, init_for_test};

    static TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    static CONFIG_INIT: OnceLock<()> = OnceLock::new();

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

        assert_eq!(event.level, LogLevel::Info);
        assert_eq!(event.message, "router started");
        assert!(event.module_path.contains("selvedge_logging"));
        assert!(event.fields.is_empty());
    }

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

        assert_eq!(event.level, LogLevel::Warn);
        assert_eq!(event.message, "target thread not found");
        assert_eq!(event.field("thread"), Some("worker-2"));
        assert_eq!(event.field("target"), Some("indexer"));
        assert!(event.field("role").is_none());
    }

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
        assert!(recorder.take().is_empty());

        selvedge_config::update_runtime("logging.level", "debug").expect("set debug");
        selvedge_log!(LogLevel::Debug, "debug should pass").expect("emit debug event");

        let events = recorder.take();
        let event = events.first().expect("captured event");
        assert_eq!(event.message, "debug should pass");
    }

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

        assert_eq!(events.len(), 4);
        assert!(events.iter().all(|event| event.message == "worker event"));
        assert_eq!(unique_workers(&events), vec!["0", "1", "2", "3"]);
    }

    #[test]
    fn log_macro_returns_error_when_config_is_missing() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::missing_config_child_reports_error")
            .env("SELVEDGE_LOGGING_MISSING_CONFIG_CHILD", "1")
            .output()
            .expect("run missing config child test");

        assert!(output.status.success(), "child test failed: {output:?}");
    }

    #[test]
    fn log_macro_returns_error_when_runtime_is_missing() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::missing_runtime_child_reports_error")
            .env("SELVEDGE_LOGGING_MISSING_RUNTIME_CHILD", "1")
            .output()
            .expect("run missing runtime child test");

        assert!(output.status.success(), "child test failed: {output:?}");
    }

    #[test]
    fn init_returns_error_when_config_is_missing() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::missing_config_init_child_reports_error")
            .env("SELVEDGE_LOGGING_MISSING_CONFIG_INIT_CHILD", "1")
            .output()
            .expect("run missing config init child test");

        assert!(output.status.success(), "child test failed: {output:?}");
    }

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

        assert_eq!(message_counter.load(std::sync::atomic::Ordering::SeqCst), 0);
        assert_eq!(field_counter.load(std::sync::atomic::Ordering::SeqCst), 0);
        assert!(recorder.take().is_empty());
    }

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

        assert!(rendered.contains("message=\"hello \\\"quoted\\\"\\nnext\""));
        assert!(rendered.contains("detail=\"two words\\tand more\""));
    }

    fn ensure_test_config() {
        CONFIG_INIT.get_or_init(|| {
            let tempdir = Arc::new(TempDir::new().expect("tempdir"));
            let config_path = tempdir.path().join("selvedge.toml");

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
            init_with_path(config_path).expect("init config");
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

    #[test]
    fn missing_config_child_reports_error() {
        if std::env::var_os("SELVEDGE_LOGGING_MISSING_CONFIG_CHILD").is_none() {
            return;
        }

        super::install_test_runtime(TestRecorder::default()).expect("install test logger");
        let error = super::selvedge_log!(LogLevel::Info, "missing config")
            .expect_err("missing config should return an error");

        assert!(matches!(
            error,
            super::EmitError::ReadConfig(selvedge_config::ConfigError::NotInitialized)
        ));
    }

    #[test]
    fn missing_runtime_child_reports_error() {
        if std::env::var_os("SELVEDGE_LOGGING_MISSING_RUNTIME_CHILD").is_none() {
            return;
        }

        let tempdir = TempDir::new().expect("tempdir");
        let config_path = tempdir.path().join("selvedge.toml");
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

        init_with_path(config_path).expect("init config");
        let error = super::selvedge_log!(LogLevel::Info, "missing runtime")
            .expect_err("missing runtime should return an error");

        assert!(matches!(error, super::EmitError::NotInitialized));
    }

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
