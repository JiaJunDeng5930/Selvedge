use std::collections::BTreeMap;
use std::error::Error;
use std::fmt;
use std::future::Future;
use std::io;
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use rmcp::model::{
    CallToolRequest, CallToolRequestParams, ClientRequest, PaginatedRequestParams, ServerResult,
    TaskSupport, Tool,
};
use rmcp::service::{PeerRequestOptions, RunningService, RxJsonRpcMessage, TxJsonRpcMessage};
use rmcp::transport::{Transport, async_rw::JsonRpcMessageCodec};
use rmcp::{Peer, RoleClient, ServiceError, ServiceExt};
use rustix::process::Pid;
use selvedge_config_model::McpServerConfig;
use selvedge_db::{TaskToolSpec, ToolExecutionSource};
use selvedge_domain_model::{JsonObject, ToolSpec};
use serde_json::Value;
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use tokio::sync::Mutex;
use tokio_util::codec::{FramedRead, FramedWrite};

use crate::{HarnessError, HarnessErrorCode, ProcessGroupGuard};

type McpService = RunningService<RoleClient, ()>;

const MAX_MCP_FRAME_BYTES: usize = 4 * 1024 * 1024;
const MAX_MCP_CATALOG_BYTES: usize = 4 * 1024 * 1024;
const MAX_MCP_TOOL_COUNT: usize = 1_024;
const MCP_CHILD_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(3);

#[derive(Clone, Default)]
pub struct McpConnectionSet {
    connections: Arc<BTreeMap<String, Arc<McpConnection>>>,
}

struct McpConnection {
    peer: Peer<RoleClient>,
    service: Mutex<Option<McpService>>,
    timeout: Duration,
}

impl McpConnectionSet {
    pub async fn connect(
        configs: &BTreeMap<String, McpServerConfig>,
    ) -> Result<(Self, Vec<TaskToolSpec>), McpStartupError> {
        let mut connections = BTreeMap::new();
        let mut registrations = Vec::new();
        let mut routes = BTreeMap::<String, (String, String)>::new();
        let mut catalog_budget = CatalogBudget::default();

        for (server_id, config) in configs {
            let (connection, tools) =
                match connect_server(server_id, config, &mut catalog_budget).await {
                    Ok(connected) => connected,
                    Err(error) => {
                        close_connections(connections).await;
                        return Err(error);
                    }
                };
            connections.insert(server_id.clone(), Arc::new(connection));

            for tool in tools {
                let registration = match convert_tool(server_id, tool) {
                    Ok(registration) => registration,
                    Err(error) => {
                        close_connections(connections).await;
                        return Err(error);
                    }
                };
                let route = (
                    server_id.clone(),
                    remote_tool_name(&registration).to_owned(),
                );
                if let Some(previous) = routes.insert(registration.tool.name.clone(), route.clone())
                {
                    close_connections(connections).await;
                    return Err(McpStartupError::NormalizedNameCollision {
                        local_name: registration.tool.name,
                        first_server_id: previous.0,
                        first_remote_tool_name: previous.1,
                        second_server_id: route.0,
                        second_remote_tool_name: route.1,
                    });
                }
                registrations.push(registration);
            }
        }

        Ok((
            Self {
                connections: Arc::new(connections),
            },
            registrations,
        ))
    }

    pub async fn close(&self) {
        for connection in self.connections.values() {
            let service = connection.service.lock().await.take();
            if let Some(mut service) = service {
                let _ = service.close().await;
            }
        }
    }

    pub(crate) async fn call_tool(
        &self,
        server_id: &str,
        remote_tool_name: String,
        arguments: JsonObject,
    ) -> Result<(Value, bool), HarnessError> {
        let connection = self.connections.get(server_id).ok_or_else(|| {
            HarnessError::new(
                HarnessErrorCode::McpRouteUnavailable,
                format!("MCP server '{server_id}' is not connected"),
            )
        })?;
        let request = ClientRequest::CallToolRequest(CallToolRequest::new(
            CallToolRequestParams::new(remote_tool_name).with_arguments(arguments),
        ));
        let handle = connection
            .peer
            .send_cancellable_request(
                request,
                PeerRequestOptions::with_timeout(connection.timeout),
            )
            .await
            .map_err(|error| map_call_error(server_id, connection.timeout, error))?;
        let response = handle
            .await_response()
            .await
            .map_err(|error| map_call_error(server_id, connection.timeout, error))?;
        let ServerResult::CallToolResult(result) = response else {
            return Err(HarnessError::new(
                HarnessErrorCode::McpCallFailed,
                format!("MCP tool call on server '{server_id}' returned an unexpected response"),
            ));
        };
        let is_error = result.is_error == Some(true);
        let output = serde_json::to_value(result).map_err(|error| {
            HarnessError::new(
                HarnessErrorCode::McpResultEncodingFailed,
                format!("failed to encode MCP tool result: {error}"),
            )
        })?;
        Ok((output, is_error))
    }
}

