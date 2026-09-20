use std::{
    cell::RefCell,
    collections::{BTreeMap, VecDeque},
    rc::Rc,
    sync::Arc,
    time::Duration,
};

use serde_json::{Value, json};
use v8::{MapFnTo, inspector::*};

use crate::{
    HostRequest, HostResponse, ScriptCheckpoint, ScriptExecutionRequest, ScriptExecutionResult,
    ScriptHost, ScriptHostError, ScriptRuntimeError, checkpoint,
    worker::{Interruption, Worker},
};

const ENVIRONMENT: &str = include_str!("environment.js");
const MODULE_OPERATION: &str = "@selvedge/load-module";

pub(crate) fn bootstrap(
    source: String,
    timeout: Duration,
) -> Result<ScriptCheckpoint, ScriptRuntimeError> {
    let (worker, mut receive) = Worker::start(timeout, move |control| {
        run(None, source, "selvedge-bootstrap".into(), None, control)
    })?;
    worker.finish()?;
    let result = receive
        .try_recv()
        .map_err(|_| engine_error("worker stopped without a result"))??;
    if result.is_error {
        return Err(engine_error(format!(
            "bootstrap failed: {}",
            result.output["error"]
        )));
    }
    Ok(result.checkpoint)
}

pub(crate) async fn execute(
    request: ScriptExecutionRequest,
    host: Arc<dyn ScriptHost>,
    timeout: Duration,
) -> Result<ScriptExecutionResult, ScriptRuntimeError> {
    let (worker, mut receive) = Worker::start(timeout, move |control| {
        run(
            Some(request.checkpoint),
            request.source,
            request.source_name,
            Some(host),
            control,
        )
    })?;
    let control = worker.control();
    let result = tokio::select! {
        result = &mut receive => result,
        error = control.cancelled() => {
            if !worker.has_started() { return Err(error); }
            receive.await
        }
    }
    .map_err(|_| engine_error("worker stopped without a result"));
    worker.finish()?;
    result?
}

struct PendingHost {
    request: HostRequest,
    resolver: v8::Global<v8::PromiseResolver>,
}

#[derive(Default)]
struct BridgeState {
    ordinal: u64,
    pending: VecDeque<PendingHost>,
    promises: Vec<v8::Global<v8::Promise>>,
}

fn track_promise(
    scope: &mut v8::PinScope,
    args: v8::FunctionCallbackArguments,
    _: v8::ReturnValue,
) {
    if let Ok(promise) = v8::Local::<v8::Promise>::try_from(args.get(0)) {
        let promise = v8::Global::new(scope, promise);
        if let Some(state) = scope.get_slot_mut::<BridgeState>() {
            state.promises.push(promise);
        }
    }
}

fn host_callback(
    scope: &mut v8::PinScope,
    args: v8::FunctionCallbackArguments,
    mut result: v8::ReturnValue,
) {
    let Some(resolver) = v8::PromiseResolver::new(scope) else {
        return;
    };
    result.set(resolver.get_promise(scope).into());
    let operation = parse_operation(scope, &args);
    match operation {
        Ok(operation) => {
            let resolver = v8::Global::new(scope, resolver);
            if let Some(state) = scope.get_slot_mut::<BridgeState>() {
                let ordinal = state.ordinal;
                state.ordinal += 1;
                let request = match operation {
                    Operation::Command(name, arguments) => HostRequest::Command {
                        ordinal,
                        name,
                        arguments,
                    },
                    Operation::Module(specifier, referrer) => HostRequest::LoadModule {
                        ordinal,
                        specifier,
                        referrer,
                    },
                };
                state.pending.push_back(PendingHost { request, resolver });
            }
        }
        Err(message) => {
            if let Some(message) = v8::String::new(scope, &message) {
                let exception = v8::Exception::type_error(scope, message);
                resolver.reject(scope, exception);
            }
        }
    }
}

enum Operation {
    Command(String, Value),
    Module(String, String),
}

