use std::process::{Child, Command, Output, Stdio};

// @behavior selvedge.testsupport.process Child-process helpers let integration tests isolate global process state while rerunning the current test binary.
pub fn child_mode(flag: &str) -> bool {
    std::env::var_os(flag).is_some()
}

// @behavior selvedge.testsupport.process.run_child Integration tests can rerun one exact test in a child process with a marker environment variable.
pub fn run_child(test_name: &str, flag: &str) -> Output {
    spawn_child(test_name, flag, &[])
        .wait_with_output()
        .expect("run child test")
}

// @behavior selvedge.testsupport.process.spawn_child Integration tests can spawn one exact test in a child process with extra environment variables.
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

    // @behavior selvedge.testsupport.process.spawn_child.fail Fast fixture setup fails the calling test when the isolated child process cannot be spawned.
    command.spawn().expect("spawn child test")
}

// @behavior selvedge.testsupport.process.assert_child_success Integration tests can assert that an isolated child test completed successfully.
pub fn assert_child_success(output: &Output) {
    assert!(output.status.success(), "child test failed: {output:?}");
}
