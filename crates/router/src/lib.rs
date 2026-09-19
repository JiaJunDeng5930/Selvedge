#![doc = include_str!("../README.md")]

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use selvedge_api::{ApiCallTerminalStatus, ApiExecutorConfig, spawn_model_call_tokio_task};
use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ClientEvent, CoreOutputEnvelope,
    CoreOutputMessage, DebugNoticeEvent, DetachReason, DomainEvent, DomainEventPublishRequest,
    EventClientReservationResult, EventControlMessage, EventIngress, EventIngressSender,
    ModelCallError, ModelCallErrorKind, ReserveClientSession, RouterAttachAdmissionResult,
    RouterCommand, RouterIngressMessage, RouterIngressSender, RouterIngressWeakSender,
    TaskCommandError, TaskRuntimeCommand, TaskRuntimeControl, TaskRuntimeExitNotice,
    TaskRuntimeSender, TaskStatusChangeOutcome, TaskStatusChangeResponder, ToolExecutionBranch,
    ToolExecutionBranchTarget, ToolExecutionRequest, ToolExecutionResult, ToolExecutionRunId,
    validate_router_command,
};
use selvedge_core::TaskRuntimeSpawnDeps;
use selvedge_db::{DbError, DbPool, read_task_status, transition_task_status};
use selvedge_domain_model::{TaskId, TaskLifecycleEvent, UnixTs};
use selvedge_task_runtime_factory::{
    RuntimeCreationError, create_task_runtime, recover_task_runtimes,
};
use tokio::task::JoinHandle;

pub struct RouterStartArgs {
    pub db: DbPool,
    pub events_tx: EventIngressSender,
    pub api_config: ApiExecutorConfig,
    pub tool_executor: Arc<dyn ToolExecutionSpawner>,
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
}

pub trait ToolExecutionSpawner: Send + Sync {
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        router_tx: RouterIngressWeakSender,
    ) -> Result<JoinHandle<()>, ToolExecutionSpawnError>;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolExecutionSpawnError {
    TokioSpawnFailed,
    ToolExecutorUnavailable,
}

pub struct RouterHandle {
    pub ingress_tx: RouterIngressSender,
    pub join_handle: JoinHandle<RouterExitStatus>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RouterExitStatus {
    Stopped,
    EventsMailboxClosed,
    RouterMailboxClosed,
    FatalError(String),
}

pub fn spawn_router(args: RouterStartArgs) -> RouterHandle {
    let (ingress_tx, ingress_rx) = tokio::sync::mpsc::unbounded_channel();
    let actor = RouterActor {
        db: args.db,
        events_tx: args.events_tx,
        api_config: args.api_config,
        tool_executor: args.tool_executor,
        core_spawn_deps: args.core_spawn_deps,
        router_tx: ingress_tx.downgrade(),
        ingress_rx,
        task_runtime_registry: HashMap::new(),
        model_call_tasks: HashMap::new(),
        tool_execution_tasks: HashMap::new(),
    };
    let join_handle = tokio::spawn(actor.run());

    RouterHandle {
        ingress_tx,
        join_handle,
    }
}

struct RouterActor {
    db: DbPool,
    events_tx: EventIngressSender,
    api_config: ApiExecutorConfig,
    tool_executor: Arc<dyn ToolExecutionSpawner>,
    core_spawn_deps: TaskRuntimeSpawnDeps,
    router_tx: RouterIngressWeakSender,
    ingress_rx: tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
    task_runtime_registry: HashMap<TaskId, RuntimeRegistryEntry>,
    model_call_tasks: HashMap<ApiEffectId, ActiveModelCall>,
    tool_execution_tasks: HashMap<ToolExecutionRunId, ActiveToolExecution>,
}

struct ActiveModelCall {
    task_id: TaskId,
    join_handle: JoinHandle<ApiCallTerminalStatus>,
}

struct ActiveToolExecution {
    task_id: TaskId,
    join_handle: JoinHandle<()>,
}

#[derive(Clone, Debug)]
struct RuntimeRegistryEntry {
    sender: TaskRuntimeSender,
    control: TaskRuntimeControl,
}

impl RouterActor {
    async fn run(mut self) -> RouterExitStatus {
        while let Some(ingress) = self.ingress_rx.recv().await {
            let result = match ingress {
                RouterIngressMessage::Command(command) => self.handle_command(command).await,
                RouterIngressMessage::Core(envelope) => self.handle_core(envelope).await,
                RouterIngressMessage::ApiOutput(envelope) => self.handle_api_output(envelope).await,
                RouterIngressMessage::Tool(result) => self.handle_tool_output(result).await,
                RouterIngressMessage::RuntimeExit(notice) => self.handle_runtime_exit(notice).await,
                RouterIngressMessage::PublishToEvents(request) => {
                    self.publish_domain_event(request).await
                }
                RouterIngressMessage::StopRouter => {
                    self.shutdown().await;
                    return RouterExitStatus::Stopped;
                }
            };

            if let Err(status) = result {
                self.shutdown().await;
                return status;
            }
        }

        self.shutdown().await;
        RouterExitStatus::RouterMailboxClosed
    }

