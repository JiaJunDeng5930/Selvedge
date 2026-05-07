use std::collections::VecDeque;
use std::fs;
use std::future;
use std::path::PathBuf;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;

use selvedge_systemd::{
    ServiceStatus, StartServiceOutcome, SystemctlBackend, SystemctlBackendConfig,
    SystemctlProcessOutput, SystemctlProcessRunner, SystemdBackend, SystemdClient, SystemdConfig,
    SystemdError, SystemdScope,
};
use tokio::sync::Mutex as AsyncMutex;
use tokio::time::timeout;

static TEST_LOCK: LazyLock<AsyncMutex<()>> = LazyLock::new(|| AsyncMutex::new(()));

#[tokio::test]
async fn query_maps_backend_statuses_without_ready_semantics() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(vec![
        Ok(ServiceStatus::Active),
        Ok(ServiceStatus::Inactive),
        Ok(ServiceStatus::Activating),
        Ok(ServiceStatus::Failed {
            message: "exit code 1".to_owned(),
        }),
        Ok(ServiceStatus::NotInstalled),
        Ok(ServiceStatus::Unknown {
            raw_state: "maintenance".to_owned(),
        }),
    ]);
    let client = SystemdClient::new(valid_config(), backend.clone()).expect("client");

    assert_eq!(
        client.query_service_status().await,
        Ok(ServiceStatus::Active)
    );
    assert_eq!(
        client.query_service_status().await,
        Ok(ServiceStatus::Inactive)
    );
    assert_eq!(
        client.query_service_status().await,
        Ok(ServiceStatus::Activating)
    );
    assert_eq!(
        client.query_service_status().await,
        Ok(ServiceStatus::Failed {
            message: "exit code 1".to_owned()
        })
    );
    assert_eq!(
        client.query_service_status().await,
        Ok(ServiceStatus::NotInstalled)
    );
    assert_eq!(
        client.query_service_status().await,
        Ok(ServiceStatus::Unknown {
            raw_state: "maintenance".to_owned()
        })
    );
    assert_eq!(backend.query_calls(), 6);
}

#[tokio::test]
async fn start_service_uses_status_preflight_and_avoids_duplicate_start_requests() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(vec![
        Ok(ServiceStatus::Inactive),
        Ok(ServiceStatus::Active),
        Ok(ServiceStatus::Activating),
        Ok(ServiceStatus::NotInstalled),
    ]);
    backend.push_start(Ok(StartServiceOutcome::StartRequested));
    let client = SystemdClient::new(valid_config(), backend.clone()).expect("client");

    assert_eq!(
        client.start_service().await,
        Ok(StartServiceOutcome::StartRequested)
    );
    assert_eq!(
        client.start_service().await,
        Ok(StartServiceOutcome::AlreadyRunning)
    );
    assert_eq!(
        client.start_service().await,
        Ok(StartServiceOutcome::AlreadyStarting)
    );
    assert_eq!(
        client.start_service().await,
        Err(SystemdError::UnitNotFound)
    );
    assert_eq!(backend.start_calls(), 1);
}

#[tokio::test]
async fn start_service_returns_backend_rejection() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(vec![Ok(ServiceStatus::Inactive)]);
    backend.push_start(Err(SystemdError::StartRejected("masked".to_owned())));
    let client = SystemdClient::new(valid_config(), backend).expect("client");

    assert_eq!(
        client.start_service().await,
        Err(SystemdError::StartRejected("masked".to_owned()))
    );
}

#[tokio::test]
async fn unavailable_backend_errors_are_preserved() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(vec![Err(SystemdError::Unavailable(
        "dbus unavailable".to_owned(),
    ))]);
    let client = SystemdClient::new(valid_config(), backend).expect("client");

    assert_eq!(
        client.query_service_status().await,
        Err(SystemdError::Unavailable("dbus unavailable".to_owned()))
    );
}

