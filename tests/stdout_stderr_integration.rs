use std::process::Command;
use tempfile::TempDir;

#[test]
fn binary_keeps_logs_off_stdout() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    command.env_remove("SELVEDGE_HOME");
    command.env("HOME", tempdir.path());
    command.env("XDG_CONFIG_HOME", tempdir.path());

    for (key, _) in std::env::vars_os() {
        if key
            .to_str()
            .is_some_and(|name| name.starts_with("SELVEDGE_APP_"))
        {
            command.env_remove(key);
        }
    }

    let output = command.output().expect("run selvedge binary");

    assert!(output.status.success(), "binary failed: {output:?}");

    let stdout = String::from_utf8(output.stdout).expect("stdout utf8");
    let stderr = String::from_utf8(output.stderr).expect("stderr utf8");

    assert_eq!(stdout.trim(), "selvedge is ready.");
    assert!(stderr.contains("message=\"selvedge started\""));
}

#[test]
fn binary_creates_default_selvedge_home_when_missing() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let expected_config = tempdir.path().join(".selvedge/config.toml");

    command.env_remove("SELVEDGE_HOME");
    command.env("HOME", tempdir.path());
    command.env("XDG_CONFIG_HOME", tempdir.path().join("xdg-home"));

    for (key, _) in std::env::vars_os() {
        if key
            .to_str()
            .is_some_and(|name| name.starts_with("SELVEDGE_APP_"))
        {
            command.env_remove(key);
        }
    }

    let output = command.output().expect("run selvedge binary");

    assert!(output.status.success(), "binary failed: {output:?}");
    assert!(expected_config.is_file(), "default config was not created");
}