    async fn handle_command(&mut self, command: RouterCommand) -> Result<(), RouterExitStatus> {
        if validate_router_command(&command).is_err() {
            settle_router_command(command, TaskCommandError::InvalidCommand);
            return self
                .publish_debug(None, "router command validation failed")
                .await;
        }

        match command {
            RouterCommand::AttachClient {
                session,
                admission_tx,
            } => self.reserve_client_session(session, admission_tx).await,
            RouterCommand::DetachClient { session } => {
                self.send_event(EventIngress::Control(EventControlMessage::DetachClient(
                    selvedge_command_model::DetachClient {
                        session,
                        reason: DetachReason::ClientRequested,
                    },
                )))
                .await
            }
            RouterCommand::UpdateSubscription {
                session,
                subscription,
            } => {
                self.send_event(EventIngress::Control(
                    EventControlMessage::UpdateSubscription(
                        selvedge_command_model::UpdateSubscription {
                            session,
                            subscription,
                        },
                    ),
                ))
                .await
            }
            RouterCommand::SendUserInput {
                task_id,
                message_text,
                responder,
            } => {
                self.route_task_local_command(
                    task_id,
                    TaskRuntimeCommand::UserInput {
                        message_text,
                        responder,
                    },
                )
                .await
            }
            RouterCommand::SendTaskInput {
                task_id,
                message_text,
                context,
                responder,
            } => {
                // Starting a task can execute its cursor, so scope must be checked before
                // runtime admission as well as inside the eventual delivery transaction.
                let db = self.db.clone();
                let replay_context = context.clone();
                let scoped_task_id = task_id.clone();
                match tokio::task::spawn_blocking(move || {
                    selvedge_db::validate_command_task_scope(
                        &db,
                        &replay_context,
                        &scoped_task_id,
                    )?;
                    // A completed delivery remains replayable if the target was later archived.
                    selvedge_db::read_command_operation(&db, &replay_context)
                })
                .await
                {
                    Ok(Ok(Some(result))) => {
                        responder.settle(Ok(result));
                        return Ok(());
                    }
                    Ok(Ok(None)) => {}
                    Ok(Err(error)) => {
                        responder.settle(Err(task_status_change_error(error)));
                        return Ok(());
                    }
                    Err(_) => {
                        responder.settle(Err(TaskCommandError::PersistenceFailed));
                        return Ok(());
                    }
                }
                let db = self.db.clone();
                let pending_task_id = task_id.clone();
                match tokio::task::spawn_blocking(move || {
                    let pending = selvedge_db::task_is_pending(&db, &pending_task_id)?;
                    let frozen = read_task_status(&db, &pending_task_id)?
                        == selvedge_domain_model::TaskStatus::Frozen;
                    Ok::<_, DbError>(pending || frozen)
                })
                .await
                {
                    Ok(Ok(true)) => {
                        let db = self.db.clone();
                        let outcome = tokio::task::spawn_blocking(move || {
                            selvedge_db::queue_user_input_with_context(
                                &db,
                                &task_id,
                                message_text,
                                now(),
                                &context,
                                serde_json::json!({"delivered": true}),
                            )
                        })
                        .await;
                        responder.settle(match outcome {
                            Ok(Ok(outcome)) => Ok(outcome.result),
                            Ok(Err(error)) => Err(task_status_change_error(error)),
                            Err(_) => Err(TaskCommandError::PersistenceFailed),
                        });
                        Ok(())
                    }
                    Ok(Ok(false)) => {
                        self.route_task_local_command(
                            task_id,
                            TaskRuntimeCommand::TaskInput {
                                message_text,
                                context,
                                responder,
                            },
                        )
                        .await
                    }
                    Ok(Err(error)) => {
                        responder.settle(Err(task_status_change_error(error)));
                        Ok(())
                    }
                    Err(_) => {
                        responder.settle(Err(TaskCommandError::PersistenceFailed));
                        Ok(())
                    }
                }
            }
            RouterCommand::ChangeTaskStatus {
                task_id,
                event,
                context,
                responder,
            } => {
                self.change_task_status_with_context(task_id, event, context, responder)
                    .await
            }
            RouterCommand::ArchiveTask { task_id, responder } => {
                self.change_task_status(task_id, TaskLifecycleEvent::Archive, responder)
                    .await
            }
            RouterCommand::FreezeTask { task_id, responder } => {
                self.change_task_status(task_id, TaskLifecycleEvent::Freeze, responder)
                    .await
            }
            RouterCommand::UnfreezeTask { task_id, responder } => {
                self.change_task_status(task_id, TaskLifecycleEvent::Unfreeze, responder)
                    .await
            }
            RouterCommand::StopTask { task_id, responder } => {
                self.change_task_status(task_id, TaskLifecycleEvent::Stop, responder)
                    .await
            }
            RouterCommand::RecoverCommandInvocation { invocation } => {
                self.recover_command_invocation(invocation).await
            }
            RouterCommand::EnsureTaskRuntime { task_id } => self.ensure_task_runtime(task_id).await,
            RouterCommand::EnsureMissingTaskRuntimes => self.ensure_missing_task_runtimes().await,
        }
    }