#[tokio::test]
async fn wait_service_active_returns_active_or_failed_status() {
    let _guard = TEST_LOCK.lock().await;
    let active_backend = FakeSystemdBackend::new(vec![
        Ok(ServiceStatus::Activating),
        Ok(ServiceStatus::Active),
    ]);
    let active_client =
        SystemdClient::new(wait_config(Duration::from_millis(50)), active_backend).expect("client");
    assert_eq!(
        active_client.wait_service_active().await,
        Ok(ServiceStatus::Active)
    );

    let failed_backend = FakeSystemdBackend::new(vec![
        Ok(ServiceStatus::Activating),
        Ok(ServiceStatus::Failed {
            message: "unit crashed".to_owned(),
        }),
    ]);
    let failed_client =
        SystemdClient::new(wait_config(Duration::from_millis(50)), failed_backend).expect("client");
    assert_eq!(
        failed_client.wait_service_active().await,
        Ok(ServiceStatus::Failed {
            message: "unit crashed".to_owned()
        })
    );
}

#[tokio::test]
async fn wait_service_active_times_out() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::repeat(ServiceStatus::Activating);
    let client =
        SystemdClient::new(wait_config(Duration::from_millis(10)), backend).expect("client");

    assert_eq!(
        client.wait_service_active().await,
        Err(SystemdError::Timeout)
    );
}

#[tokio::test]
async fn wait_service_active_times_out_when_status_query_stalls() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(Vec::new());
    let client =
        SystemdClient::new(wait_config(Duration::from_millis(10)), backend).expect("client");

    assert_eq!(
        client.wait_service_active().await,
        Err(SystemdError::Timeout)
    );
}

#[tokio::test]
async fn wait_service_active_returns_error_for_oversized_timeout() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(vec![Ok(ServiceStatus::Active)]);
    let client = SystemdClient::new(wait_config(Duration::MAX), backend.clone()).expect("client");

    assert_eq!(
        client.wait_service_active().await,
        Err(SystemdError::Timeout)
    );
    assert_eq!(backend.query_calls(), 0);
}

#[tokio::test]
async fn dropping_wait_future_stops_polling_without_cancelled_error() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::repeat(ServiceStatus::Activating);
    let client = SystemdClient::new(wait_config(Duration::from_millis(100)), backend.clone())
        .expect("client");

    let mut wait = Box::pin(client.wait_service_active());
    assert!(
        timeout(Duration::from_millis(15), wait.as_mut())
            .await
            .is_err()
    );
    let calls_before_drop = backend.query_calls();
    drop(wait);
    tokio::time::sleep(Duration::from_millis(20)).await;

    assert_eq!(backend.query_calls(), calls_before_drop);
}

#[tokio::test]
async fn invalid_unit_name_is_rejected_before_backend_calls() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(vec![Ok(ServiceStatus::Active)]);

    let result = SystemdClient::new(
        SystemdConfig {
            unit_name: " ".to_owned(),
            ..valid_config()
        },
        backend.clone(),
    );

    assert!(matches!(result, Err(SystemdError::InvalidUnitName)));
    assert_eq!(backend.query_calls(), 0);
}

#[tokio::test]
async fn config_validation_reports_first_invalid_field_in_order() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(vec![Ok(ServiceStatus::Active)]);

    let result = SystemdClient::new(
        SystemdConfig {
            unit_name: "selvedge server.service".to_owned(),
            operation_timeout: Duration::ZERO,
            poll_interval: Duration::ZERO,
        },
        backend.clone(),
    );
    assert!(matches!(result, Err(SystemdError::InvalidUnitName)));

    let result = SystemdClient::new(
        SystemdConfig {
            operation_timeout: Duration::ZERO,
            ..valid_config()
        },
        backend.clone(),
    );
    assert!(matches!(result, Err(SystemdError::InvalidOperationTimeout)));

    let result = SystemdClient::new(
        SystemdConfig {
            poll_interval: Duration::ZERO,
            ..valid_config()
        },
        backend,
    );
    assert!(matches!(result, Err(SystemdError::InvalidPollInterval)));
}

