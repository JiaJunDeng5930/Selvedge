#![doc = include_str!("../README.md")]

use std::collections::BTreeMap;
use std::{error::Error, fmt};

use selvedge_command_model::{
    HistoryNodeProjection, HistoryNodeProjectionBody, TaskProjectionStatus, ToolExecutionRequest,
    ToolExecutionResult,
};
use selvedge_domain_model::{
    HistoryNodeId, MessageRole, TaskId, ToolArgumentValue, ToolCallArgument, ToolManifest,
    ToolParameter, ToolParameterType, ToolSpec,
};
use serde_json::{Number, Value};

pub const FORK_TASK_TOOL_NAME: &str = "fork_task";
pub const READ_TASK_TOOL_NAME: &str = "read_task";
pub const SEND_MESSAGE_TO_TASK_TOOL_NAME: &str = "send_message_to_task";
pub const ARCHIVE_TASK_TOOL_NAME: &str = "archive_task";

const MAX_READ_LIMIT: i64 = 100;

pub fn tool_manifest() -> ToolManifest {
    ToolManifest {
        tools: vec![
            ToolSpec {
                name: FORK_TASK_TOOL_NAME.to_owned(),
                description: "Create an active child task from the calling task and give it an initial prompt."
                    .to_owned(),
                parameters: vec![string_parameter(
                    "prompt",
                    "Initial prompt for the child task.",
                    true,
                )],
            },
            ToolSpec {
                name: READ_TASK_TOOL_NAME.to_owned(),
                description:
                    "Read task state and a page of history. Omit task_id to read the calling task."
                        .to_owned(),
                parameters: vec![
                    string_parameter(
                        "task_id",
                        "Task to read; omit it to read the calling task.",
                        false,
                    ),
                    integer_parameter(
                        "after_node_id",
                        "Return history nodes after this node ID.",
                        false,
                    ),
                    integer_parameter(
                        "limit",
                        "Maximum history nodes to return, from 1 through 100.",
                        false,
                    ),
                ],
            },
            ToolSpec {
                name: SEND_MESSAGE_TO_TASK_TOOL_NAME.to_owned(),
                description:
                    "Send a message to an active task and report whether it was committed or queued."
                        .to_owned(),
                parameters: vec![
                    string_parameter("task_id", "Task that should receive the message.", true),
                    string_parameter("message", "Message to send to the task.", true),
                ],
            },
            ToolSpec {
                name: ARCHIVE_TASK_TOOL_NAME.to_owned(),
                description: "Archive another active task.".to_owned(),
                parameters: vec![string_parameter("task_id", "Task to archive.", true)],
            },
        ],
    }
}

fn string_parameter(name: &str, description: &str, required: bool) -> ToolParameter {
    ToolParameter {
        name: name.to_owned(),
        parameter_type: ToolParameterType::String,
        description: description.to_owned(),
        required,
    }
}