    async fn handle_core(&mut self, envelope: CoreOutputEnvelope) -> Result<(), RouterExitStatus> {
        // Core output is task-routed. Runtime identity gates registry ownership and exit cleanup;
        // queued core outputs already in ingress continue through normal task routing.
        let task_id = envelope.task_id;
        match envelope.message {
            CoreOutputMessage::RequestModelCall(request) => {
                if request.correlation.task_id != task_id {
                    return Ok(());
                }
                let correlation = request.correlation.clone();
                let db = self.db.clone();
                let status_task_id = task_id.clone();
                let status =
                    tokio::task::spawn_blocking(move || read_task_status(&db, &status_task_id))
                        .await;
                match status {
                    Ok(Ok(status)) if status.can_call_model() => {}
                    Ok(Ok(_)) => {
                        return self
                            .return_model_call_not_started(task_id, correlation)
                            .await;
                    }
                    Ok(Err(error)) => {
                        return self
                            .return_model_call_failure(
                                task_id,
                                correlation,
                                format!("model call task status read failed: {error}"),
                            )
                            .await;
                    }
                    Err(error) => {
                        return self
                            .return_model_call_failure(
                                task_id,
                                correlation,
                                format!("model call task status task failed: {error}"),
                            )
                            .await;
                    }
                }
                let effect_id = request.correlation.api_effect_id.clone();
                let join_handle = spawn_model_call_tokio_task(
                    request,
                    self.router_tx.clone(),
                    self.api_config.clone(),
                );
                if self.model_call_tasks.contains_key(&effect_id) {
                    join_handle.abort();
                    let _ = join_handle.await;
                    return Err(RouterExitStatus::FatalError(format!(
                        "duplicate API effect id '{}'",
                        effect_id.0
                    )));
                }
                self.model_call_tasks.insert(
                    effect_id,
                    ActiveModelCall {
                        task_id,
                        join_handle,
                    },
                );
                Ok(())
            }
            CoreOutputMessage::RequestToolExecution(request) => {
                if request.task_id != task_id {
                    return Ok(());
                }
                let fallback_request = request.clone();
                let db = self.db.clone();
                let status_task_id = task_id.clone();
                let status =
                    tokio::task::spawn_blocking(move || read_task_status(&db, &status_task_id))
                        .await;
                match status {
                    Ok(Ok(selvedge_domain_model::TaskStatus::Archived)) => {
                        let db = self.db.clone();
                        let invocation = selvedge_domain_model::CommandInvocationId {
                            task_id: task_id.clone(),
                            function_call_node_id: request.function_call_node_id,
                        };
                        if tokio::task::spawn_blocking(move || {
                            selvedge_db::read_admitted_command_call(&db, &invocation)
                        })
                        .await
                        .is_ok_and(|result| result.is_ok())
                        {
                            // Only the already admitted outer call may finish after archive.
                        } else {
                            return self
                                .publish_debug(
                                    Some(task_id),
                                    "tool execution rejected because task is archived",
                                )
                                .await;
                        }
                    }
                    Ok(Ok(_)) => {}
                    Ok(Err(_)) | Err(_) => {
                        return self
                            .handle_tool_output(tool_spawn_failed_result(fallback_request))
                            .await;
                    }
                }
                let tool_execution_run_id = request.tool_execution_run_id.clone();
                match self
                    .tool_executor
                    .spawn_tool_execution(request, self.router_tx.clone())
                {
                    Ok(join_handle) => {
                        if self
                            .tool_execution_tasks
                            .contains_key(&tool_execution_run_id)
                        {
                            join_handle.abort();
                            let _ = join_handle.await;
                            return Err(RouterExitStatus::FatalError(format!(
                                "duplicate tool execution run id '{}'",
                                tool_execution_run_id.0
                            )));
                        }
                        self.tool_execution_tasks.insert(
                            tool_execution_run_id,
                            ActiveToolExecution {
                                task_id,
                                join_handle,
                            },
                        );
                        Ok(())
                    }
                    Err(_) => {
                        self.handle_tool_output(tool_spawn_failed_result(fallback_request))
                            .await
                    }
                }
            }
            CoreOutputMessage::EnsureTaskRuntimes { task_ids } => {
                for task_id in task_ids {
                    self.ensure_task_runtime(task_id).await?;
                }
                Ok(())
            }
            CoreOutputMessage::PublishDomainEvent(request) => {
                if request.task_id != task_id {
                    return Ok(());
                }
                self.publish_domain_event(request).await
            }
            CoreOutputMessage::RuntimeReady => {
                self.publish_domain_event(DomainEventPublishRequest {
                    task_id,
                    event: DomainEvent::TaskRuntimeReady,
                })
                .await
            }
        }
    }