fn parse_operation(
    scope: &mut v8::PinScope,
    args: &v8::FunctionCallbackArguments,
) -> Result<Operation, String> {
    if !args.get(0).is_string() {
        return Err("host operation name must be a string".into());
    }
    let name = args.get(0).to_rust_string_lossy(scope);
    let argument = args.get(1);
    let arguments = if argument.is_undefined() {
        Value::Null
    } else {
        let serialized = v8::json::stringify(scope, argument)
            .ok_or("host arguments must be JSON serializable")?
            .to_rust_string_lossy(scope);
        serde_json::from_str(&serialized).map_err(|error| error.to_string())?
    };
    if name == MODULE_OPERATION {
        let specifier = arguments
            .get("specifier")
            .and_then(Value::as_str)
            .ok_or("module specifier must be a string")?;
        let referrer = arguments
            .get("referrer")
            .and_then(Value::as_str)
            .ok_or("module referrer must be a string")?;
        Ok(Operation::Module(specifier.into(), referrer.into()))
    } else {
        Ok(Operation::Command(name, arguments))
    }
}

struct InspectorClient;
impl V8InspectorClientImpl for InspectorClient {}

#[derive(Clone, Default)]
struct InspectorChannel {
    responses: Rc<RefCell<BTreeMap<i32, Value>>>,
    context_id: Rc<RefCell<Option<i64>>>,
}

impl ChannelImpl for InspectorChannel {
    fn send_response(&self, id: i32, message: v8::UniquePtr<StringBuffer>) {
        if let Some(message) = message.as_ref()
            && let Ok(value) = serde_json::from_str(&message.string().to_string())
        {
            self.responses.borrow_mut().insert(id, value);
        }
    }

    fn send_notification(&self, message: v8::UniquePtr<StringBuffer>) {
        if let Some(message) = message.as_ref()
            && let Ok(value) = serde_json::from_str::<Value>(&message.string().to_string())
            && value["method"] == "Runtime.executionContextCreated"
        {
            *self.context_id.borrow_mut() = value["params"]["context"]["id"].as_i64();
        }
    }

    fn flush_protocol_notifications(&self) {}
}

fn dispatch(session: &V8InspectorSession, id: i32, method: &str, params: Value) {
    let message = json!({"id": id, "method": method, "params": params}).to_string();
    session.dispatch_protocol_message(StringView::from(message.as_bytes()));
}

fn run(
    previous: Option<ScriptCheckpoint>,
    source: String,
    source_name: String,
    host: Option<Arc<dyn ScriptHost>>,
    control: Arc<Interruption>,
) -> Result<ScriptExecutionResult, ScriptRuntimeError> {
    if let Some(error) = control.error() {
        return Err(error);
    }
    let previous = previous.map(checkpoint::decode).transpose()?;
    let fresh = previous.is_none();
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| engine_error(error.to_string()))?;
    let refs = vec![
        v8::ExternalReference {
            function: host_callback.map_fn_to(),
        },
        v8::ExternalReference {
            function: track_promise.map_fn_to(),
        },
    ];
    let heap = v8::cppgc::Heap::create(v8::V8::get_current_platform(), Default::default());
    let params = v8::CreateParams::default().cpp_heap(heap);
    let mut isolate = match previous {
        None => v8::Isolate::snapshot_creator(Some(refs.into()), Some(params)),
        Some(previous) => v8::Isolate::snapshot_creator_from_existing_snapshot(
            previous,
            Some(refs.into()),
            Some(params),
        ),
    };
    isolate.set_microtasks_policy(v8::MicrotasksPolicy::Explicit);
    control.install(isolate.thread_safe_handle());
    isolate.set_slot(BridgeState::default());
    let inspector = V8Inspector::create(
        &mut isolate,
        V8InspectorClient::new(Box::new(InspectorClient)),
    );
    let outcome;
    {
        v8::scope!(let scope, &mut isolate);
        let context = v8::Context::new(scope, Default::default());
        let scope = &mut v8::ContextScope::new(scope, context);
        outcome = run_context(
            scope,
            context,
            &inspector,
            fresh,
            &source,
            &source_name,
            host.as_deref(),
            &executor,
            &control,
        );
        // SnapshotCreator must be consumed on every exit, including interrupted
        // evaluations. No Rust resolver or inspector native pointer may survive.
        scope.set_promise_hooks(None, None, None, None);
        scope.remove_slot::<BridgeState>();
        scope.cancel_terminate_execution();
        scope.set_default_context(context);
    }
    drop(inspector);
    control.remove_isolate();
    let blob = isolate.create_blob(v8::FunctionCodeHandling::Keep);
    let (output, is_error) = outcome?;
    if let Some(error) = control.error() {
        return Err(error);
    }
    let blob = blob.ok_or_else(|| engine_error("snapshot creation failed"))?;
    Ok(ScriptExecutionResult {
        checkpoint: checkpoint::encode(blob),
        output,
        is_error,
    })
}