fn integer_parameter(name: &str, description: &str, required: bool) -> ToolParameter {
    ToolParameter {
        name: name.to_owned(),
        parameter_type: ToolParameterType::Integer,
        description: description.to_owned(),
        required,
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HarnessInvocation {
    ForkTask(ForkTaskInvocation),
    ReadTask(ReadTaskInvocation),
    SendMessageToTask(SendMessageToTaskInvocation),
    ArchiveTask(ArchiveTaskInvocation),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ForkTaskInvocation {
    pub prompt: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReadTaskInvocation {
    pub task_id: Option<TaskId>,
    pub after_node_id: Option<HistoryNodeId>,
    pub limit: Option<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SendMessageToTaskInvocation {
    pub task_id: TaskId,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArchiveTaskInvocation {
    pub task_id: TaskId,
}

pub fn parse_invocation(request: &ToolExecutionRequest) -> Result<HarnessInvocation, HarnessError> {
    match request.tool_name.0.as_str() {
        FORK_TASK_TOOL_NAME => parse_fork_task(&request.arguments),
        READ_TASK_TOOL_NAME => parse_read_task(&request.arguments),
        SEND_MESSAGE_TO_TASK_TOOL_NAME => parse_send_message_to_task(&request.arguments),
        ARCHIVE_TASK_TOOL_NAME => parse_archive_task(&request.task_id, &request.arguments),
        unknown => Err(HarnessError::new(
            HarnessErrorCode::UnknownTool,
            format!("unknown tool '{unknown}'"),
        )),
    }
}

fn parse_fork_task(arguments: &[ToolCallArgument]) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["prompt"])?;
    let prompt = arguments.required_nonempty_string("prompt")?;
    Ok(HarnessInvocation::ForkTask(ForkTaskInvocation { prompt }))
}

fn parse_read_task(arguments: &[ToolCallArgument]) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["task_id", "after_node_id", "limit"])?;
    let task_id = arguments.optional_nonempty_string("task_id")?.map(TaskId);
    let after_node_id = arguments
        .optional_integer("after_node_id")?
        .map(HistoryNodeId);
    let limit = match arguments.optional_integer("limit")? {
        Some(limit) if (1..=MAX_READ_LIMIT).contains(&limit) => Some(limit as u8),
        Some(_) => {
            return Err(HarnessError::invalid_arguments(
                "argument 'limit' must be between 1 and 100",
            ));
        }
        None => None,
    };

    Ok(HarnessInvocation::ReadTask(ReadTaskInvocation {
        task_id,
        after_node_id,
        limit,
    }))
}

fn parse_send_message_to_task(
    arguments: &[ToolCallArgument],
) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["task_id", "message"])?;
    Ok(HarnessInvocation::SendMessageToTask(
        SendMessageToTaskInvocation {
            task_id: TaskId(arguments.required_nonempty_string("task_id")?),
            message: arguments.required_nonempty_string("message")?,
        },
    ))
}

fn parse_archive_task(
    calling_task_id: &TaskId,
    arguments: &[ToolCallArgument],
) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["task_id"])?;
    let task_id = TaskId(arguments.required_nonempty_string("task_id")?);
    if task_id == *calling_task_id {
        return Err(HarnessError::new(
            HarnessErrorCode::CannotArchiveCurrentTask,
            "cannot archive the calling task",
        ));
    }
    Ok(HarnessInvocation::ArchiveTask(ArchiveTaskInvocation {
        task_id,
    }))
}

struct Arguments<'a> {
    values: BTreeMap<&'a str, &'a ToolArgumentValue>,
}