#[tokio::test]
async fn systemctl_backend_uses_runner_and_maps_show_output() {
    let _guard = TEST_LOCK.lock().await;
    let runner = RecordingProcessRunner::new(vec![Ok(SystemctlProcessOutput {
        exit_code: Some(0),
        stdout: b"LoadState=loaded\nActiveState=active\n".to_vec(),
        stderr: Vec::new(),
    })]);
    let backend = SystemctlBackend::new_with_runner(systemctl_config(), runner.clone())
        .expect("systemctl backend");

    assert_eq!(
        backend
            .query_status("selvedge-server.service", Duration::from_millis(123))
            .await,
        Ok(ServiceStatus::Active)
    );
    assert_eq!(
        runner.calls(),
        vec![ProcessCall {
            program: "/bin/systemctl".to_owned(),
            args: vec![
                "--system".to_owned(),
                "show".to_owned(),
                "--property=LoadState".to_owned(),
                "--property=ActiveState".to_owned(),
                "selvedge-server.service".to_owned(),
            ],
            timeout: Duration::from_millis(123),
        }]
    );
}

#[tokio::test]
async fn systemctl_backend_maps_missing_unit_unknown_state_and_start_rejection() {
    let _guard = TEST_LOCK.lock().await;
    let runner = RecordingProcessRunner::new(vec![
        Ok(SystemctlProcessOutput {
            exit_code: Some(1),
            stdout: b"LoadState=not-found\nActiveState=inactive\n".to_vec(),
            stderr: Vec::new(),
        }),
        Ok(SystemctlProcessOutput {
            exit_code: Some(0),
            stdout: b"LoadState=loaded\nActiveState=maintenance\n".to_vec(),
            stderr: Vec::new(),
        }),
        Ok(SystemctlProcessOutput {
            exit_code: Some(1),
            stdout: Vec::new(),
            stderr: b"masked".to_vec(),
        }),
    ]);
    let backend =
        SystemctlBackend::new_with_runner(systemctl_config(), runner).expect("systemctl backend");

    assert_eq!(
        backend
            .query_status("selvedge-server.service", Duration::from_millis(50))
            .await,
        Ok(ServiceStatus::NotInstalled)
    );
    assert_eq!(
        backend
            .query_status("selvedge-server.service", Duration::from_millis(50))
            .await,
        Ok(ServiceStatus::Unknown {
            raw_state: "maintenance".to_owned()
        })
    );
    assert_eq!(
        backend
            .start_unit("selvedge-server.service", Duration::from_millis(50))
            .await,
        Err(SystemdError::StartRejected("masked".to_owned()))
    );
}

#[tokio::test]
async fn public_operations_revalidate_mutated_config_before_backend_calls() {
    let _guard = TEST_LOCK.lock().await;
    let backend = FakeSystemdBackend::new(vec![Ok(ServiceStatus::Active)]);
    let mut client = SystemdClient::new(valid_config(), backend.clone()).expect("client");
    client.config.unit_name = " ".to_owned();

    assert_eq!(
        client.query_service_status().await,
        Err(SystemdError::InvalidUnitName)
    );
    assert_eq!(
        client.start_service().await,
        Err(SystemdError::InvalidUnitName)
    );
    assert_eq!(
        client.wait_service_active().await,
        Err(SystemdError::InvalidUnitName)
    );
    assert_eq!(backend.query_calls(), 0);
}

#[test]
fn tui_and_web_do_not_depend_on_systemd_crate() {
    let root = env!("CARGO_MANIFEST_DIR");
    let tui_manifest = format!("{root}/../tui/Cargo.toml");
    if let Ok(manifest) = fs::read_to_string(tui_manifest) {
        assert!(!manifest.contains("selvedge-systemd"));
    }
    let web_manifest =
        fs::read_to_string(format!("{root}/../web/Cargo.toml")).expect("web manifest");
    assert!(!web_manifest.contains("selvedge-systemd"));
}

#[derive(Clone)]
struct FakeSystemdBackend {
    state: Arc<Mutex<FakeSystemdState>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ProcessCall {
    program: String,
    args: Vec<String>,
    timeout: Duration,
}

#[derive(Clone)]
struct RecordingProcessRunner {
    state: Arc<Mutex<RecordingProcessRunnerState>>,
}

struct RecordingProcessRunnerState {
    calls: Vec<ProcessCall>,
    outputs: VecDeque<Result<SystemctlProcessOutput, SystemdError>>,
}

impl RecordingProcessRunner {
    fn new(outputs: Vec<Result<SystemctlProcessOutput, SystemdError>>) -> Self {
        Self {
            state: Arc::new(Mutex::new(RecordingProcessRunnerState {
                calls: Vec::new(),
                outputs: outputs.into(),
            })),
        }
    }

