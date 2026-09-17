use chatgpt_auth::{ChatgptStoredTokens, persist_chatgpt_auth_file};

#[tokio::test]
async fn public_writer_rejects_empty_tokens_without_replacing_file() {
    let tempdir = tempfile::tempdir().expect("temp dir");
    let guard = selvedge_model_credentials::lock_credential_from_home(tempdir.path(), "chatgpt")
        .await
        .expect("credential lock");
    let path = guard.path().to_owned();
    std::fs::write(&path, "existing credentials").expect("write existing file");
    let tokens = ChatgptStoredTokens {
        id_token: "id-token".to_owned(),
        access_token: String::new(),
        refresh_token: "refresh-token".to_owned(),
    };

    let error = persist_chatgpt_auth_file(&guard, &tokens).expect_err("empty token must fail");

    assert_eq!(error.path, path);
    assert_eq!(error.reason, "tokens.access_token must not be empty");
    assert_eq!(
        std::fs::read_to_string(&path).expect("read existing file"),
        "existing credentials"
    );
}
