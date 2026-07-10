use std::process::{Child, Command, Output, Stdio};

pub fn child_mode(flag: &str) -> bool {
    std::env::var_os(flag).is_some()
}

pub fn run_child(test_name: &str, flag: &str) -> Output {
    spawn_child(test_name, flag, &[])
        .wait_with_output()
        .expect("run child test")
}

pub fn spawn_child(test_name: &str, flag: &str, extra_envs: &[(&str, &str)]) -> Child {
    let current_executable = std::env::current_exe().expect("current test executable");
    let mut command = Command::new(current_executable);

    command
        .arg("--exact")
        .arg(test_name)
        .env(flag, "1")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    for (key, value) in extra_envs {
        command.env(key, value);
    }

    command.spawn().expect("spawn child test")
}

pub fn assert_child_success(output: &Output) {
    assert!(output.status.success(), "child test failed: {output:?}");
}
