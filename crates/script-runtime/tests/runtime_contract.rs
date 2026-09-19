use std::{
    collections::HashMap,
    future::Future,
    pin::Pin,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

use selvedge_script_runtime::{
    HostRequest, HostResponse, ScriptCheckpoint, ScriptExecutionRequest, ScriptExecutionResult,
    ScriptHost, ScriptHostError, ScriptRuntime, ScriptRuntimeError,
};
use serde_json::json;

#[derive(Default)]
struct Host {
    identity: &'static str,
    modules: HashMap<String, String>,
    requests: Arc<Mutex<Vec<HostRequest>>>,
    pending_dropped: Arc<AtomicBool>,
}

impl ScriptHost for Host {
    fn call(
        &self,
        request: HostRequest,
    ) -> Pin<Box<dyn Future<Output = Result<HostResponse, ScriptHostError>> + Send>> {
        self.requests
            .lock()
            .expect("request log")
            .push(request.clone());
        let identity = self.identity;
        let modules = self.modules.clone();
        let dropped = self.pending_dropped.clone();
        Box::pin(async move {
            match request {
                HostRequest::Command {
                    name, arguments, ..
                } => match name.as_str() {
                    "identity" => Ok(HostResponse::Command(json!(identity))),
                    "fail" => Err(ScriptHostError {
                        message: "journal prefix mismatch".into(),
                    }),
                    "never" => {
                        struct MarkDrop(Arc<AtomicBool>);
                        impl Drop for MarkDrop {
                            fn drop(&mut self) {
                                self.0.store(true, Ordering::SeqCst);
                            }
                        }
                        let _mark = MarkDrop(dropped);
                        std::future::pending().await
                    }
                    _ => {
                        tokio::time::sleep(Duration::from_millis(1)).await;
                        Ok(HostResponse::Command(arguments))
                    }
                },
                HostRequest::LoadModule { specifier, .. } => {
                    let Some(source) = modules.get(&specifier).cloned() else {
                        return Ok(HostResponse::ModuleError {
                            message: format!("missing module: {specifier}"),
                        });
                    };
                    Ok(HostResponse::Module {
                        source,
                        resolved_specifier: specifier,
                    })
                }
            }
        })
    }
}

async fn execute(
    runtime: &ScriptRuntime,
    checkpoint: ScriptCheckpoint,
    source: &str,
    host: Arc<Host>,
) -> ScriptExecutionResult {
    runtime
        .execute(
            ScriptExecutionRequest {
                checkpoint,
                source: source.into(),
                source_name: "runtime-contract.js".into(),
            },
            host,
        )
        .await
        .expect("runtime execution")
}

fn base(runtime: &ScriptRuntime) -> ScriptCheckpoint {
    runtime.base_checkpoint().expect("base checkpoint")
}

#[tokio::test]
async fn lexical_bindings_closures_and_source_survive_repeated_independent_copies() {
    let runtime = ScriptRuntime::new("globalThis.boot = 7".into()).expect("runtime");
    let host = Arc::new(Host::default());
    let original = execute(&runtime, base(&runtime), "let count = 40; const closed = (() => { let n = 3; return {next() {return ++n}, get() {return n}} })(); function total() { return count + closed.get() }; count += 2; total()", host.clone()).await;
    assert_eq!(original.output["value"], 45);
    let parent = execute(
        &runtime,
        original.checkpoint.clone(),
        "count = 100; closed.next(); total()",
        host.clone(),
    )
    .await;
    let child = execute(
        &runtime,
        original.checkpoint,
        "count = 200; closed.next(); [total(),boot]",
        host.clone(),
    )
    .await;
    assert_eq!(parent.output["value"], 104);
    assert_eq!(child.output["value"], json!([204, 7]));
    let parent = execute(
        &runtime,
        parent.checkpoint,
        "[count,closed.get(),total.toString(),environment.names().includes('count')]",
        host.clone(),
    )
    .await;
    assert_eq!(parent.output["value"][0], 100);
    assert_eq!(parent.output["value"][1], 4);
    assert!(
        parent.output["value"][2]
            .as_str()
            .expect("function source")
            .contains("count + closed.get()")
    );
    assert_eq!(parent.output["value"][3], true);
    assert!(parent.output.get("globals").is_none());
    let child = execute(&runtime, child.checkpoint, "closed.next(); total()", host).await;
    assert_eq!(child.output["value"], 205);
}

#[tokio::test]
async fn module_cache_closures_sources_and_referrers_are_checkpointed() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let source = "const helper = await modules.load('helper.js'); let count = helper.start; module.exports = { next() { return ++count }, get() { return count } };";
    let host = Arc::new(Host {
        modules: HashMap::from([
            ("counter.js".into(), source.into()),
            ("helper.js".into(), "exports.start = 5".into()),
        ]),
        ..Host::default()
    });
    let initial = execute(
        &runtime,
        base(&runtime),
        "const counter = await modules.load('counter.js'); counter.next()",
        host.clone(),
    )
    .await;
    assert_eq!(initial.output["value"], 6);
    let child = execute(
        &runtime,
        initial.checkpoint.clone(),
        "counter.next(); [counter.get(),modules.source('counter.js'),modules.list()]",
        host.clone(),
    )
    .await;
    assert_eq!(
        child.output["value"],
        json!([7, source, ["counter.js", "helper.js"]])
    );
    let parent = execute(
        &runtime,
        initial.checkpoint,
        "(await modules.load('counter.js')).get()",
        host.clone(),
    )
    .await;
    assert_eq!(parent.output["value"], 6);
    let requests = host.requests.lock().expect("request log");
    assert!(
        matches!(&requests[..], [HostRequest::LoadModule { ordinal: 0, referrer, .. }, HostRequest::LoadModule { ordinal: 1, referrer: second, .. }] if referrer.is_empty() && second == "counter.js")
    );
}

