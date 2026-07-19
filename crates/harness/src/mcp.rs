use std::collections::BTreeMap;
use std::error::Error;
use std::fmt;
use std::io;
use std::sync::Arc;
use std::time::Duration;

use rmcp::model::{
    CallToolRequest, CallToolRequestParams, ClientRequest, ServerResult, TaskSupport, Tool,
};
use rmcp::service::{PeerRequestOptions, RunningService};
use rmcp::transport::TokioChildProcess;
use rmcp::{Peer, RoleClient, ServiceError, ServiceExt};
use selvedge_config_model::McpServerConfig;
use selvedge_db::McpToolRegistration;
use selvedge_domain_model::{JsonObject, ToolSpec};
use serde_json::Value;
use tokio::process::Command;
use tokio::sync::Mutex;

use crate::{HarnessError, HarnessErrorCode};

type McpService = RunningService<RoleClient, ()>;

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
    ) -> Result<(Self, Vec<McpToolRegistration>), McpStartupError> {
        let mut connections = BTreeMap::new();
        let mut registrations = Vec::new();
        let mut routes = BTreeMap::<String, (String, String)>::new();

        for (server_id, config) in configs {
            let (connection, tools) = match connect_server(server_id, config).await {
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
                    registration.server_id.clone(),
                    registration.remote_tool_name.clone(),
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
) -> Result<(McpConnection, Vec<Tool>), McpStartupError> {
    let timeout = Duration::from_millis(config.timeout_ms);
    let mut command = Command::new(&config.command);
    command.args(&config.args).envs(&config.env);
    let transport = TokioChildProcess::new(command).map_err(|source| McpStartupError::Spawn {
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
    let tools = match tokio::time::timeout(timeout, peer.list_all_tools()).await {
        Ok(Ok(tools)) => tools,
        Ok(Err(error)) => {
            let _ = service.close().await;
            return Err(McpStartupError::ListTools {
                server_id: server_id.to_owned(),
                message: error.to_string(),
            });
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

fn convert_tool(server_id: &str, tool: Tool) -> Result<McpToolRegistration, McpStartupError> {
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
    Ok(McpToolRegistration {
        tool: ToolSpec {
            name: local_name,
            description,
            input_schema: tool.input_schema.as_ref().clone(),
        },
        server_id: server_id.to_owned(),
        remote_tool_name,
    })
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
