use std::{
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicU8, Ordering},
        mpsc,
    },
    thread::{self, JoinHandle},
    time::Duration,
};

use tokio::sync::{Notify, oneshot};

use crate::{ScriptExecutionResult, ScriptRuntimeError};

const RUNNING: u8 = 0;
const CANCELLED: u8 = 1;
const TIMED_OUT: u8 = 2;
const FINISHED: u8 = 3;

pub(crate) struct Interruption {
    state: AtomicU8,
    started: AtomicBool,
    isolate: Mutex<Option<v8::IsolateHandle>>,
    changed: Notify,
}

impl Interruption {
    fn new() -> Self {
        Self {
            state: AtomicU8::new(RUNNING),
            started: AtomicBool::new(false),
            isolate: Mutex::new(None),
            changed: Notify::new(),
        }
    }

    pub(crate) fn install(&self, isolate: v8::IsolateHandle) {
        let mut slot = self
            .isolate
            .lock()
            .expect("interruption lock is not poisoned");
        if self.error().is_some() {
            isolate.terminate_execution();
        }
        *slot = Some(isolate);
    }

    pub(crate) fn remove_isolate(&self) {
        self.isolate
            .lock()
            .expect("interruption lock is not poisoned")
            .take();
    }

    fn interrupt(&self, state: u8) {
        if self
            .state
            .compare_exchange(RUNNING, state, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok()
        {
            if let Some(isolate) = self
                .isolate
                .lock()
                .expect("interruption lock is not poisoned")
                .as_ref()
            {
                isolate.terminate_execution();
            }
            self.changed.notify_waiters();
        }
    }

    pub(crate) fn error(&self) -> Option<ScriptRuntimeError> {
        match self.state.load(Ordering::SeqCst) {
            CANCELLED => Some(ScriptRuntimeError::Cancelled),
            TIMED_OUT => Some(ScriptRuntimeError::Timeout),
            _ => None,
        }
    }

    pub(crate) async fn cancelled(&self) -> ScriptRuntimeError {
        loop {
            let notified = self.changed.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if let Some(error) = self.error() {
                return error;
            }
            notified.await;
        }
    }
}

pub(crate) struct Worker {
    interruption: Arc<Interruption>,
    watchdog_stop: mpsc::Sender<()>,
    watchdog: Option<JoinHandle<()>>,
    completion: mpsc::Receiver<()>,
}

type ExecutionResult = Result<ScriptExecutionResult, ScriptRuntimeError>;
type EngineWork = Box<dyn FnOnce() + Send>;

fn engine_queue() -> Result<&'static mpsc::Sender<EngineWork>, ScriptRuntimeError> {
    static QUEUE: OnceLock<Result<mpsc::Sender<EngineWork>, String>> = OnceLock::new();
    QUEUE
        .get_or_init(|| {
            let (send, receive) = mpsc::channel::<EngineWork>();
            thread::Builder::new()
                .name("script-runtime".into())
                .spawn(move || {
                    // SnapshotCreator mutates V8's shared read-only heap. Its complete
                    // lifetime is serialized, and all V8 work stays on its init thread.
                    v8::V8::initialize_platform(v8::new_default_platform(0, false).make_shared());
                    v8::V8::initialize();
                    for work in receive {
                        work();
                    }
                })
                .map_err(|error| error.to_string())?;
            Ok(send)
        })
        .as_ref()
        .map_err(|error| ScriptRuntimeError::Engine(error.clone()))
}

impl Worker {
    pub(crate) fn start(
        timeout: Duration,
        work: impl FnOnce(Arc<Interruption>) -> Result<ScriptExecutionResult, ScriptRuntimeError>
        + Send
        + 'static,
    ) -> Result<(Self, oneshot::Receiver<ExecutionResult>), ScriptRuntimeError> {
        let queue = engine_queue()?;
        let interruption = Arc::new(Interruption::new());
        let (watchdog_stop, stop) = mpsc::channel();
        let control = interruption.clone();
        let watchdog = thread::Builder::new()
            .name("script-watchdog".into())
            .spawn(move || {
                if matches!(
                    stop.recv_timeout(timeout),
                    Err(mpsc::RecvTimeoutError::Timeout)
                ) {
                    control.interrupt(TIMED_OUT);
                }
            })
            .map_err(|error| ScriptRuntimeError::Engine(error.to_string()))?;
        let (finished, completion) = mpsc::channel();
        let worker = Self {
            interruption: interruption.clone(),
            watchdog_stop,
            watchdog: Some(watchdog),
            completion,
        };
        let (send, receive) = oneshot::channel();
        queue
            .send(Box::new(move || {
                interruption.started.store(true, Ordering::SeqCst);
                let result = match interruption.error() {
                    Some(error) => Err(error),
                    None => work(interruption.clone()),
                };
                interruption.remove_isolate();
                interruption.state.store(FINISHED, Ordering::SeqCst);
                let _ = send.send(result);
                let _ = finished.send(());
            }))
            .map_err(|_| ScriptRuntimeError::Engine("engine worker stopped".into()))?;
        Ok((worker, receive))
    }

    pub(crate) fn control(&self) -> Arc<Interruption> {
        self.interruption.clone()
    }

    pub(crate) fn has_started(&self) -> bool {
        self.interruption.started.load(Ordering::SeqCst)
    }

    pub(crate) fn finish(mut self) -> Result<(), ScriptRuntimeError> {
        self.completion
            .recv()
            .map_err(|_| ScriptRuntimeError::Engine("engine worker stopped".into()))?;
        let _ = self.watchdog_stop.send(());
        if let Some(watchdog) = self.watchdog.take() {
            watchdog
                .join()
                .map_err(|_| ScriptRuntimeError::Engine("watchdog panicked".into()))?;
        }
        Ok(())
    }
}

impl Drop for Worker {
    fn drop(&mut self) {
        self.interruption.interrupt(CANCELLED);
        let _ = self.watchdog_stop.send(());
    }
}