    async fn reserve_client_session(
        &mut self,
        session: selvedge_command_model::ClientSessionIdentity,
        admission_tx: selvedge_command_model::RouterAttachAdmissionSender,
    ) -> Result<(), RouterExitStatus> {
        let (result_tx, result_rx) = tokio::sync::oneshot::channel();
        let cleanup_session = session.clone();
        if self
            .events_tx
            .send(EventIngress::Control(
                EventControlMessage::ReserveClientSession(ReserveClientSession {
                    session,
                    result_tx,
                }),
            ))
            .await
            .is_err()
        {
            let _ = admission_tx.send(RouterAttachAdmissionResult::EventsMailboxClosed);
            return Err(RouterExitStatus::EventsMailboxClosed);
        }

        let (result, reserved) = match result_rx.await {
            Ok(EventClientReservationResult::Reserved) => {
                (RouterAttachAdmissionResult::Accepted, true)
            }
            Ok(EventClientReservationResult::DuplicateAttach) => {
                (RouterAttachAdmissionResult::DuplicateAttach, false)
            }
            Ok(EventClientReservationResult::ClientRegistryFull) => {
                (RouterAttachAdmissionResult::ClientRegistryFull, false)
            }
            Err(_) => (RouterAttachAdmissionResult::EventsMailboxClosed, false),
        };

        if admission_tx.send(result).is_err() && reserved {
            self.send_event(EventIngress::Control(EventControlMessage::DetachClient(
                selvedge_command_model::DetachClient {
                    session: cleanup_session,
                    reason: DetachReason::ClientDisconnected,
                },
            )))
            .await?;
        }
        Ok(())
    }

    async fn return_model_call_failure(
        &mut self,
        task_id: TaskId,
        correlation: ApiCallCorrelation,
        message: String,
    ) -> Result<(), RouterExitStatus> {
        let envelope = ApiOutputEnvelope::Failure {
            correlation,
            error: ModelCallError {
                kind: ModelCallErrorKind::Cancelled,
                message,
            },
        };
        if let Some(sender) = self
            .task_runtime_registry
            .get(&task_id)
            .map(|entry| entry.sender.clone())
        {
            return self
                .send_to_task_runtime(
                    task_id,
                    sender,
                    TaskRuntimeCommand::ApiModelReply(envelope),
                    false,
                )
                .await;
        }
        self.publish_debug(
            Some(task_id),
            "model call rejected without a live task runtime",
        )
        .await
    }

    async fn return_model_call_not_started(
        &mut self,
        task_id: TaskId,
        correlation: ApiCallCorrelation,
    ) -> Result<(), RouterExitStatus> {
        if let Some(sender) = self
            .task_runtime_registry
            .get(&task_id)
            .map(|entry| entry.sender.clone())
        {
            return self
                .send_to_task_runtime(
                    task_id,
                    sender,
                    TaskRuntimeCommand::ModelCallNotStarted { correlation },
                    false,
                )
                .await;
        }
        self.publish_debug(
            Some(task_id),
            "model call was not started because task runtime is not live",
        )
        .await
    }

    async fn handle_api_output(
        &mut self,
        envelope: ApiOutputEnvelope,
    ) -> Result<(), RouterExitStatus> {
        let (task_id, effect_id) = match &envelope {
            ApiOutputEnvelope::Success { correlation, .. }
            | ApiOutputEnvelope::Failure { correlation, .. } => (
                correlation.task_id.clone(),
                correlation.api_effect_id.clone(),
            ),
        };
        if let Some(active) = self.model_call_tasks.remove(&effect_id) {
            let _ = active.join_handle.await;
        }

        if let Some(sender) = self
            .task_runtime_registry
            .get(&task_id)
            .map(|entry| entry.sender.clone())
        {
            self.send_to_task_runtime(
                task_id,
                sender,
                TaskRuntimeCommand::ApiModelReply(envelope),
                false,
            )
            .await
        } else {
            self.publish_debug(Some(task_id), "stale api output discarded")
                .await
        }
    }

    async fn handle_tool_output(
        &mut self,
        result: ToolExecutionResult,
    ) -> Result<(), RouterExitStatus> {
        let task_id = result.task_id.clone();
        if let Some(active) = self
            .tool_execution_tasks
            .remove(&result.tool_execution_run_id)
        {
            let _ = active.join_handle.await;
        }
        if let Some(sender) = self
            .task_runtime_registry
            .get(&task_id)
            .map(|entry| entry.sender.clone())
        {
            self.send_to_task_runtime(
                task_id,
                sender,
                TaskRuntimeCommand::ToolResult(result),
                false,
            )
            .await
        } else {
            self.publish_debug(Some(task_id), "stale tool output discarded")
                .await
        }
    }

