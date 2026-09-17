#![doc = include_str!("../README.md")]

use std::collections::{BTreeMap, HashMap};

use selvedge_command_model::{
    BeginClientHydration, ClientEvent, ClientEventFrame, ClientFrame, ClientFrameSender, ClientId,
    ClientNoticeFrame, ClientSessionIdentity, ClientSnapshot, ClientSnapshotFrame,
    ClientSubscription, DeliverNotice, DeliverSnapshot, DetailLevel, EventClientReservationResult,
    EventControlMessage, EventIngress, EventIngressSender, ReserveClientSession, TaskId, TaskScope,
    UpdateSubscription,
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
            task.handle_ingress(ingress);
        }
    });

    Ok(EventsHandle {
        ingress_tx,
        join_handle,
    })
}

// Each reservation owns its hydration state, including results that arrive while
// a later reservation temporarily obscures it.
struct PendingSession {
    identity: ClientSessionIdentity,
    hydration: Option<PendingHydration>,
}
struct PendingHydration {
    begin: BeginClientHydration,
    completion: Option<PendingCompletion>,
    buffer: Vec<ClientEvent>,
}
enum PendingCompletion {
    Snapshot(ClientSnapshot),
    Failure(DeliverNotice),
}
#[derive(Default)]
struct ClientSlot {
    installed: Option<ClientSession>,
    reservations: Vec<PendingSession>,
}
struct EventsTask {
    clients: HashMap<ClientId, ClientSlot>,
    client_registry_capacity: usize,
    hydration_buffer_capacity: usize,
}
impl EventsTask {
    fn new(args: EventsStartArgs) -> Self {
        Self {
            clients: HashMap::new(),
            client_registry_capacity: args.client_registry_capacity,
            hydration_buffer_capacity: args.hydration_buffer_capacity,
        }
    }
    fn handle_ingress(&mut self, ingress: EventIngress) {
        match ingress {
            EventIngress::Control(control) => self.handle_control(control),
            EventIngress::Publish(raw) => self.handle_raw(raw),
        }
        self.clients
            .retain(|_, slot| slot.installed.is_some() || !slot.reservations.is_empty());
    }
    fn handle_control(&mut self, control: EventControlMessage) {
        match control {
            EventControlMessage::ReserveClientSession(reservation) => {
                self.reserve_client_session(reservation)
            }
            EventControlMessage::BeginClientHydration(begin) => self.begin_hydration(begin),
            EventControlMessage::DeliverSnapshot(snapshot) => self.deliver_snapshot(snapshot),
            EventControlMessage::DeliverNotice(notice) => self.deliver_notice(notice),
            EventControlMessage::UpdateSubscription(update) => self.update_subscription(update),
            EventControlMessage::DetachClient(detach) => self.detach_client(detach),
        }
    }
    fn reserve_client_session(&mut self, reservation: ReserveClientSession) {
        let ReserveClientSession { session, result_tx } = reservation;
        let result = if let Some(slot) = self.clients.get(session.client_id()) {
            if slot
                .installed
                .as_ref()
                .is_some_and(|current| current.identity.session_id() == session.session_id())
                || slot
                    .reservations
                    .iter()
                    .any(|pending| pending.identity.session_id() == session.session_id())
            {
                EventClientReservationResult::DuplicateAttach
            } else {
                EventClientReservationResult::Reserved
            }
        } else if self.clients.len() >= self.client_registry_capacity {
            EventClientReservationResult::ClientRegistryFull
        } else {
            EventClientReservationResult::Reserved
        };
        let reserved = result == EventClientReservationResult::Reserved;
        if reserved {
            self.clients
                .entry(session.client_id().clone())
                .or_default()
                .reservations
                .push(PendingSession {
                    identity: session.clone(),
                    hydration: None,
                });
        }
        if result_tx.send(result).is_err() && reserved {
            self.remove_reservation(&session);
        }
    }
    fn pending_mut(&mut self, identity: &ClientSessionIdentity) -> Option<&mut PendingSession> {
        self.clients
            .get_mut(identity.client_id())?
            .reservations
            .iter_mut()
            .find(|pending| pending.identity.session_id() == identity.session_id())
    }
    fn begin_hydration(&mut self, begin: BeginClientHydration) {
        let identity = begin.session.clone();
        if let Some(pending) = self.pending_mut(&identity) {
            pending.hydration.get_or_insert(PendingHydration {
                begin,
                completion: None,
                buffer: Vec::new(),
            });
        }
        self.install_pending(identity.client_id());
    }
    fn install_pending(&mut self, client_id: &ClientId) {
        let Some(slot) = self.clients.get_mut(client_id) else {
            return;
        };
        if !slot
            .reservations
            .last()
            .is_some_and(|pending| pending.hydration.is_some())
        {
            return;
        }
        let pending = slot.reservations.pop().expect("pending session");
        let PendingHydration {
            begin,
            completion,
            buffer,
        } = pending.hydration.expect("pending hydration begin");
        slot.reservations.clear();
        slot.installed = Some(ClientSession {
            identity: begin.session.clone(),
            outbound: begin.outbound,
            subscription: begin.subscription,
            delivery_seq: 1,
            state: ClientSessionState::Hydrating { buffer },
        });
        match completion {
            Some(PendingCompletion::Snapshot(snapshot)) => self.deliver_snapshot(DeliverSnapshot {
                session: begin.session,
                snapshot,
            }),
            Some(PendingCompletion::Failure(notice)) => {
                self.deliver_notice(notice);
                self.clients
                    .get_mut(client_id)
                    .expect("client slot")
                    .installed = None;
            }
            None => {}
        }
    }
    fn installed_mut(&mut self, identity: &ClientSessionIdentity) -> Option<&mut ClientSession> {
        self.clients
            .get_mut(identity.client_id())?
            .installed
            .as_mut()
            .filter(|session| session.identity.session_id() == identity.session_id())
    }
    fn deliver_snapshot(&mut self, snapshot: DeliverSnapshot) {
        if let Some(pending) = self
            .pending_mut(&snapshot.session)
            .and_then(|pending| pending.hydration.as_mut())
        {
            pending.completion = Some(PendingCompletion::Snapshot(snapshot.snapshot));
            return;
        }
        let Some(session) = self.installed_mut(&snapshot.session) else {
            return;
        };
        let versions = snapshot_versions(&snapshot.snapshot);
        let frame = ClientFrame::Snapshot(ClientSnapshotFrame {
            delivery_seq: session.next_delivery_seq(),
            client_command_id: session.identity.attach_command_id().clone(),
            snapshot: snapshot.snapshot,
        });
        let mut failed = session.send_frame(frame).is_err();
        if let ClientSessionState::Hydrating { buffer } =
            std::mem::replace(&mut session.state, ClientSessionState::Live)
        {
            for raw in buffer
                .into_iter()
                .filter(|raw| raw_survives_snapshot(raw, &versions))
            {
                if failed {
                    break;
                }
                if event_matches_subscription(&raw, &session.subscription) {
                    let frame = ClientFrame::Event(ClientEventFrame {
                        delivery_seq: session.next_delivery_seq(),
                        event: raw,
                    });
                    failed = session.send_frame(frame).is_err();
                }
            }
        }
        if failed {
            self.clients
                .get_mut(snapshot.session.client_id())
                .expect("client slot")
                .installed = None;
        }
    }
    fn deliver_notice(&mut self, notice: DeliverNotice) {
        if let Some(pending) = self
            .pending_mut(&notice.session)
            .and_then(|pending| pending.hydration.as_mut())
        {
            pending.completion = Some(PendingCompletion::Failure(notice));
            return;
        }
        let Some(session) = self.installed_mut(&notice.session) else {
            return;
        };
        let frame = ClientFrame::Notice(ClientNoticeFrame {
            delivery_seq: session.next_delivery_seq(),
            client_command_id: notice.client_command_id,
            notice: notice.notice,
        });
        if session.send_frame(frame).is_err() {
            self.clients
                .get_mut(notice.session.client_id())
                .expect("client slot")
                .installed = None;
        }
    }
    fn update_subscription(&mut self, update: UpdateSubscription) {
        if let Some(hydration) = self
            .pending_mut(&update.session)
            .and_then(|pending| pending.hydration.as_mut())
        {
            hydration.begin.subscription = update.subscription;
            hydration
                .buffer
                .retain(|event| event_matches_subscription(event, &hydration.begin.subscription));
            return;
        }
        if let Some(session) = self.installed_mut(&update.session) {
            session.subscription = update.subscription;
            if let ClientSessionState::Hydrating { buffer } = &mut session.state {
                buffer.retain(|raw| event_matches_subscription(raw, &session.subscription));
            }
        }
    }
    fn remove_reservation(&mut self, identity: &ClientSessionIdentity) {
        if let Some(slot) = self.clients.get_mut(identity.client_id()) {
            slot.reservations
                .retain(|pending| pending.identity.session_id() != identity.session_id());
        }
        self.install_pending(identity.client_id());
    }
    fn detach_client(&mut self, detach: selvedge_command_model::DetachClient) {
        // A hidden failed build must retain its terminal notice until rollback
        // exposes this reservation. Other detaches abandon the reservation.
        let deferred_failure = self
            .pending_mut(&detach.session)
            .and_then(|pending| pending.hydration.as_ref())
            .is_some_and(|pending| {
                matches!(pending.completion, Some(PendingCompletion::Failure(_)))
                    && detach.reason == selvedge_command_model::DetachReason::DeliveryFailed
            });
        if !deferred_failure {
            self.remove_reservation(&detach.session);
        }
        if self.installed_mut(&detach.session).is_some() {
            self.clients
                .get_mut(detach.session.client_id())
                .expect("client slot")
                .installed = None;
        }
    }
    fn handle_raw(&mut self, raw: ClientEvent) {
        for slot in self.clients.values_mut() {
            slot.reservations.retain_mut(|pending| {
                let Some(pending) = &mut pending.hydration else {
                    return true;
                };
                let begin = &pending.begin;
                if !event_matches_subscription(&raw, &begin.subscription) {
                    return true;
                }
                if pending.buffer.len() >= self.hydration_buffer_capacity {
                    return false;
                }
                pending.buffer.push(raw.clone());
                true
            });
            let Some(session) = slot.installed.as_mut() else {
                continue;
            };
            if !event_matches_subscription(&raw, &session.subscription) {
                continue;
            }
            let failed = match &mut session.state {
                ClientSessionState::Hydrating { buffer } => {
                    if buffer.len() >= self.hydration_buffer_capacity {
                        true
                    } else {
                        buffer.push(raw.clone());
                        false
                    }
                }
                ClientSessionState::Live => {
                    let frame = ClientFrame::Event(ClientEventFrame {
                        delivery_seq: session.next_delivery_seq(),
                        event: raw.clone(),
                    });
                    session.send_frame(frame).is_err()
                }
            };
            if failed {
                slot.installed = None;
            }
        }
    }
}
struct ClientSession {
    identity: ClientSessionIdentity,
    outbound: ClientFrameSender,
    subscription: ClientSubscription,
    delivery_seq: u64,
    state: ClientSessionState,
}
impl ClientSession {
    fn next_delivery_seq(&mut self) -> selvedge_command_model::DeliverySeq {
        let seq = self.delivery_seq;
        self.delivery_seq += 1;
        selvedge_command_model::DeliverySeq(seq)
    }
    fn send_frame(&self, frame: ClientFrame) -> Result<(), ()> {
        self.outbound.try_send(frame).map_err(|_| ())
    }
}
enum ClientSessionState {
    Hydrating { buffer: Vec<ClientEvent> },
    Live,
}
fn event_matches_subscription(raw: &ClientEvent, subscription: &ClientSubscription) -> bool {
    if !task_scope_matches(raw_task_id(raw), &subscription.task_scope) {
        return false;
    }
    match raw {
        ClientEvent::TaskChanged(_) => true,
        ClientEvent::HistoryAppended(_) => subscription.detail_level == DetailLevel::Verbose,
        ClientEvent::ModelCallStatus(_) => {
            subscription.detail_level == DetailLevel::Verbose
                && subscription.include_model_call_status
        }
        ClientEvent::ToolExecutionStatus(_) => {
            subscription.detail_level == DetailLevel::Verbose
                && subscription.include_tool_execution_status
        }
        ClientEvent::DebugNotice(_) => subscription.include_debug_notices,
    }
}
fn raw_task_id(raw: &ClientEvent) -> Option<&TaskId> {
    match raw {
        ClientEvent::TaskChanged(event) => Some(&event.task.task_id),
        ClientEvent::HistoryAppended(event) => Some(&event.task_id),
        ClientEvent::ModelCallStatus(event) => Some(&event.task_id),
        ClientEvent::ToolExecutionStatus(event) => Some(&event.task_id),
        ClientEvent::DebugNotice(event) => event.task_id.as_ref(),
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

fn raw_survives_snapshot(raw: &ClientEvent, snapshot_versions: &BTreeMap<TaskId, u64>) -> bool {
    let Some((task_id, state_version)) = raw_state_version(raw) else {
        return true;
    };

    snapshot_versions
        .get(task_id)
        .is_none_or(|snapshot_version| state_version > *snapshot_version)
}

fn raw_state_version(raw: &ClientEvent) -> Option<(&TaskId, u64)> {
    match raw {
        ClientEvent::TaskChanged(event) => Some((&event.task.task_id, event.task.state_version)),
        ClientEvent::HistoryAppended(event) => Some((&event.task_id, event.task_state_version)),
        ClientEvent::ModelCallStatus(_)
        | ClientEvent::ToolExecutionStatus(_)
        | ClientEvent::DebugNotice(_) => None,
    }
}
