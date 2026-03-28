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
    set_script_executable(&script_target);

    let output = run_script(&repo_root, "feature/demo");

    assert!(
        output.status.success(),
        "script failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let worktree_path = repo_root
        .join(".worktrees")
        .join(encoded_branch_name("feature/demo"));

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
        stdout.contains(&encoded_branch_name("feature/demo")),
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
    set_script_executable(&script_target);

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

#[test]
fn script_requires_repo_local_gitignore_entry_for_worktrees() {
    let tempdir = TempDir::new().expect("tempdir");
    let repo_root = tempdir.path().join("repo");
    let script_source = workspace_root().join("scripts/create-worktree.sh");
    let script_target = repo_root.join("scripts/create-worktree.sh");

    init_git_repo(&repo_root);
    fs::write(repo_root.join(".gitignore"), "").expect("clear gitignore");
    fs::write(repo_root.join(".git/info/exclude"), ".worktrees/\n").expect("write info exclude");
    fs::create_dir_all(repo_root.join("scripts")).expect("create scripts directory");
    fs::copy(&script_source, &script_target).expect("copy script");
    set_script_executable(&script_target);

    let output = run_script(&repo_root, "feature/demo");

    assert!(
        !output.status.success(),
        "script should fail when only non-repo ignore rules match"
    );

    let stderr = String::from_utf8(output.stderr).expect("stderr utf8");
    assert!(
        stderr.contains("must be ignored by the repository .gitignore"),
        "expected repo-local ignore guidance, got {stderr:?}"
    );
}

#[test]
fn script_bases_new_worktree_on_main_even_when_current_branch_is_not_main() {
    let tempdir = TempDir::new().expect("tempdir");
    let repo_root = tempdir.path().join("repo");
    let script_source = workspace_root().join("scripts/create-worktree.sh");
    let script_target = repo_root.join("scripts/create-worktree.sh");

    init_git_repo(&repo_root);
    fs::create_dir_all(repo_root.join("scripts")).expect("create scripts directory");
    fs::copy(&script_source, &script_target).expect("copy script");
    set_script_executable(&script_target);

    run_git(&repo_root, ["checkout", "-b", "feature/source"]);
    fs::write(repo_root.join("feature.txt"), "from feature branch\n").expect("write feature file");
    run_git(&repo_root, ["add", "feature.txt"]);
    run_git(&repo_root, ["commit", "-m", "Feature commit"]);

    let output = run_script(&repo_root, "feature/isolated");

    assert!(
        output.status.success(),
        "script failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let isolated_worktree_path = repo_root
        .join(".worktrees")
        .join(encoded_branch_name("feature/isolated"));
    assert!(
        !isolated_worktree_path.join("feature.txt").exists(),
        "new worktree should not inherit commits from the current non-main branch"
    );

    let head_output = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .current_dir(&isolated_worktree_path)
        .output()
        .expect("read isolated worktree head");
    let main_output = Command::new("git")
        .args(["rev-parse", "main"])
        .current_dir(&repo_root)
        .output()
        .expect("read main head");

    assert_eq!(
        String::from_utf8(head_output.stdout).expect("isolated head utf8"),
        String::from_utf8(main_output.stdout).expect("main head utf8"),
        "new worktree should start from main"
    );
}

#[test]
fn script_keeps_distinct_worktree_paths_for_similar_branch_names() {
    let tempdir = TempDir::new().expect("tempdir");
    let repo_root = tempdir.path().join("repo");
    let script_source = workspace_root().join("scripts/create-worktree.sh");
    let script_target = repo_root.join("scripts/create-worktree.sh");

    init_git_repo(&repo_root);
    fs::create_dir_all(repo_root.join("scripts")).expect("create scripts directory");
    fs::copy(&script_source, &script_target).expect("copy script");
    set_script_executable(&script_target);

    let slash_output = run_script(&repo_root, "feature/a");
    assert!(
        slash_output.status.success(),
        "script failed: {}",
        String::from_utf8_lossy(&slash_output.stderr)
    );

    let dash_output = run_script(&repo_root, "feature-a");
    assert!(
        dash_output.status.success(),
        "script failed: {}",
        String::from_utf8_lossy(&dash_output.stderr)
    );

    assert!(
        repo_root
            .join(".worktrees")
            .join(encoded_branch_name("feature/a"))
            .is_dir()
    );
    assert!(
        repo_root
            .join(".worktrees")
            .join(encoded_branch_name("feature-a"))
            .is_dir()
    );
}

#[test]
fn script_supports_long_branch_names_without_leaving_partial_branch_state() {
    let tempdir = TempDir::new().expect("tempdir");
    let repo_root = tempdir.path().join("repo");
    let script_source = workspace_root().join("scripts/create-worktree.sh");
    let script_target = repo_root.join("scripts/create-worktree.sh");
    let long_branch_name = format!("feature/{}", "a".repeat(180));

    init_git_repo(&repo_root);
    fs::create_dir_all(repo_root.join("scripts")).expect("create scripts directory");
    fs::copy(&script_source, &script_target).expect("copy script");
    set_script_executable(&script_target);

    let output = run_script(&repo_root, &long_branch_name);
    assert!(
        output.status.success(),
        "script failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    assert!(
        repo_root
            .join(".worktrees")
            .join(encoded_branch_name(&long_branch_name))
            .is_dir()
    );

    let branch_output = Command::new("git")
        .args(["branch", "--list", &long_branch_name])
        .current_dir(&repo_root)
        .output()
        .expect("list branches");
    let branches = String::from_utf8(branch_output.stdout).expect("branches utf8");
    assert!(
        branches.contains(&long_branch_name),
        "expected branch to exist after successful creation"
    );
}

#[test]
fn script_uses_shared_root_when_run_inside_an_existing_worktree() {
    let tempdir = TempDir::new().expect("tempdir");
    let repo_root = tempdir.path().join("repo");
    let script_source = workspace_root().join("scripts/create-worktree.sh");
    let root_script_target = repo_root.join("scripts/create-worktree.sh");

    init_git_repo(&repo_root);
    fs::create_dir_all(repo_root.join("scripts")).expect("create scripts directory");
    fs::copy(&script_source, &root_script_target).expect("copy root script");
    set_script_executable(&root_script_target);

    let first_worktree_name = encoded_branch_name("feature/one");
    run_git(
        &repo_root,
        [
            "worktree",
            "add",
            &format!(".worktrees/{first_worktree_name}"),
            "-b",
            "feature/one",
            "main",
        ],
    );

    let nested_worktree = repo_root.join(".worktrees").join(&first_worktree_name);
    let nested_script_target = nested_worktree.join("scripts/create-worktree.sh");
    fs::create_dir_all(nested_worktree.join("scripts")).expect("create nested scripts directory");
    fs::copy(&script_source, &nested_script_target).expect("copy nested script");
    set_script_executable(&nested_script_target);

    let output = run_script(&nested_worktree, "feature/two");
    assert!(
        output.status.success(),
        "script failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    assert!(
        repo_root
            .join(".worktrees")
            .join(encoded_branch_name("feature/two"))
            .is_dir()
    );
    assert!(
        !nested_worktree
            .join(".worktrees")
            .join(encoded_branch_name("feature/two"))
            .exists()
    );
}

fn run_script(repo_root: &Path, branch_name: &str) -> std::process::Output {
    Command::new("sh")
        .args([
            "-c",
            &format!("./scripts/create-worktree.sh '{branch_name}'"),
        ])
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

fn encoded_branch_name(branch_name: &str) -> String {
    let output = Command::new("git")
        .args(["hash-object", "--stdin"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("spawn git hash-object");
    let mut child = output;
    {
        use std::io::Write;

        let stdin = child.stdin.as_mut().expect("child stdin");
        stdin
            .write_all(branch_name.as_bytes())
            .expect("write branch name");
    }
    let output = child.wait_with_output().expect("wait for git hash-object");
    assert!(
        output.status.success(),
        "git hash-object failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    format!(
        "branch-{}",
        String::from_utf8(output.stdout)
            .expect("hash stdout utf8")
            .trim()
    )
}

#[cfg(unix)]
fn set_script_executable(script_path: &Path) {
    use std::os::unix::fs::PermissionsExt;

    let mut permissions = fs::metadata(script_path)
        .expect("read script metadata")
        .permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(script_path, permissions).expect("make script executable");
}