fn map_call_error(server_id: &str, timeout: Duration, error: ServiceError) -> HarnessError {
    match error {
        ServiceError::Timeout { .. } => HarnessError::new(
            HarnessErrorCode::McpCallTimedOut,
            format!(
                "MCP tool call on server '{server_id}' timed out after {} ms",
                timeout.as_millis()
            ),
        ),
        error => HarnessError::new(
            HarnessErrorCode::McpCallFailed,
            format!("MCP tool call on server '{server_id}' failed: {error}"),
        ),
    }
}

async fn close_connections(connections: BTreeMap<String, Arc<McpConnection>>) {
    McpConnectionSet {
        connections: Arc::new(connections),
    }
    .close()
    .await;
}

async fn connect_server(
    server_id: &str,
    config: &McpServerConfig,
    catalog_budget: &mut CatalogBudget,
) -> Result<(McpConnection, Vec<Tool>), McpStartupError> {
    let timeout = Duration::from_millis(config.timeout_ms);
    let mut command = Command::new(&config.command);
    command.args(&config.args).envs(&config.env);
    let transport =
        BoundedChildProcess::spawn(command).map_err(|source| McpStartupError::Spawn {
            server_id: server_id.to_owned(),
            source,
        })?;
    let mut service = tokio::time::timeout(timeout, ().serve(transport))
        .await
        .map_err(|_| McpStartupError::TimedOut {
            server_id: server_id.to_owned(),
            operation: McpStartupOperation::Initialize,
            timeout_ms: config.timeout_ms,
        })?
        .map_err(|error| McpStartupError::Initialize {
            server_id: server_id.to_owned(),
            message: error.to_string(),
        })?;
    let peer = service.peer().clone();
    let tools =
        match tokio::time::timeout(timeout, discover_tools(&peer, server_id, catalog_budget)).await
        {
            Ok(Ok(tools)) => tools,
            Ok(Err(error)) => {
                let _ = service.close().await;
                return Err(error);
            }
            Err(_) => {
                let _ = service.close().await;
                return Err(McpStartupError::TimedOut {
                    server_id: server_id.to_owned(),
                    operation: McpStartupOperation::ListTools,
                    timeout_ms: config.timeout_ms,
                });
            }
        };
    Ok((
        McpConnection {
            peer,
            service: Mutex::new(Some(service)),
            timeout,
        },
        tools,
    ))
}

async fn discover_tools(
    peer: &Peer<RoleClient>,
    server_id: &str,
    catalog_budget: &mut CatalogBudget,
) -> Result<Vec<Tool>, McpStartupError> {
    let mut tools = Vec::new();
    let mut cursor = None;
    loop {
        let result = peer
            .list_tools(Some(PaginatedRequestParams::default().with_cursor(cursor)))
            .await
            .map_err(|error| McpStartupError::ListTools {
                server_id: server_id.to_owned(),
                message: error.to_string(),
            })?;
        for tool in result.tools {
            catalog_budget.consume(server_id, &tool)?;
            tools.push(tool);
        }
        cursor = result.next_cursor;
        if cursor.is_none() {
            return Ok(tools);
        }
    }
}

struct CatalogBudget {
    tool_count: usize,
    catalog_bytes: usize,
}

impl Default for CatalogBudget {
    fn default() -> Self {
        Self {
            tool_count: 0,
            catalog_bytes: 2,
        }
    }
}

impl CatalogBudget {
    fn consume(&mut self, server_id: &str, tool: &Tool) -> Result<(), McpStartupError> {
        let encoded_len = serde_json::to_vec(tool)
            .map_err(|error| McpStartupError::ListTools {
                server_id: server_id.to_owned(),
                message: format!("failed to measure tool catalog: {error}"),
            })?
            .len();
        self.catalog_bytes = self
            .catalog_bytes
            .saturating_add(encoded_len + usize::from(self.tool_count > 0));
        if self.tool_count == MAX_MCP_TOOL_COUNT || self.catalog_bytes > MAX_MCP_CATALOG_BYTES {
            return Err(McpStartupError::CatalogLimitExceeded {
                server_id: server_id.to_owned(),
                max_tools: MAX_MCP_TOOL_COUNT,
                max_bytes: MAX_MCP_CATALOG_BYTES,
            });
        }
        self.tool_count += 1;
        Ok(())
    }
}

