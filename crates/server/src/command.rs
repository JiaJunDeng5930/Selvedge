use selvedge_local_protocol::CommandRequest;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ClientCommand {
    LoginChatgpt,
    ListModels,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ClientCommandDecodeError {
    MalformedPayload,
    UnsupportedCommand,
}

impl TryFrom<&CommandRequest> for ClientCommand {
    type Error = ClientCommandDecodeError;

    fn try_from(request: &CommandRequest) -> Result<Self, Self::Error> {
        let command = match request.command_name.as_str() {
            "login-chatgpt" => Self::LoginChatgpt,
            "list-models" => Self::ListModels,
            _ => return Err(ClientCommandDecodeError::UnsupportedCommand),
        };
        if !request
            .payload
            .as_object()
            .is_some_and(|object| object.is_empty())
        {
            return Err(ClientCommandDecodeError::MalformedPayload);
        }
        Ok(command)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use selvedge_local_protocol::{LocalClientCommandId, LocalClientId};

    #[test]
    fn decodes_supported_commands_with_empty_payloads() {
        for (command_name, expected) in [
            ("login-chatgpt", ClientCommand::LoginChatgpt),
            ("list-models", ClientCommand::ListModels),
        ] {
            assert_eq!(
                ClientCommand::try_from(&request(command_name, serde_json::json!({}))),
                Ok(expected)
            );
        }
    }

    #[test]
    fn rejects_malformed_payload_for_supported_command() {
        assert_eq!(
            ClientCommand::try_from(&request(
                "login-chatgpt",
                serde_json::json!({"unexpected": true}),
            )),
            Err(ClientCommandDecodeError::MalformedPayload)
        );
    }

    #[test]
    fn rejects_unknown_command() {
        assert_eq!(
            ClientCommand::try_from(&request("send-user-input", serde_json::json!({}))),
            Err(ClientCommandDecodeError::UnsupportedCommand)
        );
    }

    fn request(command_name: &str, payload: serde_json::Value) -> CommandRequest {
        CommandRequest {
            client_id: LocalClientId("client-1".to_owned()),
            client_command_id: LocalClientCommandId("command-1".to_owned()),
            command_name: command_name.to_owned(),
            payload,
        }
    }
}
