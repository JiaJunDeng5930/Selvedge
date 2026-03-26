#![doc = include_str!("../README.md")]

use std::{
    fmt::Display,
    io::{self, Write},
    sync::{Arc, LazyLock, Mutex, OnceLock, RwLock},
};

use selvedge_config::read;
use selvedge_config_model::LogFilter;
use tracing::{Event, Metadata, Subscriber};
use tracing_log::{LogTracer, NormalizeEvent};
use tracing_subscriber::{Registry, layer::Context, layer::Layer, prelude::*};

static RUNTIME: LazyLock<RwLock<RuntimeState>> =
    LazyLock::new(|| RwLock::new(RuntimeState::Uninitialized));
static SUBSCRIBER_INSTALLED: OnceLock<()> = OnceLock::new();

pub fn init() -> Result<(), InitError> {
    validate_config_ready()?;
    initialize_runtime(Arc::new(StderrSink::default()), false)?;

    if let Err(error) = install_subscriber() {
        if matches!(error, InitError::InstallSubscriber(_)) {
            reset_runtime();
        }
        return Err(error);
    }

    Ok(())
}

#[derive(Debug)]
pub enum InitError {
    AlreadyInitialized,
    ReadConfig(selvedge_config::ConfigError),
    InstallLogTracer(log::SetLoggerError),
    InstallSubscriber(tracing::subscriber::SetGlobalDefaultError),
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
            Self::InstallLogTracer(error) => {
                write!(formatter, "failed to install log tracer: {error}")
            }
            Self::InstallSubscriber(error) => {
                write!(formatter, "failed to install tracing subscriber: {error}")
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
#[doc(hidden)]
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

#[doc(hidden)]
pub fn should_emit(level: LogLevel, module_path: &str) -> Result<bool, EmitError> {
    read(|config| {
        let minimum_level = config.logging.effective_level_for(module_path);

        level.meets_filter(minimum_level)
    })
    .map_err(EmitError::from)
}

#[doc(hidden)]
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

#[doc(hidden)]
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

#[derive(Default)]
struct SelvedgeLayer;

impl<S> Layer<S> for SelvedgeLayer
where
    S: Subscriber,
{
    fn enabled(&self, metadata: &Metadata<'_>, _ctx: Context<'_, S>) -> bool {
        let level = capture_level(*metadata.level());
        let module_path = metadata.module_path().unwrap_or(metadata.target());

        should_emit(level, module_path).unwrap_or(true)
    }

    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let normalized_metadata = event.normalized_metadata();
        let metadata = normalized_metadata
            .as_ref()
            .unwrap_or_else(|| event.metadata());
        let level = capture_level(*metadata.level());
        let module_path = metadata.module_path().unwrap_or(metadata.target());
        let should_write =
            should_emit(level, module_path).expect("logging subscriber failed to read config");

        if !should_write {
            return;
        }

        let captured = capture_event(event);
        let sink = current_sink().expect("logging subscriber is not initialized");

        sink.write(captured)
            .expect("logging subscriber failed to write event");
    }
}

fn install_subscriber() -> Result<(), InitError> {
    if SUBSCRIBER_INSTALLED.get().is_some() {
        return Ok(());
    }

    let subscriber = Registry::default().with(SelvedgeLayer);
    tracing::subscriber::set_global_default(subscriber).map_err(InitError::InstallSubscriber)?;
    let _ = SUBSCRIBER_INSTALLED.set(());

    if let Err(error) = LogTracer::init() {
        panic!("failed to install log tracer after subscriber setup: {error}");
    }

    Ok(())
}

fn validate_config_ready() -> Result<(), InitError> {
    read(|config| {
        let _ = config.logging.level;
    })
    .map_err(InitError::from)
}

fn initialize_runtime(sink: Arc<dyn EventSink>, replace_existing: bool) -> Result<(), InitError> {
    let mut runtime = RUNTIME
        .write()
        .map_err(|_| InitError::RuntimeLockPoisoned)?;

    match &mut *runtime {
        RuntimeState::Uninitialized => {
            *runtime = RuntimeState::Initialized(sink);
            Ok(())
        }
        RuntimeState::Initialized(current) if replace_existing => {
            *current = sink;
            Ok(())
        }
        RuntimeState::Initialized(_) => Err(InitError::AlreadyInitialized),
    }
}

fn reset_runtime() {
    let mut runtime = RUNTIME.write().expect("logging runtime lock poisoned");
    *runtime = RuntimeState::Uninitialized;
}

fn current_sink() -> Result<Arc<dyn EventSink>, EmitError> {
    let runtime = RUNTIME.read().map_err(|_| EmitError::RuntimeLockPoisoned)?;

    match &*runtime {
        RuntimeState::Uninitialized => Err(EmitError::NotInitialized),
        RuntimeState::Initialized(sink) => Ok(sink.clone()),
    }
}

fn capture_event(event: &Event<'_>) -> LogEvent {
    let normalized_metadata = event.normalized_metadata();
    let metadata = normalized_metadata
        .as_ref()
        .unwrap_or_else(|| event.metadata());
    let mut visitor = EventFieldVisitor::default();

    event.record(&mut visitor);

    LogEvent {
        level: capture_level(*metadata.level()),
        message: visitor.take_message().unwrap_or_default(),
        module_path: metadata
            .module_path()
            .unwrap_or(metadata.target())
            .to_owned(),
        file: metadata.file().unwrap_or("").to_owned(),
        line: metadata.line().unwrap_or_default(),
        fields: visitor.finish(),
    }
}

fn capture_level(level: tracing::Level) -> LogLevel {
    match level {
        tracing::Level::TRACE => LogLevel::Trace,
        tracing::Level::DEBUG => LogLevel::Debug,
        tracing::Level::INFO => LogLevel::Info,
        tracing::Level::WARN => LogLevel::Warn,
        tracing::Level::ERROR => LogLevel::Error,
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

#[derive(Default)]
struct EventFieldVisitor {
    message: Option<String>,
    fields: Vec<(String, String)>,
}

impl EventFieldVisitor {
    fn finish(self) -> Vec<(String, String)> {
        self.fields
    }

    fn take_message(&mut self) -> Option<String> {
        self.message.take()
    }
}

impl tracing::field::Visit for EventFieldVisitor {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        let rendered = format!("{value:?}");

        if field.name() == "message" {
            self.message = Some(trim_debug_quotes(&rendered));
            return;
        }

        self.fields
            .push((field.name().to_owned(), trim_debug_quotes(&rendered)));
    }

    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        if field.name() == "message" {
            self.message = Some(value.to_owned());
            return;
        }

        self.fields
            .push((field.name().to_owned(), value.to_owned()));
    }
}

fn trim_debug_quotes(value: &str) -> String {
    value
        .strip_prefix('"')
        .and_then(|trimmed| trimmed.strip_suffix('"'))
        .unwrap_or(value)
        .to_owned()
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
    install_subscriber()?;
    initialize_runtime(Arc::new(recorder), true)
}

#[cfg(test)]
mod tests {
    use std::{
        collections::BTreeMap,
        process::Command,
        sync::{Arc, Mutex, OnceLock},
    };