#[tokio::test]
async fn host_functions_rebind_and_detached_operations_are_drained_in_order() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let first_host = Arc::new(Host {
        identity: "first",
        ..Host::default()
    });
    let second_host = Arc::new(Host {
        identity: "second",
        ..Host::default()
    });
    let first = execute(&runtime, base(&runtime), "const identify = () => __selvedgeHost('identity',{}); let identity = await identify(); identity", first_host).await;
    assert_eq!(first.output["value"], "first");
    let second = execute(&runtime, first.checkpoint, "identity = await identify(); void (async () => { const a = await __selvedgeHost('echo', 1); const b = await __selvedgeHost('echo', 2); globalThis.detached = a+b; })(); identity", second_host.clone()).await;
    assert_eq!(second.output["value"], "second");
    let final_result = execute(&runtime, second.checkpoint, "detached", second_host.clone()).await;
    assert_eq!(final_result.output["value"], 3);
    let requests = second_host.requests.lock().expect("request log");
    let ordinals: Vec<_> = requests
        .iter()
        .map(|request| match request {
            HostRequest::Command { ordinal, .. } | HostRequest::LoadModule { ordinal, .. } => {
                *ordinal
            }
        })
        .collect();
    assert_eq!(ordinals, [0, 1, 2]);
}

#[tokio::test]
async fn ordinary_exceptions_preserve_state_and_console_logs() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let host = Arc::new(Host::default());
    let error = execute(
        &runtime,
        base(&runtime),
        "let preserved = 3; console.log('before', preserved); throw new Error('ordinary failure')",
        host.clone(),
    )
    .await;
    assert!(error.is_error);
    assert!(
        error.output["error"]
            .as_str()
            .expect("error")
            .contains("ordinary failure")
    );
    assert_eq!(
        error.output["logs"],
        json!([{"level":"log","values":["before",3]}])
    );
    let result = execute(
        &runtime,
        error.checkpoint,
        "preserved += 1; preserved",
        host,
    )
    .await;
    assert_eq!(result.output["value"], 4);
    assert_eq!(result.output["logs"], json!([]));
}

#[tokio::test]
async fn host_errors_cannot_be_caught_to_continue_new_effects() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let host = Arc::new(Host::default());
    let error = runtime.execute(ScriptExecutionRequest { checkpoint: base(&runtime), source: "try { await __selvedgeHost('fail', {}); } catch (_) {} await __selvedgeHost('echo', 'forbidden');".into(), source_name: "fatal-host.js".into() }, host.clone()).await.expect_err("fatal host error");
    assert!(matches!(error, ScriptRuntimeError::Host(_)));
    assert_eq!(host.requests.lock().expect("requests").len(), 1);
    let result = execute(&runtime, base(&runtime), "2+2", host).await;
    assert_eq!(result.output["value"], 4);
}