    async fn handle_runtime_exit(
        &mut self,
        notice: TaskRuntimeExitNotice,
    ) -> Result<(), RouterExitStatus> {
        let removed = self
            .task_runtime_registry
            .get(&notice.task_id)
            .is_some_and(|entry| entry.control.same_control(&notice.task_runtime_control));
        if removed {
            self.task_runtime_registry.remove(&notice.task_id);
            self.cancel_task_effects(&notice.task_id).await;
        }
        let message = if removed {
            format!("task runtime exited: {:?}", notice.reason)
        } else {
            format!("stale task runtime exit discarded: {:?}", notice.reason)
        };
        self.publish_debug(Some(notice.task_id), message).await
    }

    async fn route_task_local_command(
        &mut self,
        task_id: TaskId,
        command: TaskRuntimeCommand,
    ) -> Result<(), RouterExitStatus> {
        if let Some(sender) = self
            .task_runtime_registry
            .get(&task_id)
            .map(|entry| entry.sender.clone())
        {
            return self
                .send_to_task_runtime(task_id, sender, command, true)
                .await;
        }
        self.create_runtime_and_send(task_id, command).await
    }

    async fn create_runtime_and_send(
        &mut self,
        task_id: TaskId,
        command: TaskRuntimeCommand,
    ) -> Result<(), RouterExitStatus> {
        match self.create_runtime(task_id.clone()).await {
            Ok(entry) => {
                if let Err(error) = entry.sender.send(command) {
                    self.task_runtime_registry.remove(&task_id);
                    settle_task_runtime_command(error.0, TaskCommandError::RuntimeUnavailable);
                    self.publish_debug(Some(task_id), "task command delivery failed")
                        .await?;
                }
            }
            Err((error, message)) => {
                settle_task_runtime_command(command, error);
                self.publish_debug(Some(task_id), message).await?;
            }
        }
        Ok(())
    }

    async fn change_task_status_with_context(
        &mut self,
        task_id: TaskId,
        event: TaskLifecycleEvent,
        context: selvedge_domain_model::CommandOperationContext,
        responder: selvedge_command_model::CommandOperationResponder,
    ) -> Result<(), RouterExitStatus> {
        let db = self.db.clone();
        let effect_task_id = task_id.clone();
        let deferred_self_change = context.operation.is_some() && context.caller_task_id == task_id;
        let status = match event {
            TaskLifecycleEvent::Archive => selvedge_domain_model::TaskStatus::Archived,
            TaskLifecycleEvent::Freeze => selvedge_domain_model::TaskStatus::Frozen,
            TaskLifecycleEvent::Unfreeze => selvedge_domain_model::TaskStatus::Active,
            TaskLifecycleEvent::Stop => selvedge_domain_model::TaskStatus::Stopped,
            _ => {
                responder.settle(Err(TaskCommandError::InvalidCommand));
                return Ok(());
            }
        };
        let outcome = tokio::task::spawn_blocking(move || {
            selvedge_db::transition_task_status_with_context(
                &db,
                &effect_task_id,
                event,
                now(),
                &context,
                serde_json::json!({"status": format!("{status:?}").to_lowercase()}),
            )
        })
        .await;
        match outcome {
            Ok(Ok(outcome)) => {
                responder.settle(Ok(outcome.result));
                if !outcome.replayed && !deferred_self_change {
                    self.apply_committed_task_status(task_id, status).await?;
                }
            }
            Ok(Err(error)) => responder.settle(Err(task_status_change_error(error))),
            Err(_) => responder.settle(Err(TaskCommandError::PersistenceFailed)),
        }
        Ok(())
    }

    async fn change_task_status(
        &mut self,
        task_id: TaskId,
        event: TaskLifecycleEvent,
        responder: TaskStatusChangeResponder,
    ) -> Result<(), RouterExitStatus> {
        let db = self.db.clone();
        let transition_task_id = task_id.clone();
        let transition = tokio::task::spawn_blocking(move || {
            transition_task_status(&db, &transition_task_id, event, now())
        })
        .await;
        let row = match transition {
            Ok(Ok(row)) => row,
            Ok(Err(error)) => {
                responder.settle(Err(task_status_change_error(error)));
                return Ok(());
            }
            Err(error) => {
                responder.settle(Err(TaskCommandError::PersistenceFailed));
                return self
                    .publish_debug(
                        Some(task_id),
                        format!("task status transition task failed: {error}"),
                    )
                    .await;
            }
        };

        let status = row.task_status;
        responder.settle(Ok(TaskStatusChangeOutcome { status }));

        self.apply_committed_task_status(task_id, status).await
    }

    async fn apply_committed_task_status(
        &mut self,
        task_id: TaskId,
        status: selvedge_domain_model::TaskStatus,
    ) -> Result<(), RouterExitStatus> {
        if status.has_runtime() {
            if let Some(entry) = self.task_runtime_registry.get(&task_id) {
                entry.control.notify_status_changed();
                return Ok(());
            }
            return self.ensure_task_runtime(task_id).await;
        }

        self.cancel_task_effects(&task_id).await;
        if let Some(entry) = self.task_runtime_registry.get(&task_id).cloned() {
            entry.control.notify_status_changed();
            let _ = entry.control.wait_for_shutdown().await;
            self.remove_runtime_if_current(&task_id, &entry);
        }
        Ok(())
    }

