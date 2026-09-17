use std::fs;
use std::path::Path;
use std::process::Command;

use tempfile::TempDir;

/// Owns the repository and its isolated Git configuration for the whole test.
pub(crate) struct TestRepo {
    repository: TempDir,
    git_home: TempDir,
}

impl TestRepo {
    pub(crate) fn new() -> Self {
        let repo = Self {
            repository: TempDir::new().expect("temporary repository"),
            git_home: TempDir::new().expect("temporary Git home"),
        };
        fs::create_dir(repo.git_home.path().join(".config")).expect("Git config directory");
        fs::write(repo.git_home.path().join("gitconfig"), "").expect("empty Git config");
        repo.git(&["init"]);
        repo.git(&["config", "user.name", "Test User"]);
        repo.git(&["config", "user.email", "test@example.com"]);
        // Repository-local settings also isolate Git invoked by the code under test.
        repo.git(&["config", "core.hooksPath", "/dev/null"]);
        repo.git(&["config", "commit.gpgsign", "false"]);
        repo
    }

    pub(crate) fn workspace() -> Self {
        let repo = Self::new();
        repo.write("README.md", "# repo\n");
        repo.write("Cargo.toml", "[workspace]\nmembers = [\"crates/demo\"]\n");
        repo.git_add(&["Cargo.toml", "README.md"]);
        repo.git_commit("initial");
        repo
    }

    pub(crate) fn path(&self) -> &Path {
        self.repository.path()
    }

    pub(crate) fn write(&self, relative_path: &str, content: &str) {
        let path = self.path().join(relative_path);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("parent directory");
        }
        fs::write(path, content).expect("write test file");
    }

    pub(crate) fn read(&self, relative_path: &str) -> String {
        fs::read_to_string(self.path().join(relative_path)).expect("read test file")
    }

    pub(crate) fn git_add(&self, paths: &[&str]) {
        let mut args = vec!["add"];
        args.extend_from_slice(paths);
        self.git(&args);
    }

    pub(crate) fn git_commit(&self, message: &str) {
        self.git(&["commit", "-m", message]);
    }

    pub(crate) fn git_rm(&self, paths: &[&str]) {
        let mut args = vec!["rm"];
        args.extend_from_slice(paths);
        self.git(&args);
    }

    pub(crate) fn commit_tree(&self, message: &str) -> String {
        self.git(&["commit-tree", "HEAD^{tree}", "-m", message])
    }

    pub(crate) fn git_reset_hard(&self, commit: &str) {
        self.git(&["reset", "--hard", commit]);
    }

    fn git(&self, args: &[&str]) -> String {
        let mut command = Command::new("git");
        for (key, _) in std::env::vars_os() {
            if key.to_string_lossy().starts_with("GIT_") {
                command.env_remove(key);
            }
        }
        let output = command
            .current_dir(self.path())
            .env("HOME", self.git_home.path())
            .env("XDG_CONFIG_HOME", self.git_home.path().join(".config"))
            .env("GIT_CONFIG_GLOBAL", self.git_home.path().join("gitconfig"))
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .args(args)
            .output()
            .expect("run git");
        assert!(
            output.status.success(),
            "git {args:?} failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8_lossy(&output.stdout).trim().to_owned()
    }
}