type McpWriter = FramedWrite<ChildStdin, JsonRpcMessageCodec<TxJsonRpcMessage<RoleClient>>>;

struct BoundedChildProcess {
    child: Option<Child>,
    process_group: ProcessGroupGuard,
    reader: FramedRead<ChildStdout, JsonRpcMessageCodec<RxJsonRpcMessage<RoleClient>>>,
    writer: Arc<Mutex<Option<McpWriter>>>,
}

impl BoundedChildProcess {
    fn spawn(mut command: Command) -> io::Result<Self> {
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true)
            .process_group(0);
        let mut child = command.spawn()?;
        let process_group_id = child
            .id()
            .and_then(|id| i32::try_from(id).ok())
            .and_then(Pid::from_raw)
            .ok_or_else(|| io::Error::other("spawned MCP server did not have a process ID"))?;
        let process_group = ProcessGroupGuard::new(process_group_id);
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("MCP child stdout was not piped"))?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("MCP child stdin was not piped"))?;
        Ok(Self {
            child: Some(child),
            process_group,
            reader: FramedRead::new(
                stdout,
                JsonRpcMessageCodec::new_with_max_length(MAX_MCP_FRAME_BYTES),
            ),
            writer: Arc::new(Mutex::new(Some(FramedWrite::new(
                stdin,
                JsonRpcMessageCodec::default(),
            )))),
        })
    }
}

impl Transport<RoleClient> for BoundedChildProcess {
    type Error = io::Error;

    fn send(
        &mut self,
        item: TxJsonRpcMessage<RoleClient>,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send + 'static {
        let writer = self.writer.clone();
        async move {
            let mut writer = writer.lock().await;
            match writer.as_mut() {
                Some(writer) => writer.send(item).await.map_err(Into::into),
                None => Err(io::Error::new(
                    io::ErrorKind::NotConnected,
                    "MCP transport is closed",
                )),
            }
        }
    }

    async fn receive(&mut self) -> Option<RxJsonRpcMessage<RoleClient>> {
        match self.reader.next().await {
            Some(Ok(message)) => Some(message),
            Some(Err(_)) | None => None,
        }
    }

    async fn close(&mut self) -> Result<(), Self::Error> {
        self.writer.lock().await.take();
        let Some(mut child) = self.child.take() else {
            self.process_group
                .terminate_raw()
                .map_err(|error| io::Error::other(error.to_string()))?;
            self.process_group.disarm();
            return Ok(());
        };
        let wait_result = match tokio::time::timeout(MCP_CHILD_SHUTDOWN_TIMEOUT, child.wait()).await
        {
            Ok(result) => result,
            Err(_) => {
                self.process_group
                    .terminate_raw()
                    .map_err(|error| io::Error::other(error.to_string()))?;
                tokio::time::timeout(MCP_CHILD_SHUTDOWN_TIMEOUT, child.wait())
                    .await
                    .map_err(|_| io::Error::other("MCP process group could not be reaped"))?
            }
        };
        let termination = self
            .process_group
            .terminate_raw()
            .map_err(|error| io::Error::other(error.to_string()));
        if termination.is_ok() {
            self.process_group.disarm();
        }
        wait_result.map(|_| ())?;
        termination
    }
}

fn convert_tool(server_id: &str, tool: Tool) -> Result<TaskToolSpec, McpStartupError> {
    if tool.task_support() == TaskSupport::Required {
        return Err(McpStartupError::TaskModeRequired {
            server_id: server_id.to_owned(),
            remote_tool_name: tool.name.into_owned(),
        });
    }
    let remote_tool_name = tool.name.into_owned();
    let local_name = model_tool_name(server_id, &remote_tool_name)?;
    let description = tool
        .description
        .map(|value| value.into_owned())
        .filter(|description| !description.trim().is_empty())
        .unwrap_or_else(|| format!("MCP tool '{remote_tool_name}' from server '{server_id}'."));
    Ok(TaskToolSpec {
        tool: ToolSpec {
            name: local_name,
            description,
            input_schema: tool.input_schema.as_ref().clone(),
        },
        execution_source: ToolExecutionSource::Mcp {
            server_id: server_id.to_owned(),
            remote_tool_name,
        },
    })
}

fn remote_tool_name(tool: &TaskToolSpec) -> &str {
    match &tool.execution_source {
        ToolExecutionSource::Mcp {
            remote_tool_name, ..
        } => remote_tool_name,
        ToolExecutionSource::Harness => unreachable!("MCP discovery only creates MCP routes"),
    }
}

