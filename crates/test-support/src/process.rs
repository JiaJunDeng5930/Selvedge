use std::process::{Child, Command, Output, Stdio};

const CHILD_TARGET: &str = "SELVEDGE_TEST_CHILD_TARGET";
const CHILD_STARTED: &str = "selvedge child test entered: ";

pub fn child_mode(flag: &str) -> bool {
    if std::env::var_os(flag).is_none() {
        return false;
    }
    let expected = std::env::var(CHILD_TARGET).expect("child test target");
    let thread = std::thread::current();
    assert_eq!(
        thread.name(),
        Some(expected.as_str()),
        "wrong child test entered"
    );
    eprintln!("{CHILD_STARTED}{expected}");
    true
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
        .arg("--nocapture")
        .env(CHILD_TARGET, test_name)
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
    assert!(
        String::from_utf8_lossy(&output.stderr)
            .lines()
            .any(|line| line.starts_with(CHILD_STARTED)),
        "child test never acknowledged entering its expected test: {output:?}"
    );
}

#[cfg(test)]
mod tests {
    use super::{assert_child_success, child_mode, run_child};

    #[test]
    fn confirms_the_exact_child_test_executed() {
        const FLAG: &str = "SELVEDGE_TEST_CONFIRM_CHILD";
        if child_mode(FLAG) {
            return;
        }
        assert_child_success(&run_child(
            "process::tests::confirms_the_exact_child_test_executed",
            FLAG,
        ));
    }

    #[test]
    fn rejects_missing_test_even_when_harness_exits_successfully() {
        let output = run_child("no_such_test_after_rename", "SELVEDGE_TEST_MISSING_CHILD");
        assert!(output.status.success());
        assert!(std::panic::catch_unwind(|| assert_child_success(&output)).is_err());
    }

    #[test]
    fn propagates_child_test_failure() {
        const FLAG: &str = "SELVEDGE_TEST_FAIL_CHILD";
        assert!(!child_mode(FLAG), "intentional child failure");
        let output = run_child("process::tests::propagates_child_test_failure", FLAG);
        assert!(!output.status.success());
        assert!(std::panic::catch_unwind(|| assert_child_success(&output)).is_err());
    }
}