#[tokio::test]
async fn cpu_loops_microtask_loops_and_pending_promises_time_out_without_poisoning_runtime() {
    let runtime = ScriptRuntime::new(String::new())
        .expect("runtime")
        .with_execution_timeout(Duration::from_millis(150));
    let host = Arc::new(Host::default());
    for source in [
        "while (true) {}",
        "await new Promise(() => {})",
        "Promise.resolve().then(function loop() { return Promise.resolve().then(loop) });",
    ] {
        let result = runtime
            .execute(
                ScriptExecutionRequest {
                    checkpoint: base(&runtime),
                    source: source.into(),
                    source_name: "timeout.js".into(),
                },
                host.clone(),
            )
            .await;
        assert!(
            matches!(result, Err(ScriptRuntimeError::Timeout)),
            "{result:?}"
        );
    }
    let runtime = runtime.with_execution_timeout(Duration::from_secs(3));
    assert_eq!(
        execute(&runtime, base(&runtime), "6*7", host).await.output["value"],
        42
    );
}

#[tokio::test]
async fn non_json_results_keep_successful_state_without_evaluating_source_again() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let host = Arc::new(Host::default());
    let circular = execute(
        &runtime,
        base(&runtime),
        "globalThis.evaluations = (globalThis.evaluations ?? 0) + 1; let x = {}; x.self = x; x",
        host.clone(),
    )
    .await;
    assert!(!circular.is_error, "{}", circular.output);
    assert_eq!(circular.output["value_type"], "object");
    assert!(circular.output["value"].as_str().is_some());
    let restored = execute(
        &runtime,
        circular.checkpoint,
        "[x.self === x, evaluations]",
        host.clone(),
    )
    .await;
    assert_eq!(restored.output["value"], json!([true, 1]));

    let bigint = execute(
        &runtime,
        base(&runtime),
        "let x = 1; ({v: 1n})",
        host.clone(),
    )
    .await;
    assert!(!bigint.is_error, "{}", bigint.output);
    assert_eq!(bigint.output["value_type"], "object");
    assert!(bigint.output["value"].as_str().is_some());
    let restored = execute(&runtime, bigint.checkpoint, "x", host.clone()).await;
    assert_eq!(restored.output["value"], 1);

    let ordinary = execute(
        &runtime,
        base(&runtime),
        "({answer: 42, nested: [null, true, {word: 'yes'}]})",
        host,
    )
    .await;
    assert!(!ordinary.is_error);
    assert_eq!(
        ordinary.output["value"],
        json!({"answer":42,"nested":[null,true,{"word":"yes"}]})
    );
}

#[tokio::test]
async fn checkpoint_restoration_requirements_are_checked_before_returning_state() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let host = Arc::new(Host::default());
    let initial = execute(&runtime, base(&runtime), "let kept = 5; kept", host.clone()).await;
    let broken = runtime.execute(
        ScriptExecutionRequest {
            checkpoint: initial.checkpoint.clone(),
            source: "kept = 9; Object.defineProperty(globalThis, 'console', {value: console, configurable: false}); 2".into(),
            source_name: "console-restore.js".into(),
        },
        host.clone(),
    ).await.expect_err("an unrestorable console is rejected before checkpointing");
    assert!(
        broken
            .to_string()
            .contains("console must remain configurable")
    );
    let restored = execute(
        &runtime,
        initial.checkpoint,
        "console.log('restored'); kept",
        host.clone(),
    )
    .await;
    assert_eq!(restored.output["value"], 5);
    assert_eq!(
        restored.output["logs"],
        json!([{"level":"log","values":["restored"]}])
    );

    let shadowed = execute(
        &runtime,
        base(&runtime),
        "let globalThis = {console: {}}; let JSON = {}; let kept = 10; 1",
        host.clone(),
    )
    .await;
    assert!(!shadowed.is_error, "{}", shadowed.output);
    let restored = execute(
        &runtime,
        shadowed.checkpoint,
        "kept += 2; console.log('working'); kept",
        host,
    )
    .await;
    assert_eq!(restored.output["value"], 12);
    assert_eq!(
        restored.output["logs"],
        json!([{"level":"log","values":["working"]}])
    );
}