    fn calls(&self) -> Vec<ProcessCall> {
        self.state
            .lock()
            .expect("process runner lock")
            .calls
            .clone()
    }
}

impl SystemctlProcessRunner for RecordingProcessRunner {
    async fn run(
        &self,
        program: &str,
        args: &[String],
        timeout: Duration,
    ) -> Result<SystemctlProcessOutput, SystemdError> {
        let mut state = self.state.lock().expect("process runner lock");
        state.calls.push(ProcessCall {
            program: program.to_owned(),
            args: args.to_vec(),
            timeout,
        });
        state
            .outputs
            .pop_front()
            .unwrap_or_else(|| Err(SystemdError::BackendFailure("no output".to_owned())))
    }
}

struct FakeSystemdState {
    query_calls: usize,
    start_calls: usize,
    query_results: VecDeque<Result<ServiceStatus, SystemdError>>,
    start_results: VecDeque<Result<StartServiceOutcome, SystemdError>>,
    repeat_status: Option<ServiceStatus>,
}

impl FakeSystemdBackend {
    fn new(query_results: Vec<Result<ServiceStatus, SystemdError>>) -> Self {
        Self {
            state: Arc::new(Mutex::new(FakeSystemdState {
                query_calls: 0,
                start_calls: 0,
                query_results: query_results.into(),
                start_results: VecDeque::new(),
                repeat_status: None,
            })),
        }
    }

    fn repeat(status: ServiceStatus) -> Self {
        Self {
            state: Arc::new(Mutex::new(FakeSystemdState {
                query_calls: 0,
                start_calls: 0,
                query_results: VecDeque::new(),
                start_results: VecDeque::new(),
                repeat_status: Some(status),
            })),
        }
    }

    fn push_start(&self, result: Result<StartServiceOutcome, SystemdError>) {
        self.state
            .lock()
            .expect("fake systemd lock")
            .start_results
            .push_back(result);
    }

    fn query_calls(&self) -> usize {
        self.state.lock().expect("fake systemd lock").query_calls
    }

    fn start_calls(&self) -> usize {
        self.state.lock().expect("fake systemd lock").start_calls
    }
}

impl SystemdBackend for FakeSystemdBackend {
    async fn query_status(
        &self,
        _unit_name: &str,
        _operation_timeout: Duration,
    ) -> Result<ServiceStatus, SystemdError> {
        let next = {
            let mut state = self.state.lock().expect("fake systemd lock");
            state.query_calls += 1;
            state.query_results.pop_front().or_else(|| {
                state
                    .repeat_status
                    .as_ref()
                    .map(|status| Ok(status.clone()))
            })
        };

        if let Some(result) = next {
            return result;
        }

        future::pending().await
    }

    async fn start_unit(
        &self,
        _unit_name: &str,
        _operation_timeout: Duration,
    ) -> Result<StartServiceOutcome, SystemdError> {
        let mut state = self.state.lock().expect("fake systemd lock");
        state.start_calls += 1;
        state
            .start_results
            .pop_front()
            .unwrap_or(Ok(StartServiceOutcome::StartRequested))
    }
}

fn valid_config() -> SystemdConfig {
    SystemdConfig {
        unit_name: "selvedge-server.service".to_owned(),
        operation_timeout: Duration::from_millis(50),
        poll_interval: Duration::from_millis(1),
    }
}

fn wait_config(timeout: Duration) -> SystemdConfig {
    SystemdConfig {
        operation_timeout: timeout,
        poll_interval: Duration::from_millis(1),
        ..valid_config()
    }
}

fn systemctl_config() -> SystemctlBackendConfig {
    SystemctlBackendConfig {
        systemctl_path: PathBuf::from("/bin/systemctl"),
        scope: SystemdScope::System,
    }
}