fn model_tool_name(server_id: &str, remote_tool_name: &str) -> Result<String, McpStartupError> {
    if remote_tool_name.is_empty() {
        return Err(McpStartupError::InvalidToolName {
            server_id: server_id.to_owned(),
            remote_tool_name: remote_tool_name.to_owned(),
            local_name: None,
        });
    }
    let local_name = format!(
        "mcp__{}__{}",
        server_id.replace('.', "_"),
        remote_tool_name.replace('.', "_")
    );
    if local_name.len() > 64
        || !local_name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
    {
        return Err(McpStartupError::InvalidToolName {
            server_id: server_id.to_owned(),
            remote_tool_name: remote_tool_name.to_owned(),
            local_name: Some(local_name),
        });
    }
    Ok(local_name)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum McpStartupOperation {
    Initialize,
    ListTools,
}

impl fmt::Display for McpStartupOperation {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Initialize => "initialize",
            Self::ListTools => "tools/list",
        })
    }
}

#[derive(Debug)]
pub enum McpStartupError {
    Spawn {
        server_id: String,
        source: io::Error,
    },
    Initialize {
        server_id: String,
        message: String,
    },
    ListTools {
        server_id: String,
        message: String,
    },
    CatalogLimitExceeded {
        server_id: String,
        max_tools: usize,
        max_bytes: usize,
    },
    TimedOut {
        server_id: String,
        operation: McpStartupOperation,
        timeout_ms: u64,
    },
    InvalidToolName {
        server_id: String,
        remote_tool_name: String,
        local_name: Option<String>,
    },
    NormalizedNameCollision {
        local_name: String,
        first_server_id: String,
        first_remote_tool_name: String,
        second_server_id: String,
        second_remote_tool_name: String,
    },
    TaskModeRequired {
        server_id: String,
        remote_tool_name: String,
    },
}

impl fmt::Display for McpStartupError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Spawn { server_id, source } => {
                write!(
                    formatter,
                    "failed to start MCP server '{server_id}': {source}"
                )
            }
            Self::Initialize { server_id, message } => {
                write!(
                    formatter,
                    "MCP server '{server_id}' initialization failed: {message}"
                )
            }
            Self::ListTools { server_id, message } => {
                write!(
                    formatter,
                    "MCP server '{server_id}' tools/list failed: {message}"
                )
            }
            Self::CatalogLimitExceeded {
                server_id,
                max_tools,
                max_bytes,
            } => write!(
                formatter,
                "MCP server '{server_id}' tool catalog exceeds {max_tools} tools or {max_bytes} bytes"
            ),
            Self::TimedOut {
                server_id,
                operation,
                timeout_ms,
            } => write!(
                formatter,
                "MCP server '{server_id}' {operation} timed out after {timeout_ms} ms"
            ),
            Self::InvalidToolName {
                server_id,
                remote_tool_name,
                local_name,
            } => write!(
                formatter,
                "MCP tool '{remote_tool_name}' from server '{server_id}' produces invalid model tool name '{}'",
                local_name.as_deref().unwrap_or("")
            ),
            Self::NormalizedNameCollision {
                local_name,
                first_server_id,
                first_remote_tool_name,
                second_server_id,
                second_remote_tool_name,
            } => write!(
                formatter,
                "MCP model tool name '{local_name}' collides between '{first_server_id}/{first_remote_tool_name}' and '{second_server_id}/{second_remote_tool_name}'"
            ),
            Self::TaskModeRequired {
                server_id,
                remote_tool_name,
            } => write!(
                formatter,
                "MCP tool '{remote_tool_name}' from server '{server_id}' requires unsupported task-mode execution"
            ),
        }
    }
}

impl Error for McpStartupError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Spawn { source, .. } => Some(source),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{McpStartupError, model_tool_name};

    #[test]
    fn model_tool_names_replace_only_dots_and_enforce_wire_constraints() {
        assert_eq!(
            model_tool_name("git.hub", "pull.request").expect("valid name"),
            "mcp__git_hub__pull_request"
        );
        assert!(matches!(
            model_tool_name("server", "bad/name"),
            Err(McpStartupError::InvalidToolName { .. })
        ));
        assert!(matches!(
            model_tool_name("server", &"x".repeat(60)),
            Err(McpStartupError::InvalidToolName { .. })
        ));
        assert!(matches!(
            model_tool_name("server", ""),
            Err(McpStartupError::InvalidToolName { .. })
        ));
    }
}
