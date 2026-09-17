use selvedge_model_credentials::{
    CredentialKind, ModelCredentialRecord, credential_path, read_credential_from_home,
    write_credential_to_home,
};

#[tokio::test]
async fn write_then_read_persists_provider_credential_record() {
    let tempdir = tempfile::TempDir::new().expect("tempdir");
    let record = ModelCredentialRecord {
        schema_version: 1,
        provider: "chatgpt".to_owned(),
        credential_kind: CredentialKind::Login,
        payload: serde_json::json!({
            "tokens": {
                "id_token": "id",
                "access_token": "access",
                "refresh_token": "refresh"
            }
        }),
    };

    let path = write_credential_to_home(tempdir.path(), &record)
        .await
        .expect("persist credential");
    let loaded = read_credential_from_home(tempdir.path(), "chatgpt")
        .await
        .expect("read credential")
        .expect("credential present");

    assert_eq!(
        path,
        tempdir.path().join("auth/model-providers/chatgpt.json")
    );
    assert_eq!(loaded, record);
}

#[test]
fn credential_path_rejects_path_unsafe_provider_ids() {
    let tempdir = tempfile::TempDir::new().expect("tempdir");
    let error = credential_path(tempdir.path(), "../chatgpt").expect_err("invalid provider");

    assert_eq!(
        error.to_string(),
        "provider id \"../chatgpt\" is not path-safe"
    );
}

#[tokio::test]
async fn locked_writer_rejects_another_provider_without_replacing_credential() {
    let home = tempfile::tempdir().expect("temporary home");
    let guard = selvedge_model_credentials::lock_credential_from_home(home.path(), "chatgpt")
        .await
        .expect("credential lock");
    let mut record = ModelCredentialRecord {
        schema_version: 1,
        provider: "chatgpt".to_owned(),
        credential_kind: CredentialKind::Login,
        payload: serde_json::json!({"tokens": {"access_token": "original"}}),
    };
    guard.write(&record).expect("write under lock");
    let original = std::fs::read(guard.path()).expect("original bytes");
    record.provider = "other".to_owned();
    guard.write(&record).expect_err("guard belongs to chatgpt");
    assert_eq!(
        std::fs::read(guard.path()).expect("unchanged bytes"),
        original
    );
    assert_eq!(
        guard
            .read()
            .expect("read under lock")
            .expect("credential")
            .provider,
        "chatgpt"
    );
}
