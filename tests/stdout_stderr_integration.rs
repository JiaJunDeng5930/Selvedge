use std::process::Command;

#[test]
fn binary_keeps_logs_off_stdout() {
    let output = Command::new(env!("CARGO_BIN_EXE_selvedge"))
        .env_remove("SELVEDGE_CONFIG")
        .env_remove("SELVEDGE_APP")
        .env_remove("SELVEDGE_APP__LOGGING__LEVEL")
        .env_remove("SELVEDGE_APP__LOGGING__MODULE_LEVELS")
        .output()
        .expect("run selvedge binary");

    assert!(output.status.success(), "binary failed: {output:?}");

    let stdout = String::from_utf8(output.stdout).expect("stdout utf8");
    let stderr = String::from_utf8(output.stderr).expect("stderr utf8");

    assert_eq!(stdout.trim(), "selvedge is ready.");
    assert!(stderr.contains("message=\"selvedge started\""));
}
