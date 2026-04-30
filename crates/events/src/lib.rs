#![doc = include_str!("../README.md")]

use std::collections::{BTreeMap, HashMap};

use selvedge_command_model::{
    BeginClientHydration, ClientEvent, ClientEventFrame, ClientFrame, ClientFrameSender, ClientId,
    ClientNoticeFrame, ClientSnapshot, ClientSnapshotFrame, ClientSubscription, DeliverNotice,
    DeliverSnapshot, DetailLevel, EventControlMessage, EventIngress, EventIngressSender, RawEvent,
    TaskId, TaskScope, UpdateSubscription,
};
use tokio::sync::mpsc;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EventsStartArgs {
    pub ingress_capacity: usize,
    pub client_registry_capacity: usize,
    pub hydration_buffer_capacity: usize,
}

#[derive(Debug)]
pub struct EventsHandle {
    pub ingress_tx: EventIngressSender,
    pub join_handle: tokio::task::JoinHandle<()>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SpawnEventsError {
    InvalidIngressCapacity,
    InvalidClientRegistryCapacity,
    InvalidHydrationBufferCapacity,
}

pub fn spawn_events_task(args: EventsStartArgs) -> Result<EventsHandle, SpawnEventsError> {
    if args.ingress_capacity == 0 {
        return Err(SpawnEventsError::InvalidIngressCapacity);
    }

    if args.client_registry_capacity == 0 {
        return Err(SpawnEventsError::InvalidClientRegistryCapacity);
    }

    if args.hydration_buffer_capacity == 0 {
        return Err(SpawnEventsError::InvalidHydrationBufferCapacity);
    }

    let (ingress_tx, mut ingress_rx) = mpsc::channel(args.ingress_capacity);
    let join_handle = tokio::spawn(async move {
        let mut task = EventsTask::new(args);

        while let Some(ingress) = ingress_rx.recv().await {
            task.handle_ingress(ingress).await;
        }
    });

    Ok(EventsHandle {
        ingress_tx,
        join_handle,
    })
}

struct EventsTask {
    sessions: HashMap<ClientId, ClientSession>,
    hydration_buffer_capacity: usize,
}

impl EventsTask {
    fn new(args: EventsStartArgs) -> Self {
        Self {
            sessions: HashMap::with_capacity(args.client_registry_capacity),
            hydration_buffer_capacity: args.hydration_buffer_capacity,
        }
    }

    async fn handle_ingress(&mut self, ingress: EventIngress) {
        match ingress {
            EventIngress::Control(control) => self.handle_control(control).await,
            EventIngress::Raw(raw) => self.handle_raw(raw).await,
        }
    }

    async fn handle_control(&mut self, control: EventControlMessage) {
        match control {
            EventControlMessage::BeginClientHydration(begin) => self.begin_hydration(begin),
            EventControlMessage::DeliverSnapshot(snapshot) => self.deliver_snapshot(snapshot).await,
            EventControlMessage::DeliverNotice(notice) => self.deliver_notice(notice).await,
            EventControlMessage::UpdateSubscription(update) => self.update_subscription(update),
            EventControlMessage::DetachClient(detach) => {
                self.sessions.remove(&detach.client_id);
            }
        }
    }

    fn begin_hydration(&mut self, begin: BeginClientHydration) {
        self.sessions.insert(
            begin.client_id,
            ClientSession {
                outbound: begin.outbound,
                subscription: begin.subscription,
                delivery_seq: 1,
                state: ClientSessionState::Hydrating { buffer: Vec::new() },
            },
        );
    }