    use selvedge_config::{init_with_path, update_runtime};
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
        update_runtime("logging.level", "info").expect("set log level");
        update_runtime("logging.module_levels", BTreeMap::<String, String>::new())
            .expect("clear module levels");
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
        update_runtime("logging.level", "info").expect("set log level");
        update_runtime("logging.module_levels", BTreeMap::<String, String>::new())
            .expect("clear module levels");
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
        update_runtime("logging.level", "info").expect("set info");
        update_runtime("logging.module_levels", BTreeMap::<String, String>::new())
            .expect("clear module levels");
        recorder.clear();

        selvedge_log!(LogLevel::Debug, "debug should be filtered")
            .expect("debug event should evaluate cleanly");
        assert!(recorder.take().is_empty());

        update_runtime("logging.level", "debug").expect("set debug");
        selvedge_log!(LogLevel::Debug, "debug should pass").expect("emit debug event");

        let events = recorder.take();
        let event = events.first().expect("captured event");
        assert_eq!(event.message, "debug should pass");
    }

    #[test]
    fn concurrent_logging_keeps_messages_distinct() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();

        init_for_test(recorder.clone()).expect("init test logger");
        update_runtime("logging.level", "info").expect("set log level");
        update_runtime("logging.module_levels", BTreeMap::<String, String>::new())
            .expect("clear module levels");
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
    fn dependency_logs_are_filtered_in_subscriber_layer() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();

        init_for_test(recorder.clone()).expect("init test logger");
        update_runtime("logging.level", "warn").expect("set warn level");
        update_runtime("logging.module_levels", BTreeMap::<String, String>::new())
            .expect("clear module levels");
        recorder.clear();

        log::info!("dependency info");
        assert!(recorder.take().is_empty());

        log::error!("dependency error");