#[tokio::test]
async fn detached_rejections_report_errors_and_late_handlers_are_respected() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let host = Arc::new(Host::default());
    let rejected = execute(
        &runtime,
        base(&runtime),
        "let x = 0; (async () => { x = 2; throw new Error('detached'); })(); 1",
        host.clone(),
    )
    .await;
    assert!(rejected.is_error);
    assert_eq!(rejected.output["value"], 1);
    assert!(
        rejected.output["error"]
            .as_str()
            .expect("unhandled rejection")
            .contains("detached")
    );
    let restored = execute(&runtime, rejected.checkpoint, "x", host.clone()).await;
    assert!(!restored.is_error);
    assert_eq!(restored.output["value"], 2);

    let handled = execute(&runtime, base(&runtime), "let x = 0; const rejected = (async () => { x = 2; throw new Error('handled later'); })(); void __selvedgeHost('echo', null).then(() => rejected.catch(() => { x = 3; })); 1", host.clone()).await;
    assert!(!handled.is_error, "{}", handled.output);
    assert!(handled.output.get("error").is_none());
    let restored = execute(&runtime, handled.checkpoint, "x", host).await;
    assert_eq!(restored.output["value"], 3);
}

#[tokio::test]
async fn dropping_execution_cancels_pending_host_work() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let host = Arc::new(Host::default());
    let request = ScriptExecutionRequest {
        checkpoint: base(&runtime),
        source: "await __selvedgeHost('never', null)".into(),
        source_name: "cancel.js".into(),
    };
    let executing_runtime = runtime.clone();
    let executing_host = host.clone();
    let task =
        tokio::spawn(async move { executing_runtime.execute(request, executing_host).await });
    tokio::time::timeout(Duration::from_secs(3), async {
        while host.requests.lock().expect("requests").is_empty() {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("host operation started");
    task.abort();
    assert!(task.await.expect_err("cancelled execution").is_cancelled());
    tokio::time::timeout(Duration::from_secs(2), async {
        while !host.pending_dropped.load(Ordering::SeqCst) {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("cancelled host future was dropped");
    assert_eq!(
        execute(&runtime, base(&runtime), "21*2", host).await.output["value"],
        42
    );
}

#[tokio::test]
async fn suspended_async_work_is_rejected_even_when_the_top_level_has_finished() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    for source in [
        "const never = new Promise(() => {}); const background = (async () => { await never; await __selvedgeHost('identity', {}); })(); 1",
        "let resume; const suspended = (async () => { await new Promise(resolve => resume = resolve); await __selvedgeHost('identity', {}); })(); 1",
    ] {
        let host = Arc::new(Host::default());
        let result = runtime
            .execute(
                ScriptExecutionRequest {
                    checkpoint: base(&runtime),
                    source: source.into(),
                    source_name: "suspended.js".into(),
                },
                host.clone(),
            )
            .await;
        assert!(
            matches!(result, Err(ScriptRuntimeError::UnsettledPromises(_))),
            "{result:?}"
        );
        assert!(host.requests.lock().expect("requests").is_empty());
    }
}

#[tokio::test]
async fn missing_modules_are_catchable_and_concurrent_loads_wait_for_exports() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let host = Arc::new(Host {
        modules: HashMap::from([(
            "slow.js".into(),
            "await __selvedgeHost('echo', null); module.exports = { ready: true };".into(),
        )]),
        ..Host::default()
    });
    let loaded = execute(&runtime, base(&runtime), "let missing; try { await modules.load('missing.js'); } catch (error) { missing = error.message; } const both = await Promise.all([modules.load('slow.js'), modules.load('slow.js')]); [missing,both.map(module => module.ready)]", host.clone()).await;
    assert!(!loaded.is_error, "{}", loaded.output);
    assert_eq!(
        loaded.output["value"],
        json!(["missing module: missing.js", [true, true]])
    );
    let restored = execute(
        &runtime,
        loaded.checkpoint,
        "[missing,both[0] === both[1]]",
        host,
    )
    .await;
    assert_eq!(
        restored.output["value"],
        json!(["missing module: missing.js", true])
    );
}

#[test]
fn concurrent_runtime_creation_execution_and_drop_keep_bootstraps_independent() {
    let threads: Vec<_> = (0..8)
        .map(|identity| {
            std::thread::spawn(move || {
                let executor = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .expect("test executor");
                for _ in 0..2 {
                    let runtime = ScriptRuntime::new(format!("globalThis.identity = {identity}"))
                        .expect("runtime");
                    let result = executor.block_on(execute(
                        &runtime,
                        base(&runtime),
                        "identity + await __selvedgeHost('echo', 0)",
                        Arc::new(Host::default()),
                    ));
                    assert_eq!(result.output["value"], identity);
                }
            })
        })
        .collect();
    for thread in threads {
        thread.join().expect("concurrent runtime operation");
    }
}

#[tokio::test]
async fn queued_timeout_and_drop_do_not_wait_for_the_active_host_operation() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let active_runtime = runtime
        .clone()
        .with_execution_timeout(Duration::from_millis(500));
    let active_host = Arc::new(Host::default());
    let active_request = ScriptExecutionRequest {
        checkpoint: base(&runtime),
        source: "await __selvedgeHost('never', null)".into(),
        source_name: "active.js".into(),
    };
    let current_host = active_host.clone();
    let active =
        tokio::spawn(async move { active_runtime.execute(active_request, current_host).await });
    tokio::time::timeout(Duration::from_secs(3), async {
        while active_host.requests.lock().expect("requests").is_empty() {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("active operation started");
    let queued_runtime = runtime
        .clone()
        .with_execution_timeout(Duration::from_millis(30));
    let queued_host = Arc::new(Host::default());
    let queued = ScriptExecutionRequest {
        checkpoint: base(&runtime),
        source: "await __selvedgeHost('echo', 'must not start')".into(),
        source_name: "queued.js".into(),
    };
    let result = tokio::time::timeout(
        Duration::from_millis(150),
        queued_runtime.execute(queued.clone(), queued_host.clone()),
    )
    .await
    .expect("queue timeout returns promptly");
    assert!(matches!(result, Err(ScriptRuntimeError::Timeout)));
    let queued_task = tokio::spawn(async move { runtime.execute(queued, queued_host).await });
    tokio::task::yield_now().await;
    queued_task.abort();
    tokio::time::timeout(Duration::from_millis(100), queued_task)
        .await
        .expect("queued cancellation is nonblocking")
        .expect_err("queued task cancelled");
    active.abort();
    assert!(
        active
            .await
            .expect_err("active task cancelled")
            .is_cancelled()
    );
}

#[tokio::test]
async fn standard_heap_values_restore_and_unsupported_native_facilities_are_absent() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    let host = Arc::new(Host::default());
    let initial = execute(&runtime, base(&runtime), "const date = new Date(1234); const pattern = /test/gi; const map = new Map([['answer',42]]); const set = new Set([1,2]); const buffer = new ArrayBuffer(4); const bytes = new Uint8Array(buffer); bytes[0] = 9; const fulfilled = Promise.resolve(7); let captured; try { throw new Error('saved') } catch (error) { captured = error; } 'saved'", host.clone()).await;
    let restored = execute(&runtime, initial.checkpoint, "[date.getTime(),pattern.test('TEST'),map.get('answer'),set.has(2),buffer.byteLength,bytes[0],await fulfilled,captured.message,typeof Intl,typeof WebAssembly,typeof Temporal,typeof process,typeof fetch]", host).await;
    assert_eq!(
        restored.output["value"],
        json!([
            1234,
            true,
            42,
            true,
            4,
            9,
            7,
            "saved",
            "undefined",
            "undefined",
            "undefined",
            "undefined",
            "undefined"
        ])
    );
}

#[tokio::test]
async fn invalid_checkpoint_bytes_are_rejected_before_restoration() {
    let runtime = ScriptRuntime::new(String::new()).expect("runtime");
    for mut checkpoint in [
        ScriptCheckpoint(vec![]),
        ScriptCheckpoint(vec![1, 2, 3]),
        base(&runtime),
    ] {
        if let Some(last) = checkpoint.0.last_mut() {
            *last ^= 0xff;
        }
        let result = runtime
            .execute(
                ScriptExecutionRequest {
                    checkpoint,
                    source: "1".into(),
                    source_name: "bad-checkpoint.js".into(),
                },
                Arc::new(Host::default()),
            )
            .await;
        assert!(matches!(
            result,
            Err(ScriptRuntimeError::InvalidCheckpoint(_))
        ));
    }
}