    async fn send_to_task_runtime(
        &mut self,
        task_id: TaskId,
        sender: TaskRuntimeSender,
        command: TaskRuntimeCommand,
        create_when_closed: bool,
    ) -> Result<(), RouterExitStatus> {
        let Err(error) = sender.send(command) else {
            return Ok(());
        };

        self.task_runtime_registry.remove(&task_id);
        if create_when_closed {
            return self.create_runtime_and_send(task_id, error.0).await;
        }

        self.publish_debug(Some(task_id), "task runtime mailbox closed")
            .await
    }

    async fn recover_command_invocation(
        &mut self,
        invocation: selvedge_domain_model::CommandInvocationId,
    ) -> Result<(), RouterExitStatus> {
        let db = self.db.clone();
        let recovery = invocation.clone();
        if !tokio::task::spawn_blocking(move || {
            selvedge_db::read_admitted_command_call(&db, &recovery)
        })
        .await
        .is_ok_and(|result| result.is_ok())
        {
            return Ok(());
        }
        let db = self.db.clone();
        let task_id = invocation.task_id.clone();
        if tokio::task::spawn_blocking(move || read_task_status(&db, &task_id))
            .await
            .is_ok_and(|result| result == Ok(selvedge_domain_model::TaskStatus::Active))
        {
            return self.ensure_task_runtime(invocation.task_id).await;
        }
        if self
            .tool_execution_tasks
            .values()
            .any(|effect| effect.task_id == invocation.task_id)
        {
            return Ok(());
        }
        if let Some(entry) = self.task_runtime_registry.get(&invocation.task_id).cloned() {
            self.cancel_task_effects(&invocation.task_id).await;
            entry.control.shutdown().await;
            self.remove_runtime_if_current(&invocation.task_id, &entry);
        }
        let db = self.db.clone();
        let router_tx = self.router_tx.clone();
        let deps = self.core_spawn_deps.clone();
        let recovery = invocation.clone();
        match tokio::task::spawn_blocking(move || {
            selvedge_task_runtime_factory::create_command_recovery_runtime(
                &db, &router_tx, &deps, &recovery,
            )
        })
        .await
        {
            Ok(Ok(spawned)) => {
                let entry = RuntimeRegistryEntry {
                    sender: spawned.task_runtime_tx,
                    control: spawned.task_runtime_control,
                };
                if entry
                    .sender
                    .send(TaskRuntimeCommand::RecoverCommandInvocation {
                        invocation: invocation.clone(),
                    })
                    .is_ok()
                {
                    self.task_runtime_registry.insert(invocation.task_id, entry);
                }
                Ok(())
            }
            Ok(Err(error)) => {
                self.publish_debug(Some(invocation.task_id), error.to_string())
                    .await
            }
            Err(error) => {
                self.publish_debug(Some(invocation.task_id), error.to_string())
                    .await
            }
        }
    }

    async fn ensure_task_runtime(&mut self, task_id: TaskId) -> Result<(), RouterExitStatus> {
        if self.task_runtime_registry.contains_key(&task_id) {
            return Ok(());
        }
        if let Err((_, message)) = self.create_runtime(task_id.clone()).await {
            self.publish_debug(Some(task_id), message).await?;
        }
        Ok(())
    }

    async fn create_runtime(
        &mut self,
        task_id: TaskId,
    ) -> Result<RuntimeRegistryEntry, (TaskCommandError, String)> {
        let db = self.db.clone();
        let router_tx = self.router_tx.clone();
        let deps = self.core_spawn_deps.clone();
        let create_task_id = task_id.clone();
        let spawned = tokio::task::spawn_blocking(move || {
            create_task_runtime(&db, &router_tx, &deps, create_task_id)
        })
        .await
        .map_err(|error| {
            (
                TaskCommandError::RuntimeUnavailable,
                format!("runtime creation task failed: {error}"),
            )
        })?
        .map_err(|error| (task_command_factory_error(&error), error.to_string()))?;
        self.register_runtime(spawned)
    }