impl<'a> Arguments<'a> {
    fn new(
        arguments: &'a [ToolCallArgument],
        allowed: &[&str],
    ) -> Result<Arguments<'a>, HarnessError> {
        let mut values = BTreeMap::new();
        for argument in arguments {
            let name = argument.name.0.as_str();
            if !allowed.contains(&name) {
                return Err(HarnessError::invalid_arguments(format!(
                    "unexpected argument '{name}'"
                )));
            }
            if values.insert(name, &argument.value).is_some() {
                return Err(HarnessError::invalid_arguments(format!(
                    "duplicate argument '{name}'"
                )));
            }
        }
        Ok(Arguments { values })
    }

    fn required_nonempty_string(&self, name: &str) -> Result<String, HarnessError> {
        self.optional_nonempty_string(name)?.ok_or_else(|| {
            HarnessError::invalid_arguments(format!("missing required argument '{name}'"))
        })
    }

    fn optional_nonempty_string(&self, name: &str) -> Result<Option<String>, HarnessError> {
        let Some(value) = self.values.get(name) else {
            return Ok(None);
        };
        let ToolArgumentValue::String(value) = value else {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must be a string"
            )));
        };
        if value.trim().is_empty() {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must not be empty"
            )));
        }
        Ok(Some(value.clone()))
    }

    fn optional_integer(&self, name: &str) -> Result<Option<i64>, HarnessError> {
        let Some(value) = self.values.get(name) else {
            return Ok(None);
        };
        let ToolArgumentValue::Integer(value) = value else {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must be an integer"
            )));
        };
        Ok(Some(*value))
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum HarnessSuccess {
    ForkTask(ForkTaskSuccess),
    ReadTask(ReadTaskSuccess),
    SendMessageToTask(SendMessageToTaskSuccess),
    ArchiveTask(ArchiveTaskSuccess),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ForkTaskSuccess {
    pub task_id: TaskId,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReadTaskSuccess {
    pub task_id: TaskId,
    pub status: TaskProjectionStatus,
    pub state_version: u64,
    pub cursor_node_id: HistoryNodeId,
    pub parent_task_id: Option<TaskId>,
    pub queued_message_count: u64,
    pub history: HistoryPage,
}

#[derive(Clone, Debug, PartialEq)]
pub struct HistoryPage {
    pub nodes: Vec<HistoryNodeProjection>,
    pub next_after_node_id: Option<HistoryNodeId>,
    pub has_more: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MessageDisposition {
    Committed { node_id: HistoryNodeId },
    Queued,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SendMessageToTaskSuccess {
    pub task_id: TaskId,
    pub disposition: MessageDisposition,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArchiveTaskSuccess {
    pub task_id: TaskId,
}

impl HarnessSuccess {
    pub fn to_stable_json(&self) -> String {
        success_json(self).to_string()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HarnessErrorCode {
    InvalidArguments,
    UnknownTool,
    TaskNotFound,
    TaskArchived,
    StaleToolCall,
    HistoryCursorNotOnTask,
    CannotArchiveCurrentTask,
    OperationCancelled,
    RouterUnavailable,
    RuntimeStartFailed,
    StorageError,
    ExecutorPanicked,
}

impl HarnessErrorCode {
    pub const fn as_str(self) -> &'static str {
        match self {
            HarnessErrorCode::InvalidArguments => "invalid_arguments",
            HarnessErrorCode::UnknownTool => "unknown_tool",
            HarnessErrorCode::TaskNotFound => "task_not_found",
            HarnessErrorCode::TaskArchived => "task_archived",
            HarnessErrorCode::StaleToolCall => "stale_tool_call",
            HarnessErrorCode::HistoryCursorNotOnTask => "history_cursor_not_on_task",
            HarnessErrorCode::CannotArchiveCurrentTask => "cannot_archive_current_task",
            HarnessErrorCode::OperationCancelled => "operation_cancelled",
            HarnessErrorCode::RouterUnavailable => "router_unavailable",
            HarnessErrorCode::RuntimeStartFailed => "runtime_start_failed",
            HarnessErrorCode::StorageError => "storage_error",
            HarnessErrorCode::ExecutorPanicked => "executor_panicked",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HarnessError {
    General {
        code: HarnessErrorCode,
        message: String,
    },
    RuntimeStartFailedAfterChildCreated {
        task_id: TaskId,
        message: String,
    },
}

impl HarnessError {
    pub fn new(code: HarnessErrorCode, message: impl Into<String>) -> Self {
        Self::General {
            code,
            message: message.into(),
        }
    }

    pub fn runtime_start_failed_after_child_created(
        task_id: TaskId,
        message: impl Into<String>,
    ) -> Self {
        Self::RuntimeStartFailedAfterChildCreated {
            task_id,
            message: message.into(),
        }
    }

    pub fn invalid_arguments(message: impl Into<String>) -> Self {
        Self::new(HarnessErrorCode::InvalidArguments, message)
    }

    pub const fn code(&self) -> HarnessErrorCode {
        match self {
            HarnessError::General { code, .. } => *code,
            HarnessError::RuntimeStartFailedAfterChildCreated { .. } => {
                HarnessErrorCode::RuntimeStartFailed
            }
        }
    }

    pub fn message(&self) -> &str {
        match self {
            HarnessError::General { message, .. }
            | HarnessError::RuntimeStartFailedAfterChildCreated { message, .. } => message,
        }
    }

    pub fn created_child_task_id(&self) -> Option<&TaskId> {
        match self {
            HarnessError::General { .. } => None,
            HarnessError::RuntimeStartFailedAfterChildCreated { task_id, .. } => Some(task_id),
        }
    }

    pub fn to_stable_json(&self) -> String {
        error_json(self).to_string()
    }
}

impl fmt::Display for HarnessError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.code().as_str(), self.message())
    }
}

impl Error for HarnessError {}

pub fn encode_tool_execution_result(
    request: &ToolExecutionRequest,
    outcome: Result<HarnessSuccess, HarnessError>,
) -> ToolExecutionResult {
    let (output_text, is_error) = match outcome {
        Ok(success) => (success.to_stable_json(), false),
        Err(error) => (error.to_stable_json(), true),
    };
    ToolExecutionResult {
        task_id: request.task_id.clone(),
        tool_execution_run_id: request.tool_execution_run_id.clone(),
        function_call_node_id: request.function_call_node_id,
        function_call_id: request.function_call_id.clone(),
        tool_name: request.tool_name.clone(),
        output_text,
        is_error,
    }
}

fn success_json(success: &HarnessSuccess) -> Value {
    match success {
        HarnessSuccess::ForkTask(success) => object([
            ("task_id", task_id_json(&success.task_id)),
            ("status", Value::String("active".to_owned())),
        ]),
        HarnessSuccess::ReadTask(success) => object([
            ("task_id", task_id_json(&success.task_id)),
            ("status", task_status_json(&success.status)),
            ("state_version", Value::from(success.state_version)),
            ("cursor_node_id", Value::from(success.cursor_node_id.0)),
            (
                "parent_task_id",
                optional_task_id_json(success.parent_task_id.as_ref()),
            ),
            (
                "queued_message_count",
                Value::from(success.queued_message_count),
            ),
            ("history", history_page_json(&success.history)),
        ]),
        HarnessSuccess::SendMessageToTask(success) => {
            let mut fields = BTreeMap::new();
            fields.insert("task_id".to_owned(), task_id_json(&success.task_id));
            match success.disposition {
                MessageDisposition::Committed { node_id } => {
                    fields.insert(
                        "disposition".to_owned(),
                        Value::String("committed".to_owned()),
                    );
                    fields.insert("node_id".to_owned(), Value::from(node_id.0));
                }
                MessageDisposition::Queued => {
                    fields.insert("disposition".to_owned(), Value::String("queued".to_owned()));
                }
            }
            Value::Object(fields.into_iter().collect())
        }
        HarnessSuccess::ArchiveTask(success) => object([
            ("task_id", task_id_json(&success.task_id)),
            ("status", Value::String("archived".to_owned())),
        ]),
    }
}

fn error_json(error: &HarnessError) -> Value {
    let mut fields = BTreeMap::from([
        (
            "code".to_owned(),
            Value::String(error.code().as_str().to_owned()),
        ),
        (
            "message".to_owned(),
            Value::String(error.message().to_owned()),
        ),
    ]);
    if let Some(task_id) = error.created_child_task_id() {
        fields.insert("task_created".to_owned(), Value::Bool(true));
        fields.insert("task_id".to_owned(), task_id_json(task_id));
    }
    object([("error", Value::Object(fields.into_iter().collect()))])
}

fn history_page_json(page: &HistoryPage) -> Value {
    object([
        (
            "nodes",
            Value::Array(page.nodes.iter().map(history_node_json).collect()),
        ),
        (
            "next_after_node_id",
            page.next_after_node_id
                .map_or(Value::Null, |node_id| Value::from(node_id.0)),
        ),
        ("has_more", Value::Bool(page.has_more)),
    ])
}

fn history_node_json(node: &HistoryNodeProjection) -> Value {
    let mut fields = BTreeMap::new();
    fields.insert("node_id".to_owned(), Value::from(node.node_id.0));
    fields.insert(
        "parent_node_id".to_owned(),
        node.parent_node_id
            .map_or(Value::Null, |node_id| Value::from(node_id.0)),
    );
    fields.insert("created_at".to_owned(), Value::from(node.created_at.0));

    match &node.body {
        HistoryNodeProjectionBody::Message { role, text } => {
            fields.insert("kind".to_owned(), Value::String("message".to_owned()));
            fields.insert("role".to_owned(), message_role_json(role));
            fields.insert("text".to_owned(), Value::String(text.clone()));
        }
        HistoryNodeProjectionBody::Reasoning { text } => {
            fields.insert("kind".to_owned(), Value::String("reasoning".to_owned()));
            fields.insert("text".to_owned(), Value::String(text.clone()));
        }
        HistoryNodeProjectionBody::FunctionCall {
            function_call_id,
            tool_name,
            arguments,
        } => {
            fields.insert("kind".to_owned(), Value::String("function_call".to_owned()));
            fields.insert(
                "function_call_id".to_owned(),
                Value::String(function_call_id.0.clone()),
            );
            fields.insert("tool_name".to_owned(), Value::String(tool_name.0.clone()));
            fields.insert(
                "arguments".to_owned(),
                Value::Array(arguments.iter().map(tool_argument_json).collect()),
            );
        }
        HistoryNodeProjectionBody::FunctionOutput {
            function_call_node_id,
            function_call_id,
            tool_name,
            output_text,
            is_error,
        } => {
            fields.insert(
                "kind".to_owned(),
                Value::String("function_output".to_owned()),
            );
            fields.insert(
                "function_call_node_id".to_owned(),
                Value::from(function_call_node_id.0),
            );
            fields.insert(
                "function_call_id".to_owned(),
                Value::String(function_call_id.0.clone()),
            );
            fields.insert("tool_name".to_owned(), Value::String(tool_name.0.clone()));
            fields.insert("output_text".to_owned(), Value::String(output_text.clone()));
            fields.insert("is_error".to_owned(), Value::Bool(*is_error));
        }
    }

    Value::Object(fields.into_iter().collect())
}

fn tool_argument_json(argument: &ToolCallArgument) -> Value {
    object([
        ("name", Value::String(argument.name.0.clone())),
        ("value", tool_argument_value_json(&argument.value)),
    ])
}

fn tool_argument_value_json(value: &ToolArgumentValue) -> Value {
    match value {
        ToolArgumentValue::String(value) => Value::String(value.clone()),
        ToolArgumentValue::Integer(value) => Value::from(*value),
        ToolArgumentValue::Number(value) => {
            Number::from_f64(*value).map_or(Value::Null, Value::Number)
        }
        ToolArgumentValue::Boolean(value) => Value::Bool(*value),
    }
}

fn task_id_json(task_id: &TaskId) -> Value {
    Value::String(task_id.0.clone())
}

fn optional_task_id_json(task_id: Option<&TaskId>) -> Value {
    task_id.map_or(Value::Null, task_id_json)
}

fn task_status_json(status: &TaskProjectionStatus) -> Value {
    Value::String(
        match status {
            TaskProjectionStatus::Active => "active",
            TaskProjectionStatus::Archived => "archived",
        }
        .to_owned(),
    )
}

fn message_role_json(role: &MessageRole) -> Value {
    Value::String(
        match role {
            MessageRole::System => "system",
            MessageRole::Developer => "developer",
            MessageRole::User => "user",
            MessageRole::Assistant => "assistant",
            MessageRole::Tool => "tool",
        }
        .to_owned(),
    )
}

fn object<const N: usize>(entries: [(&str, Value); N]) -> Value {
    let fields = entries
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value))
        .collect::<BTreeMap<_, _>>();
    Value::Object(fields.into_iter().collect())
}