#[allow(clippy::too_many_arguments)]
fn run_context(
    scope: &mut v8::PinScope,
    context: v8::Local<v8::Context>,
    inspector: &V8Inspector,
    fresh: bool,
    source: &str,
    source_name: &str,
    host: Option<&dyn ScriptHost>,
    executor: &tokio::runtime::Runtime,
    control: &Interruption,
) -> Result<(Value, bool), ScriptRuntimeError> {
    prepare_console(scope)?;
    let empty = StringView::from(&b""[..]);
    inspector.context_created(context, 1, empty, empty);
    let channel = InspectorChannel::default();
    let session = inspector.connect(
        1,
        Channel::new(Box::new(channel.clone())),
        StringView::from(&b"{}"[..]),
        V8InspectorClientTrustLevel::FullyTrusted,
    );
    let result = (|| {
        let promise_hook = v8::Function::new(scope, track_promise)
            .ok_or_else(|| engine_error("could not create promise tracker"))?;
        scope.set_promise_hooks(Some(promise_hook), None, None, None);
        if fresh {
            let callback = v8::Function::new(scope, host_callback)
                .ok_or_else(|| engine_error("could not create host bridge"))?;
            let key = v8::String::new(scope, "__selvedgeHost")
                .ok_or_else(|| engine_error("could not allocate bridge name"))?;
            context
                .global(scope)
                .set(scope, key.into(), callback.into());
            evaluate_script(scope, ENVIRONMENT)?;
        } else {
            let console = runtime_property(scope, "console")?;
            set_console(scope, console)?;
        }
        dispatch(&session, 1, "Runtime.enable", json!({}));
        let context_id = channel
            .context_id
            .borrow()
            .ok_or_else(|| engine_error("inspector did not report its execution context"))?;
        let source_name = source_name.replace(['\r', '\n'], " ");
        dispatch(
            &session,
            2,
            "Runtime.evaluate",
            json!({
                "expression": format!("{source}\n//# sourceURL={source_name}"),
                "contextId": context_id,
                "replMode": true,
                "awaitPromise": true,
                "returnByValue": false,
                "generatePreview": false,
            }),
        );
        let mut response = drive(scope, &channel, host, executor, control, 2)?;
        if response["result"].get("exceptionDetails").is_none()
            && let Some(object_id) = response["result"]["result"].get("objectId").cloned()
        {
            // Serializing a successful value is optional. Retain the original
            // remote description when its graph cannot be represented as JSON.
            dispatch(
                &session,
                4,
                "Runtime.callFunctionOn",
                json!({
                    "objectId": object_id,
                    "functionDeclaration": "function () { return this; }",
                    "returnByValue": true,
                    "generatePreview": false,
                }),
            );
            let serialized = drive(scope, &channel, host, executor, control, 4)?;
            if serialized.get("error").is_none()
                && serialized["result"].get("exceptionDetails").is_none()
                && serialized["result"]["result"].get("value").is_some()
            {
                response["result"]["result"] = serialized["result"]["result"].clone();
            }
        }
        dispatch(
            &session,
            3,
            "Runtime.globalLexicalScopeNames",
            json!({"executionContextId": context_id}),
        );
        let names = channel
            .responses
            .borrow_mut()
            .remove(&3)
            .and_then(|response| response["result"].get("names").cloned())
            .unwrap_or_else(|| json!([]));
        let names = v8::String::new(scope, &names.to_string())
            .and_then(|text| v8::json::parse(scope, text))
            .ok_or_else(|| engine_error("could not parse lexical names"))?;
        call_runtime(scope, "setLexicalNames", &[names])?;
        let logs = call_runtime(scope, "takeLogs", &[])?;
        let logs = v8::json::stringify(scope, logs)
            .ok_or_else(|| engine_error("could not serialize console logs"))?
            .to_rust_string_lossy(scope);
        let logs: Value =
            serde_json::from_str(&logs).map_err(|error| engine_error(error.to_string()))?;
        let rejections = ensure_settled(scope, control)?;
        // Exercise the next restoration's requirement before committing bytes;
        // a nonconfigurable console must not become a permanently broken state.
        prepare_console(scope)?;
        make_output(response, logs, rejections)
    })();
    drop(session);
    inspector.context_destroyed(context);
    result
}