    async fn deliver_snapshot(&mut self, snapshot: DeliverSnapshot) {
        let Some(session) = self.sessions.get_mut(&snapshot.client_id) else {
            return;
        };

        let snapshot_versions = snapshot_versions(&snapshot.snapshot);
        let frame = ClientFrame::Snapshot(ClientSnapshotFrame {
            delivery_seq: session.next_delivery_seq(),
            client_command_id: snapshot.client_command_id,
            snapshot: snapshot.snapshot,
        });

        if session.outbound.send(frame).await.is_err() {
            self.sessions.remove(&snapshot.client_id);
            return;
        }

        match &mut session.state {
            ClientSessionState::Hydrating { buffer } => {
                let buffered = std::mem::take(buffer);
                session.state = ClientSessionState::Live;

                for raw in buffered
                    .into_iter()
                    .filter(|raw| raw_survives_snapshot(raw, &snapshot_versions))
                {
                    let Some(event) = client_event_for_subscription(&raw, &session.subscription)
                    else {
                        continue;
                    };

                    let frame = ClientFrame::Event(ClientEventFrame {
                        delivery_seq: session.next_delivery_seq(),
                        event,
                    });

                    if session.outbound.send(frame).await.is_err() {
                        self.sessions.remove(&snapshot.client_id);
                        return;
                    }
                }
            }
            ClientSessionState::Live => {}
        }
    }

    async fn deliver_notice(&mut self, notice: DeliverNotice) {
        let Some(session) = self.sessions.get_mut(&notice.client_id) else {
            return;
        };

        let frame = ClientFrame::Notice(ClientNoticeFrame {
            delivery_seq: session.next_delivery_seq(),
            client_command_id: notice.client_command_id,
            notice: notice.notice,
        });

        if session.outbound.send(frame).await.is_err() {
            self.sessions.remove(&notice.client_id);
        }
    }

    fn update_subscription(&mut self, update: UpdateSubscription) {
        let Some(session) = self.sessions.get_mut(&update.client_id) else {
            return;
        };

        session.subscription = update.subscription;

        if let ClientSessionState::Hydrating { buffer } = &mut session.state {
            buffer
                .retain(|raw| client_event_for_subscription(raw, &session.subscription).is_some());
        }
    }

