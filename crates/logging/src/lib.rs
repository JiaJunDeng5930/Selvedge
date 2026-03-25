#![doc = include_str!("../README.md")]

use std::{
    fmt::Display,
    io::{self, Write},
    sync::{Arc, LazyLock, Mutex, OnceLock, RwLock},
};

use selvedge_config::read;
use selvedge_config_model::LogFilter;
use tracing::{Event, Subscriber};
use tracing_log::LogTracer;
use tracing_subscriber::{Registry, layer::Context, layer::Layer, prelude::*};

static RUNTIME: LazyLock<RwLock<RuntimeState>> =
    LazyLock::new(|| RwLock::new(RuntimeState::Uninitialized));
static SUBSCRIBER_INSTALLED: OnceLock<()> = OnceLock::new();

#[doc(hidden)]
pub mod __private {
    pub use tracing;
}

pub fn init() -> Result<(), InitError> {
    install_subscriber()?;
    initialize_runtime(Arc::new(StdoutSink::default()), false)
}

#[derive(Debug)]
pub enum InitError {
    AlreadyInitialized,
    InstallLogTracer(log::SetLoggerError),
    InstallSubscriber(tracing::subscriber::SetGlobalDefaultError),
    RuntimeLockPoisoned,
}

impl Display for InitError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::AlreadyInitialized => formatter.write_str("logging has already been initialized"),
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

#[derive(Debug)]
pub enum EmitError {
    ReadConfig(selvedge_config::ConfigError),
}

impl Display for EmitError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ReadConfig(error) => write!(formatter, "failed to read logging config: {error}"),
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

#[macro_export]
macro_rules! selvedge_log {
    ($level:expr, $message:expr $(,)?) => {{
        match $crate::should_emit($level, module_path!()) {
            ::std::result::Result::Ok(true) => {
                match $level {
                    $crate::LogLevel::Trace => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::TRACE,
                        message = %$message
                    ),
                    $crate::LogLevel::Debug => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::DEBUG,
                        message = %$message
                    ),
                    $crate::LogLevel::Info => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::INFO,
                        message = %$message
                    ),
                    $crate::LogLevel::Warn => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::WARN,
                        message = %$message
                    ),
                    $crate::LogLevel::Error => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::ERROR,
                        message = %$message
                    ),
                }

                ::std::result::Result::<(), $crate::EmitError>::Ok(())
            }
            ::std::result::Result::Ok(false) => {
                ::std::result::Result::<(), $crate::EmitError>::Ok(())
            }
            ::std::result::Result::Err(error) => ::std::result::Result::Err(error),
        }
    }};
    ($level:expr, $message:expr; $($key:ident = $value:expr),+ $(,)?) => {{
        match $crate::should_emit($level, module_path!()) {
            ::std::result::Result::Ok(true) => {
                match $level {
                    $crate::LogLevel::Trace => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::TRACE,
                        message = %$message,
                        $($key = $crate::__private::tracing::field::display(&$value)),+
                    ),
                    $crate::LogLevel::Debug => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::DEBUG,
                        message = %$message,
                        $($key = $crate::__private::tracing::field::display(&$value)),+
                    ),
                    $crate::LogLevel::Info => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::INFO,
                        message = %$message,
                        $($key = $crate::__private::tracing::field::display(&$value)),+
                    ),
                    $crate::LogLevel::Warn => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::WARN,
                        message = %$message,
                        $($key = $crate::__private::tracing::field::display(&$value)),+
                    ),
                    $crate::LogLevel::Error => $crate::__private::tracing::event!(
                        $crate::__private::tracing::Level::ERROR,
                        message = %$message,
                        $($key = $crate::__private::tracing::field::display(&$value)),+
                    ),
                }

                ::std::result::Result::<(), $crate::EmitError>::Ok(())
            }
            ::std::result::Result::Ok(false) => {
                ::std::result::Result::<(), $crate::EmitError>::Ok(())
            }
            ::std::result::Result::Err(error) => ::std::result::Result::Err(error),
        }
    }};
}

enum RuntimeState {
    Uninitialized,
    Initialized(Arc<dyn EventSink>),
}

trait EventSink: Send + Sync {
    fn write(&self, event: LogEvent);
}

struct StdoutSink {
    writer: Mutex<io::Stdout>,
}

impl Default for StdoutSink {
    fn default() -> Self {
        Self {
            writer: Mutex::new(io::stdout()),
        }
    }
}

impl EventSink for StdoutSink {
    fn write(&self, event: LogEvent) {
        let mut writer = self.writer.lock().expect("stdout writer lock poisoned");
        let rendered = render_event(&event);

        writeln!(writer, "{rendered}").expect("write rendered event");
    }
}

#[derive(Default)]
struct SelvedgeLayer;

impl<S> Layer<S> for SelvedgeLayer
where
    S: Subscriber,
{
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let metadata = event.metadata();
        let level = capture_level(*metadata.level());
        let module_path = metadata.module_path().unwrap_or(metadata.target());
        let should_write = should_emit(level, module_path).unwrap_or(false);

        if !should_write {
            return;
        }

        let captured = capture_event(event);
        let sink = current_sink();

        sink.write(captured);
    }
}

fn install_subscriber() -> Result<(), InitError> {
    if SUBSCRIBER_INSTALLED.get().is_some() {
        return Ok(());
    }

    LogTracer::init().map_err(InitError::InstallLogTracer)?;
    let subscriber = Registry::default().with(SelvedgeLayer);

    tracing::subscriber::set_global_default(subscriber).map_err(InitError::InstallSubscriber)?;
    let _ = SUBSCRIBER_INSTALLED.set(());

    Ok(())
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

fn current_sink() -> Arc<dyn EventSink> {
    let runtime = RUNTIME.read().expect("logging runtime lock poisoned");

    match &*runtime {
        RuntimeState::Uninitialized => panic!("logging must be initialized before use"),
        RuntimeState::Initialized(sink) => sink.clone(),
    }
}

fn capture_event(event: &Event<'_>) -> LogEvent {
    let metadata = event.metadata();
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
        "level={} module={} file={} line={} message=\"{}\"",
        render_level(event.level),
        event.module_path,
        event.file,
        event.line,
        event.message
    );

    for (key, value) in &event.fields {
        rendered.push(' ');
        rendered.push_str(key);
        rendered.push('=');
        rendered.push_str(value);
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
    fn write(&self, event: LogEvent) {
        let mut events = self.events.lock().expect("test recorder lock");
        events.push(event);
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

        let error = super::selvedge_log!(LogLevel::Info, "missing config")
            .expect_err("missing config should return an error");

        assert!(matches!(
            error,
            super::EmitError::ReadConfig(selvedge_config::ConfigError::NotInitialized)
        ));
    }
}