    async fn ensure_missing_task_runtimes(&mut self) -> Result<(), RouterExitStatus> {
        let db = self.db.clone();
        let admissions = match tokio::task::spawn_blocking(move || {
            selvedge_db::list_admitted_command_invocations(&db)
        })
        .await
        {
            Ok(Ok(admissions)) => admissions,
            Ok(Err(error)) => return self.publish_debug(None, error.to_string()).await,
            Err(error) => return self.publish_debug(None, error.to_string()).await,
        };
        // Pending children cannot request predecessor recovery themselves. Register every
        // admitted owner before the ordinary scan so inactive owners can publish them.
        for invocation in admissions {
            self.recover_command_invocation(invocation).await?;
        }
        let db = self.db.clone();
        let router_tx = self.router_tx.clone();
        let deps = self.core_spawn_deps.clone();
        let live_task_ids = self.task_runtime_registry.keys().cloned().collect();
        let recovered = match tokio::task::spawn_blocking(move || {
            recover_task_runtimes(&db, &router_tx, &deps, &live_task_ids)
        })
        .await
        {
            Ok(Ok(recovered)) => recovered,
            Ok(Err(error)) => return self.publish_debug(None, error.to_string()).await,
            Err(error) => {
                return self
                    .publish_debug(None, format!("runtime recovery task failed: {error}"))
                    .await;
            }
        };
        // Register every created runtime before publishing diagnostics: an events
        // failure must not strand runtimes outside the router's shutdown barrier.
        let mut failed = recovered
            .failed
            .into_iter()
            .map(|(task_id, error)| (task_id, error.to_string()))
            .collect::<Vec<_>>();
        for spawned in recovered.created {
            let task_id = spawned.task_id.clone();
            if let Err((_, message)) = self.register_runtime(spawned) {
                failed.push((task_id, message));
            }
        }
        for (task_id, message) in failed {
            self.publish_debug(Some(task_id), message).await?;
        }
        Ok(())
    }

    fn register_runtime(
        &mut self,
        spawned: selvedge_core::SpawnedTaskRuntime,
    ) -> Result<RuntimeRegistryEntry, (TaskCommandError, String)> {
        let entry = RuntimeRegistryEntry {
            sender: spawned.task_runtime_tx,
            control: spawned.task_runtime_control,
        };
        entry.sender.send(TaskRuntimeCommand::Start).map_err(|_| {
            (
                TaskCommandError::RuntimeUnavailable,
                "task runtime start failed".to_owned(),
            )
        })?;
        self.task_runtime_registry
            .insert(spawned.task_id, entry.clone());
        Ok(entry)
    }

    async fn shutdown(&mut self) {
        self.ingress_rx.close();
        self.cancel_all_effects().await;
        self.shutdown_runtimes().await;
        while let Some(ingress) = self.ingress_rx.recv().await {
            settle_router_ingress(ingress, TaskCommandError::RuntimeUnavailable);
        }
    }

    async fn cancel_task_effects(&mut self, task_id: &TaskId) {
        let model_effect_ids = self
            .model_call_tasks
            .iter()
            .filter(|(_, active)| &active.task_id == task_id)
            .map(|(effect_id, _)| effect_id.clone())
            .collect::<Vec<_>>();
        let tool_run_ids = self
            .tool_execution_tasks
            .iter()
            .filter(|(_, active)| &active.task_id == task_id)
            .map(|(run_id, _)| run_id.clone())
            .collect::<Vec<_>>();
        let model_calls = model_effect_ids
            .into_iter()
            .filter_map(|effect_id| self.model_call_tasks.remove(&effect_id))
            .collect::<Vec<_>>();
        let tool_executions = tool_run_ids
            .into_iter()
            .filter_map(|run_id| self.tool_execution_tasks.remove(&run_id))
            .collect::<Vec<_>>();

        for active in &model_calls {
            active.join_handle.abort();
        }
        for active in &tool_executions {
            active.join_handle.abort();
        }
        for active in model_calls {
            let _ = active.join_handle.await;
        }
        for active in tool_executions {
            let _ = active.join_handle.await;
        }
    }

    async fn cancel_all_effects(&mut self) {
        let model_calls = std::mem::take(&mut self.model_call_tasks);
        let tool_executions = std::mem::take(&mut self.tool_execution_tasks);
        for active in model_calls.values() {
            active.join_handle.abort();
        }
        for active in tool_executions.values() {
            active.join_handle.abort();
        }
        for active in model_calls.into_values() {
            let _ = active.join_handle.await;
        }
        for active in tool_executions.into_values() {
            let _ = active.join_handle.await;
        }
    }

    async fn shutdown_runtimes(&mut self) {
        let entries = self
            .task_runtime_registry
            .iter()
            .map(|(task_id, entry)| (task_id.clone(), entry.clone()))
            .collect::<Vec<_>>();
        for (task_id, entry) in entries {
            self.shutdown_runtime_entry(entry.clone()).await;
            self.remove_runtime_if_current(&task_id, &entry);
        }
    }

    async fn shutdown_runtime_entry(&self, entry: RuntimeRegistryEntry) {
        let _ = entry.control.shutdown().await;
    }

    fn remove_runtime_if_current(&mut self, task_id: &TaskId, entry: &RuntimeRegistryEntry) {
        let is_current = self
            .task_runtime_registry
            .get(task_id)
            .is_some_and(|current| current.control.same_control(&entry.control));
        if is_current {
            self.task_runtime_registry.remove(task_id);
        }
    }