        let events = recorder.take();
        let event = events.first().expect("captured dependency error");
        assert_eq!(event.level, LogLevel::Error);
        assert_eq!(event.message, "dependency error");
    }

    #[test]
    fn dependency_logs_respect_module_level_overrides() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();

        init_for_test(recorder.clone()).expect("init test logger");
        update_runtime("logging.level", "warn").expect("set warn level");
        update_runtime("logging.module_levels.selvedge_logging::tests", "debug")
            .expect("set module override");
        recorder.clear();

        log::info!("dependency info through module override");

        let events = recorder.take();
        let event = events.first().expect("captured dependency info");
        assert_eq!(event.level, LogLevel::Info);
        assert_eq!(event.message, "dependency info through module override");
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
    fn init_failure_does_not_leave_runtime_initialized() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::subscriber_conflict_child_keeps_runtime_uninitialized")
            .env("SELVEDGE_LOGGING_SUBSCRIBER_CONFLICT_CHILD", "1")
            .output()
            .expect("run subscriber conflict child test");

        assert!(output.status.success(), "child test failed: {output:?}");
    }

    #[test]
    fn scoped_dispatcher_use_does_not_block_logging_init() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::scoped_dispatcher_child_allows_init")
            .env("SELVEDGE_LOGGING_SCOPED_DISPATCHER_CHILD", "1")
            .output()
            .expect("run scoped dispatcher child test");

        assert!(output.status.success(), "child test failed: {output:?}");
    }

    #[test]
    fn log_tracer_conflict_fails_fast() {
        let current_executable = std::env::current_exe().expect("current test executable");
        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::log_tracer_conflict_child_panics")
            .env("SELVEDGE_LOGGING_LOG_TRACER_CONFLICT_CHILD", "1")
            .output()
            .expect("run log tracer conflict child test");

        assert!(
            !output.status.success(),
            "child test unexpectedly passed: {output:?}"
        );
    }

    #[test]
    fn filtered_log_does_not_evaluate_message_or_fields() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();
        let message_counter = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let field_counter = Arc::new(std::sync::atomic::AtomicUsize::new(0));

        init_for_test(recorder.clone()).expect("init test logger");
        update_runtime("logging.level", "warn").expect("set warn level");
        update_runtime("logging.module_levels", BTreeMap::<String, String>::new())
            .expect("clear module levels");
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
    fn filtered_tracing_event_does_not_evaluate_payload() {
        let _guard = test_lock().lock().expect("test lock");
        ensure_test_config();
        let recorder = TestRecorder::default();
        let message_counter = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let field_counter = Arc::new(std::sync::atomic::AtomicUsize::new(0));

        init_for_test(recorder.clone()).expect("init test logger");
        update_runtime("logging.level", "warn").expect("set warn level");
        update_runtime("logging.module_levels", BTreeMap::<String, String>::new())
            .expect("clear module levels");
        recorder.clear();

        let message_counter_for_event = Arc::clone(&message_counter);
        let field_counter_for_event = Arc::clone(&field_counter);
        tracing::event!(
            tracing::Level::INFO,
            message = %counted_message(&message_counter_for_event),
            worker = tracing::field::display(counted_field(&field_counter_for_event)),
        );

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

        init_for_test(TestRecorder::default()).expect("init test logger");
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

    #[test]
    fn subscriber_conflict_child_keeps_runtime_uninitialized() {
        if std::env::var_os("SELVEDGE_LOGGING_SUBSCRIBER_CONFLICT_CHILD").is_none() {
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
        tracing::subscriber::set_global_default(tracing_subscriber::Registry::default())
            .expect("install conflicting subscriber");

        let init_error = super::init().expect_err("logging init should fail");
        assert!(matches!(init_error, super::InitError::InstallSubscriber(_)));

        let emit_error = super::selvedge_log!(LogLevel::Info, "after failed init")
            .expect_err("runtime should remain uninitialized after failed init");
        assert!(matches!(emit_error, super::EmitError::NotInitialized));
    }

    #[test]
    fn scoped_dispatcher_child_allows_init() {
        if std::env::var_os("SELVEDGE_LOGGING_SCOPED_DISPATCHER_CHILD").is_none() {
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
        tracing::subscriber::with_default(tracing_subscriber::Registry::default(), || {
            tracing::info!("scoped dispatcher warmup");
        });

        super::init().expect("scoped dispatcher should not block global init");
    }

    #[test]
    fn log_tracer_conflict_child_panics() {
        if std::env::var_os("SELVEDGE_LOGGING_LOG_TRACER_CONFLICT_CHILD").is_none() {
            return;
        }

        #[derive(Debug)]
        struct ExistingLogger;

        impl log::Log for ExistingLogger {
            fn enabled(&self, _metadata: &log::Metadata<'_>) -> bool {
                true
            }

            fn log(&self, _record: &log::Record<'_>) {}

            fn flush(&self) {}
        }

        static EXISTING_LOGGER: ExistingLogger = ExistingLogger;

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
        log::set_logger(&EXISTING_LOGGER).expect("install conflicting logger");
        log::set_max_level(log::LevelFilter::Trace);

        let _ = super::init();
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
