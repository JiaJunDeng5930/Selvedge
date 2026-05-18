use selvedge_model_credentials::{
    CredentialKind, ModelCredentialRecord, credential_path, read_credential_from_home,
    write_credential_to_home,
};

#[tokio::test]
// @verifies selvedge.model.credentials.write.from_home
// @verifies selvedge.model.credentials.read.from_home
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

    // @verifies selvedge.model.credentials.path
    assert_eq!(
        path,
        tempdir.path().join("auth/model-providers/chatgpt.json")
    );
    // @verifies selvedge.model.credentials.read.from_home
    assert_eq!(loaded, record);
}

#[test]
// @verifies selvedge.model.credentials.path
fn credential_path_rejects_path_unsafe_provider_ids() {
    let tempdir = tempfile::TempDir::new().expect("tempdir");
    let error = credential_path(tempdir.path(), "../chatgpt").expect_err("invalid provider");

    assert_eq!(
        error.to_string(),
        "provider id \"../chatgpt\" is not path-safe"
    );
}
