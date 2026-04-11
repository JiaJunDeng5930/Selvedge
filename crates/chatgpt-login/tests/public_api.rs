use std::{path::PathBuf, time::Duration};

use chatgpt_login::{
    ChatgptLoginError, ChatgptLoginResult, DeviceCodeAuthorization, DeviceCodeChallenge,
    DeviceCodePollOutcome, complete_device_code_login, poll_device_code_login,
    start_device_code_login,
};
use chrono::{TimeZone, Utc};

#[test]
fn public_api_exposes_chatgpt_device_code_types_and_functions() {
    let challenge = DeviceCodeChallenge {
        verification_url: "https://auth.openai.com/codex/device".to_owned(),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: Duration::from_secs(5),
        issued_at: Utc
            .timestamp_opt(1_700_000_000, 0)
            .single()
            .expect("issued_at"),
        expires_at: Utc
            .timestamp_opt(1_700_000_900, 0)
            .single()
            .expect("expires_at"),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };
    let result = ChatgptLoginResult {
        auth_file_path: PathBuf::from("/tmp/chatgpt-auth.json"),
        account_id: "account-id".to_owned(),
        user_id: Some("user-id".to_owned()),
        email: Some("user@example.com".to_owned()),
        plan_type: Some("plus".to_owned()),
    };

    assert_eq!(
        challenge.verification_url,
        "https://auth.openai.com/codex/device"
    );
    assert_eq!(authorization.code_verifier, "code-verifier");
    assert_eq!(result.account_id, "account-id");
    assert!(matches!(
        DeviceCodePollOutcome::Authorized(authorization.clone()),
        DeviceCodePollOutcome::Authorized(DeviceCodeAuthorization { .. })
    ));
    assert!(matches!(
        ChatgptLoginError::ChallengeExpired,
        ChatgptLoginError::ChallengeExpired
    ));

    let _ = start_device_code_login;
    let _ = poll_device_code_login;
    let _ = complete_device_code_login;
}