    async fn handle_raw(&mut self, raw: RawEvent) {
        let client_ids = self.sessions.keys().cloned().collect::<Vec<_>>();

        for client_id in client_ids {
            if !self.sessions.contains_key(&client_id) {
                continue;
            }

            let should_remove = {
                let Some(session) = self.sessions.get_mut(&client_id) else {
                    continue;
                };

                match &mut session.state {
                    ClientSessionState::Hydrating { buffer } => {
                        if client_event_for_subscription(&raw, &session.subscription).is_some() {
                            if buffer.len() >= self.hydration_buffer_capacity {
                                true
                            } else {
                                buffer.push(raw.clone());
                                false
                            }
                        } else {
                            false
                        }
                    }
                    ClientSessionState::Live => {
                        if let Some(event) =
                            client_event_for_subscription(&raw, &session.subscription)
                        {
                            let frame = ClientFrame::Event(ClientEventFrame {
                                delivery_seq: session.next_delivery_seq(),
                                event,
                            });
                            session.outbound.send(frame).await.is_err()
                        } else {
                            false
                        }
                    }
                }
            };

            if should_remove {
                self.sessions.remove(&client_id);
            }
        }
    }
}

struct ClientSession {
    outbound: ClientFrameSender,
    subscription: ClientSubscription,
    delivery_seq: u64,
    state: ClientSessionState,
}

impl ClientSession {
    fn next_delivery_seq(&mut self) -> selvedge_command_model::DeliverySeq {
        let delivery_seq = selvedge_command_model::DeliverySeq(self.delivery_seq);
        self.delivery_seq += 1;
        delivery_seq
    }
}

enum ClientSessionState {
    Hydrating { buffer: Vec<RawEvent> },
    Live,
}

fn client_event_for_subscription(
    raw: &RawEvent,
    subscription: &ClientSubscription,
) -> Option<ClientEvent> {
    if !task_scope_matches(raw_task_id(raw), &subscription.task_scope) {
        return None;
    }

    match raw {
        RawEvent::TaskChanged(event) => Some(ClientEvent::TaskChanged(
            selvedge_command_model::TaskChangedEvent {
                task: event.task.clone(),
            },
        )),
        RawEvent::HistoryAppended(event) => {
            if subscription.detail_level == DetailLevel::Verbose {
                Some(ClientEvent::HistoryAppended(
                    selvedge_command_model::HistoryAppendedEvent {
                        task_id: event.task_id.clone(),
                        task_state_version: event.task_state_version,
                        appended_nodes: event.appended_nodes.clone(),
                    },
                ))
            } else {
                None
            }
        }
        RawEvent::ModelCallStatus(event) => {
            if subscription.detail_level == DetailLevel::Verbose
                && subscription.include_model_call_status
            {
                Some(ClientEvent::ModelCallStatus(
                    selvedge_command_model::ModelCallStatusEvent {
                        task_id: event.task_id.clone(),
                        model_call_id: event.model_call_id.clone(),
                        phase: event.phase.clone(),
                    },
                ))
            } else {
                None
            }
        }
        RawEvent::ToolExecutionStatus(event) => {
            if subscription.detail_level == DetailLevel::Verbose
                && subscription.include_tool_execution_status
            {
                Some(ClientEvent::ToolExecutionStatus(
                    selvedge_command_model::ToolExecutionStatusEvent {
                        task_id: event.task_id.clone(),
                        tool_execution_run_id: event.tool_execution_run_id.clone(),
                        function_call_node_id: event.function_call_node_id,
                        tool_name: event.tool_name.clone(),
                        phase: event.phase.clone(),
                    },
                ))
            } else {
                None
            }
        }
        RawEvent::Debug(event) => {
            if subscription.include_debug_notices {
                Some(ClientEvent::DebugNotice(
                    selvedge_command_model::DebugNoticeEvent {
                        task_id: event.task_id.clone(),
                        message_text: event.message_text.clone(),
                    },
                ))
            } else {
                None
            }
        }
    }
}

fn raw_task_id(raw: &RawEvent) -> Option<&TaskId> {
    match raw {
        RawEvent::TaskChanged(event) => Some(&event.task.task_id),
        RawEvent::HistoryAppended(event) => Some(&event.task_id),
        RawEvent::ModelCallStatus(event) => Some(&event.task_id),
        RawEvent::ToolExecutionStatus(event) => Some(&event.task_id),
        RawEvent::Debug(event) => event.task_id.as_ref(),
    }
}

fn task_scope_matches(task_id: Option<&TaskId>, task_scope: &TaskScope) -> bool {
    match task_scope {
        TaskScope::AllTasks => true,
        TaskScope::TaskIds(task_ids) => task_id.is_some_and(|task_id| task_ids.contains(task_id)),
    }
}

fn snapshot_versions(snapshot: &ClientSnapshot) -> BTreeMap<TaskId, u64> {
    snapshot
        .task_versions
        .iter()
        .map(|version| (version.task_id.clone(), version.state_version))
        .collect()
}

fn raw_survives_snapshot(raw: &RawEvent, snapshot_versions: &BTreeMap<TaskId, u64>) -> bool {
    let Some((task_id, state_version)) = raw_state_version(raw) else {
        return true;
    };

    snapshot_versions
        .get(task_id)
        .is_none_or(|snapshot_version| state_version > *snapshot_version)
}

fn raw_state_version(raw: &RawEvent) -> Option<(&TaskId, u64)> {
    match raw {
        RawEvent::TaskChanged(event) => Some((&event.task.task_id, event.task.state_version)),
        RawEvent::HistoryAppended(event) => Some((&event.task_id, event.task_state_version)),
        RawEvent::ModelCallStatus(_) | RawEvent::ToolExecutionStatus(_) | RawEvent::Debug(_) => {
            None
        }
    }
}