fn drive(
    scope: &mut v8::PinScope,
    channel: &InspectorChannel,
    host: Option<&dyn ScriptHost>,
    executor: &tokio::runtime::Runtime,
    control: &Interruption,
    response_id: i32,
) -> Result<Value, ScriptRuntimeError> {
    loop {
        if let Some(error) = control.error() {
            return Err(error);
        }
        scope.perform_microtask_checkpoint();
        if let Some(error) = control.error() {
            return Err(error);
        }
        let pending = scope
            .get_slot_mut::<BridgeState>()
            .and_then(|state| state.pending.pop_front());
        if let Some(pending) = pending {
            let host = host.ok_or_else(|| engine_error("bootstrap cannot invoke the host"))?;
            let response = executor.block_on(async {
                tokio::select! {
                    biased;
                    error = control.cancelled() => Err(error),
                    response = host.call(pending.request.clone()) => response.map_err(ScriptRuntimeError::Host),
                }
            })?;
            if let (HostRequest::LoadModule { .. }, HostResponse::ModuleError { message }) =
                (&pending.request, &response)
            {
                let message = v8::String::new(scope, message)
                    .ok_or_else(|| engine_error("could not allocate module error"))?;
                let error = v8::Exception::error(scope, message);
                let resolver = v8::Local::new(scope, pending.resolver);
                resolver.reject(scope, error);
                continue;
            }
            let response = match (&pending.request, response) {
                (HostRequest::Command { .. }, HostResponse::Command(value)) => value,
                (
                    HostRequest::LoadModule { .. },
                    HostResponse::Module {
                        source,
                        resolved_specifier,
                    },
                ) => json!({"source":source,"resolved_specifier":resolved_specifier}),
                _ => {
                    return Err(ScriptRuntimeError::Host(ScriptHostError {
                        message: "host response kind does not match the request".into(),
                    }));
                }
            };
            let text = v8::String::new(scope, &response.to_string())
                .ok_or_else(|| engine_error("could not allocate host response"))?;
            let value = v8::json::parse(scope, text)
                .ok_or_else(|| engine_error("could not parse host response"))?;
            let resolver = v8::Local::new(scope, pending.resolver);
            resolver.resolve(scope, value);
            continue;
        }
        if let Some(response) = channel.responses.borrow_mut().remove(&response_id) {
            return Ok(response);
        }
        return Err(executor.block_on(control.cancelled()));
    }
}

fn make_output(
    response: Value,
    logs: Value,
    rejections: Vec<String>,
) -> Result<(Value, bool), ScriptRuntimeError> {
    if let Some(error) = response.get("error") {
        return Err(engine_error(format!(
            "inspector evaluation failed: {error}"
        )));
    }
    let result = &response["result"];
    let value = &result["result"];
    let mut output = json!({
        "value": value.get("value").or_else(|| value.get("unserializableValue")).cloned().unwrap_or(Value::Null),
        "value_type": value.get("type").cloned().unwrap_or(Value::Null),
        "logs": logs,
    });
    let is_error = result.get("exceptionDetails").is_some() || !rejections.is_empty();
    if let Some(exception) = result.get("exceptionDetails") {
        output["error"] = exception["exception"]
            .get("description")
            .or_else(|| exception.get("text"))
            .cloned()
            .unwrap_or_else(|| json!("script threw an exception"));
    } else if value.get("value").is_none()
        && value.get("unserializableValue").is_none()
        && let Some(description) = value.get("description")
    {
        output["value"] = description.clone();
    }
    if !rejections.is_empty() {
        let error = rejections.join("\n");
        output["error"] = match output.get("error").and_then(Value::as_str) {
            Some(existing) => json!(format!("{existing}\n{error}")),
            None => json!(error),
        };
    }
    Ok((output, is_error))
}

