use selvedge_command_model::{CoreOutputMessage, RouterIngressMessage, TaskRuntimeCommand};
use selvedge_core::{SpawnTaskRuntimeArgs, TaskRuntimeConfig, spawn_task_runtime};
use selvedge_db::{
    CreateRootTaskInput, NewHistoryNode, NewHistoryNodeContent, NewMessageNodeContent,
    OpenDbOptions, ReasoningEffort, TaskId, UnixTs, create_root_task, open_db,
};

#[tokio::test]
async fn task_runtime_starts_and_requests_model_call_for_user_input() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db");
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: selvedge_db::MessageRole::System,
                    message_text: "system".to_owned(),
                }),
                created_at: UnixTs(1),
            },
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx,
        config: TaskRuntimeConfig {
            mailbox_capacity: 8,
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .await
        .expect("send start");
    let ready = router_rx.recv().await.expect("ready");
    assert!(matches!(
        ready,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RuntimeReady { .. })
    ));

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "hello".to_owned(),
        })
        .await
        .expect("send input");

    let request = router_rx.recv().await.expect("model request");
    assert!(matches!(
        request,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RequestModelCall(_))
    ));
}