    async fn publish_domain_event(
        &mut self,
        request: DomainEventPublishRequest,
    ) -> Result<(), RouterExitStatus> {
        let raw = match request.event {
            DomainEvent::TaskRuntimeReady => ClientEvent::DebugNotice(DebugNoticeEvent {
                task_id: Some(request.task_id),
                message_text: "task runtime ready".to_owned(),
            }),
            DomainEvent::ErrorNotice { message } => ClientEvent::DebugNotice(DebugNoticeEvent {
                task_id: Some(request.task_id),
                message_text: message,
            }),
            DomainEvent::UserMessageCommitted { .. }
            | DomainEvent::AssistantMessageCommitted { .. }
            | DomainEvent::ReasoningCommitted { .. }
            | DomainEvent::FunctionCallCommitted { .. }
            | DomainEvent::FunctionOutputCommitted { .. }
            | DomainEvent::TaskArchived => return Ok(()),
        };
        self.send_event(EventIngress::Publish(raw)).await
    }

    async fn publish_debug(
        &mut self,
        task_id: Option<TaskId>,
        message: impl Into<String>,
    ) -> Result<(), RouterExitStatus> {
        self.send_event(EventIngress::Publish(ClientEvent::DebugNotice(
            DebugNoticeEvent {
                task_id,
                message_text: message.into(),
            },
        )))
        .await
    }

    async fn send_event(&mut self, event: EventIngress) -> Result<(), RouterExitStatus> {
        self.events_tx
            .send(event)
            .await
            .map_err(|_| RouterExitStatus::EventsMailboxClosed)
    }
}

fn tool_spawn_failed_result(request: ToolExecutionRequest) -> ToolExecutionResult {
    ToolExecutionResult {
        completion: selvedge_command_model::ToolExecutionCompletion::ordinary(),
        task_id: request.task_id,
        tool_execution_run_id: request.tool_execution_run_id,
        function_call_node_id: request.function_call_node_id,
        function_call_id: request.function_call_id,
        tool_name: request.tool_name,
        branches: vec![ToolExecutionBranch {
            target: ToolExecutionBranchTarget::CallingTask,
            output: serde_json::Value::String("tool execution spawn failed".to_owned()),
            is_error: true,
            messages: Vec::new(),
        }],
    }
}

fn settle_router_ingress(ingress: RouterIngressMessage, error: TaskCommandError) {
    if let RouterIngressMessage::Command(envelope) = ingress {
        settle_router_command(envelope, error);
    }
}

fn settle_router_command(command: RouterCommand, error: TaskCommandError) {
    match command {
        RouterCommand::SendUserInput { responder, .. } => responder.settle(Err(error)),
        RouterCommand::SendTaskInput { responder, .. }
        | RouterCommand::ChangeTaskStatus { responder, .. } => responder.settle(Err(error)),
        RouterCommand::ArchiveTask { responder, .. }
        | RouterCommand::FreezeTask { responder, .. }
        | RouterCommand::UnfreezeTask { responder, .. }
        | RouterCommand::StopTask { responder, .. } => responder.settle(Err(error)),
        RouterCommand::AttachClient { .. }
        | RouterCommand::DetachClient { .. }
        | RouterCommand::UpdateSubscription { .. }
        | RouterCommand::RecoverCommandInvocation { .. }
        | RouterCommand::EnsureTaskRuntime { .. }
        | RouterCommand::EnsureMissingTaskRuntimes => {}
    }
}

fn settle_task_runtime_command(command: TaskRuntimeCommand, error: TaskCommandError) {
    match command {
        TaskRuntimeCommand::UserInput { responder, .. } => responder.settle(Err(error)),
        TaskRuntimeCommand::TaskInput { responder, .. } => responder.settle(Err(error)),
        TaskRuntimeCommand::Start
        | TaskRuntimeCommand::RecoverCommandInvocation { .. }
        | TaskRuntimeCommand::ModelCallNotStarted { .. }
        | TaskRuntimeCommand::ApiModelReply(_)
        | TaskRuntimeCommand::ToolResult(_) => {}
    }
}

fn task_status_change_error(error: DbError) -> TaskCommandError {
    match error {
        DbError::NotFound => TaskCommandError::TaskMissing,
        DbError::CommandOperationMismatch => TaskCommandError::CommandOperationMismatch,
        DbError::InvalidTaskStatus { status } => TaskCommandError::InvalidTaskStatus { status },
        DbError::CommandEnvironmentBusy { .. }
        | DbError::StaleFunctionCall
        | DbError::HistoryCursorNotOnTask
        | DbError::ToolUnavailable
        | DbError::TaskDescendantLimitExceeded { .. }
        | DbError::Constraint(_)
        | DbError::Storage(_)
        | DbError::SchemaMismatch { .. } => TaskCommandError::PersistenceFailed,
    }
}

fn now() -> UnixTs {
    UnixTs(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64,
    )
}

fn task_command_factory_error(error: &RuntimeCreationError) -> TaskCommandError {
    match error {
        RuntimeCreationError::TaskMissing => TaskCommandError::TaskMissing,
        RuntimeCreationError::TaskArchived => TaskCommandError::TaskArchived,
        RuntimeCreationError::TaskPending => TaskCommandError::RuntimeUnavailable,
        RuntimeCreationError::DbReadFailed(_) => TaskCommandError::PersistenceFailed,
        RuntimeCreationError::CoreSpawnFailed(_) => TaskCommandError::RuntimeUnavailable,
    }
}