fn ensure_settled(
    scope: &mut v8::PinScope,
    control: &Interruption,
) -> Result<Vec<String>, ScriptRuntimeError> {
    scope.perform_microtask_checkpoint();
    if let Some(error) = control.error() {
        return Err(error);
    }
    let Some(state) = scope.get_slot_mut::<BridgeState>() else {
        return Err(engine_error("host bridge is missing"));
    };
    if !state.pending.is_empty() {
        return Err(engine_error(
            "output serialization started a host operation",
        ));
    }
    let promises = std::mem::take(&mut state.promises);
    let mut unsettled = 0;
    let mut rejections = Vec::new();
    for promise in promises {
        let promise = v8::Local::new(scope, promise);
        match promise.state() {
            v8::PromiseState::Pending => unsettled += 1,
            v8::PromiseState::Rejected if !promise.has_handler() => {
                let reason = promise.result(scope);
                let message = v8::Exception::create_message(scope, reason);
                rejections.push(format!(
                    "Unhandled promise rejection: {}",
                    message.get(scope).to_rust_string_lossy(scope)
                ));
            }
            _ => {}
        }
    }
    if unsettled != 0 {
        return Err(ScriptRuntimeError::UnsettledPromises(unsettled));
    }
    Ok(rejections)
}

fn prepare_console(scope: &mut v8::PinScope) -> Result<(), ScriptRuntimeError> {
    let hidden = v8::undefined(scope);
    set_console(scope, hidden.into())
}

fn set_console(
    scope: &mut v8::PinScope,
    value: v8::Local<v8::Value>,
) -> Result<(), ScriptRuntimeError> {
    let key = v8::String::new(scope, "console")
        .ok_or_else(|| engine_error("could not allocate console property name"))?;
    let global = scope.get_current_context().global(scope);
    if global.define_own_property(scope, key.into(), value, v8::PropertyAttribute::NONE)
        != Some(true)
    {
        return Err(engine_error(
            "console must remain configurable for checkpoint restoration",
        ));
    }
    Ok(())
}

fn runtime_property<'s>(
    scope: &mut v8::PinScope<'s, '_>,
    name: &str,
) -> Result<v8::Local<'s, v8::Value>, ScriptRuntimeError> {
    let global = scope.get_current_context().global(scope);
    let runtime_key = v8::String::new(scope, "__selvedgeRuntime")
        .ok_or_else(|| engine_error("could not allocate runtime property name"))?;
    let runtime = global
        .get(scope, runtime_key.into())
        .and_then(|runtime| v8::Local::<v8::Object>::try_from(runtime).ok())
        .ok_or_else(|| engine_error("runtime housekeeping object is missing"))?;
    let key = v8::String::new(scope, name)
        .ok_or_else(|| engine_error("could not allocate runtime member name"))?;
    runtime
        .get(scope, key.into())
        .ok_or_else(|| engine_error("runtime housekeeping member is missing"))
}

fn call_runtime<'s>(
    scope: &mut v8::PinScope<'s, '_>,
    name: &str,
    arguments: &[v8::Local<'s, v8::Value>],
) -> Result<v8::Local<'s, v8::Value>, ScriptRuntimeError> {
    let method = v8::Local::<v8::Function>::try_from(runtime_property(scope, name)?)
        .map_err(|_| engine_error("runtime housekeeping member is not a function"))?;
    let receiver = v8::undefined(scope);
    method
        .call(scope, receiver.into(), arguments)
        .ok_or_else(|| engine_error("runtime housekeeping call failed"))
}

fn evaluate_script(scope: &mut v8::PinScope, source: &str) -> Result<String, ScriptRuntimeError> {
    v8::tc_scope!(let scope, scope);
    let text = v8::String::new(scope, source)
        .ok_or_else(|| engine_error("could not allocate JavaScript source"))?;
    let result = v8::Script::compile(scope, text, None).and_then(|script| script.run(scope));
    result
        .map(|value| value.to_rust_string_lossy(scope))
        .ok_or_else(|| {
            engine_error(
                scope
                    .exception()
                    .map(|error| error.to_rust_string_lossy(scope))
                    .unwrap_or_else(|| "JavaScript execution was interrupted".into()),
            )
        })
}

fn engine_error(message: impl Into<String>) -> ScriptRuntimeError {
    ScriptRuntimeError::Engine(message.into())
}
