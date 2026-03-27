use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use tempfile::TempDir;

#[test]
fn script_creates_branch_and_worktree_in_hidden_directory() {
    let tempdir = TempDir::new().expect("tempdir");
    let repo_root = tempdir.path().join("repo");
    let script_source = workspace_root().join("scripts/create-worktree.sh");
    let script_target = repo_root.join("scripts/create-worktree.sh");

    init_git_repo(&repo_root);
    fs::create_dir_all(repo_root.join("scripts")).expect("create scripts directory");
    fs::copy(&script_source, &script_target).expect("copy script");

    let output = run_script(&repo_root, "feature/demo");

    assert!(
        output.status.success(),
        "script failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let worktree_path = repo_root.join(".worktrees/feature-demo");

    assert!(worktree_path.is_dir(), "worktree directory should exist");

    let branch_output = Command::new("git")
        .args(["branch", "--list", "feature/demo"])
        .current_dir(&repo_root)
        .output()
        .expect("list branches");
    let branches = String::from_utf8(branch_output.stdout).expect("branches utf8");

    assert!(
        branches.contains("feature/demo"),
        "expected feature/demo branch, got {branches:?}"
    );

    let stdout = String::from_utf8(output.stdout).expect("stdout utf8");
    assert!(
        stdout.contains(".worktrees/feature-demo"),
        "expected created path in stdout, got {stdout:?}"
    );
}

#[test]
fn script_fails_when_worktree_directory_is_not_ignored() {
    let tempdir = TempDir::new().expect("tempdir");
    let repo_root = tempdir.path().join("repo");
    let script_source = workspace_root().join("scripts/create-worktree.sh");
    let script_target = repo_root.join("scripts/create-worktree.sh");

    init_git_repo(&repo_root);
    fs::write(repo_root.join(".gitignore"), "").expect("write empty gitignore");
    fs::create_dir_all(repo_root.join("scripts")).expect("create scripts directory");
    fs::copy(&script_source, &script_target).expect("copy script");

    let output = run_script(&repo_root, "feature/demo");

    assert!(
        !output.status.success(),
        "script should fail when .worktrees is not ignored"
    );

    let stderr = String::from_utf8(output.stderr).expect("stderr utf8");
    assert!(
        stderr.contains(".worktrees/ is not ignored"),
        "expected ignore guidance, got {stderr:?}"
    );
}

fn run_script(repo_root: &Path, branch_name: &str) -> std::process::Output {
    Command::new("bash")
        .arg("scripts/create-worktree.sh")
        .arg(branch_name)
        .current_dir(repo_root)
        .output()
        .expect("run create-worktree script")
}

fn init_git_repo(repo_root: &Path) {
    fs::create_dir_all(repo_root).expect("create repo root");
    run_git(repo_root, ["init", "-b", "main"]);
    run_git(repo_root, ["config", "user.name", "Selvedge Test"]);
    run_git(repo_root, ["config", "user.email", "selvedge@example.com"]);
    fs::write(repo_root.join(".gitignore"), ".worktrees/\n").expect("write gitignore");
    fs::write(repo_root.join("README.md"), "# Temp Repo\n").expect("write readme");
    run_git(repo_root, ["add", "."]);
    run_git(repo_root, ["commit", "-m", "Initial commit"]);
}

fn run_git<const N: usize>(repo_root: &Path, args: [&str; N]) {
    let output = Command::new("git")
        .args(args)
        .current_dir(repo_root)
        .output()
        .expect("run git command");

    assert!(
        output.status.success(),
        "git command {:?} failed: {}",
        args,
        String::from_utf8_lossy(&output.stderr)
    );
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
