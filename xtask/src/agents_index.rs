use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsStr;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

const BEGIN_MARKER: &str = "<!-- BEGIN AGENTS_MD_PROJECT_INDEX -->";
const END_MARKER: &str = "<!-- END AGENTS_MD_PROJECT_INDEX -->";
const PROJECT_INDEX_HEADING: &str = "## Project Index";

/// @constraint tool.project_index.warning The project index reports tracked directories whose direct filesystem entry count is high enough to slow agent context lookup.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirectoryWarning {
    /// @constraint tool.project_index.warning.path A directory warning names the indexed path whose current filesystem contents exceed the threshold.
    pub path: String,
    /// @constraint tool.project_index.warning.entry_count A directory warning exposes the observed direct entry count for that path.
    pub entry_count: usize,
}

/// @behavior tool.project_index.status The project index check reports whether the AGENTS.md project index matches the tracked checkout.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CheckStatus {
    Fresh { warnings: Vec<DirectoryWarning> },
    Stale { warnings: Vec<DirectoryWarning> },
}

/// @behavior tool.project_index.update The project index update command rewrites the generated AGENTS.md project index from Git-tracked files.
pub fn update_agents_md(
    root: &Path,
    warning_threshold: usize,
) -> Result<Vec<DirectoryWarning>, String> {
    let prepared = prepare(root, warning_threshold)?;
    let existing = match fs::read_to_string(&prepared.agents_md_path) {
        Ok(content) => content,
        Err(error) if error.kind() == io::ErrorKind::NotFound => String::new(),
        // @behavior tool.project_index.update.read_error The project index update command reports AGENTS.md read errors with the affected path.
        Err(error) => {
            return Err(format!(
                "failed to read {}: {error}",
                prepared.agents_md_path.display()
            ));
        }
    };
    let updated = upsert_index_block(&existing, &prepared.rendered_block, prepared.line_ending)?;
    // @behavior tool.project_index.update.write The project index update command persists the generated block back into AGENTS.md.
    fs::write(&prepared.agents_md_path, updated).map_err(|error| {
        format!(
            "failed to write {}: {error}",
            prepared.agents_md_path.display()
        )
    })?;
    Ok(prepared.warnings)
}

/// @behavior tool.project_index.check The project index check command compares AGENTS.md with the tracked-file index that would be generated now.
pub fn check_agents_md(root: &Path, warning_threshold: usize) -> Result<CheckStatus, String> {
    let prepared = prepare(root, warning_threshold)?;
    let existing = match fs::read_to_string(&prepared.agents_md_path) {
        Ok(content) => content,
        // @behavior tool.project_index.check.missing_agents The project index check reports a stale index when AGENTS.md is absent.
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(CheckStatus::Stale {
                warnings: prepared.warnings,
            });
        }
        // @behavior tool.project_index.check.read_error The project index check reports AGENTS.md read errors with the affected path.
        Err(error) => {
            return Err(format!(
                "failed to read {}: {error}",
                prepared.agents_md_path.display()
            ));
        }
    };
    let updated = upsert_index_block(&existing, &prepared.rendered_block, prepared.line_ending)?;
    if existing == updated {
        Ok(CheckStatus::Fresh {
            warnings: prepared.warnings,
        })
    } else {
        Ok(CheckStatus::Stale {
            warnings: prepared.warnings,
        })
    }
}

struct PreparedIndex {
    agents_md_path: PathBuf,
    rendered_block: String,
    line_ending: &'static str,
    warnings: Vec<DirectoryWarning>,
}

fn prepare(root: &Path, warning_threshold: usize) -> Result<PreparedIndex, String> {
    let tracked_files = git_tracked_files(root)?;
    let line_ending = detect_line_ending(&root.join("AGENTS.md"));
    let rendered_block = render_index_block(&tracked_files, line_ending);
    let warnings = collect_directory_warnings(root, &tracked_files, warning_threshold)?;
    Ok(PreparedIndex {
        agents_md_path: root.join("AGENTS.md"),
        rendered_block,
        line_ending,
        warnings,
    })
}

/// @behavior tool.project_index.git_files The project index reads the tracked-file set from `git ls-files -z`.
fn git_tracked_files(root: &Path) -> Result<Vec<PathBuf>, String> {
    let output = isolated_git_command()
        .current_dir(root)
        .args(["ls-files", "-z"])
        .output()
        .map_err(|error| format!("failed to run git ls-files: {error}"))?;
    if !output.status.success() {
        // @behavior tool.project_index.git_files.failure The project index reports Git stderr when tracked-file discovery fails.
        return Err(format!(
            "git ls-files failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    let mut paths = output
        .stdout
        .split(|byte| *byte == b'\0')
        .filter(|entry| !entry.is_empty())
        .map(|entry| PathBuf::from(String::from_utf8_lossy(entry).into_owned()))
        .collect::<Vec<_>>();
    paths.sort();
    Ok(paths)
}

/// @constraint tool.project_index.git_env Git-backed project index reads ignore inherited Git environment variables.
fn isolated_git_command() -> Command {
    let mut command = Command::new("git");

    for (key, _) in std::env::vars_os() {
        if key.to_string_lossy().starts_with("GIT_") {
            command.env_remove(&key);
        }
    }

    command
}

/// @behavior tool.project_index.render The project index renders tracked files into the generated AGENTS.md project index block.
fn render_index_block(tracked_files: &[PathBuf], line_ending: &str) -> String {
    let directory_map = build_directory_map(tracked_files);
    let mut lines = vec![
        BEGIN_MARKER.to_string(),
        "```text".to_string(),
        "[Project Index]|root:.".to_string(),
        "|source:git-tracked-files-only".to_string(),
        "|excluded:{git-ignored,git-untracked}".to_string(),
    ];

    for (directory, entries) in directory_map {
        lines.push(format!("|{directory}:{{{}}}", entries.join(",")));
    }

    lines.push("```".to_string());
    lines.push(END_MARKER.to_string());
    lines.join(line_ending)
}

/// @behavior tool.project_index.directory_map The project index groups tracked files into deterministic directory rows.
fn build_directory_map(tracked_files: &[PathBuf]) -> BTreeMap<String, Vec<String>> {
    let mut directories: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    directories.entry(".".to_string()).or_default();

    for path in tracked_files {
        let parts = path.iter().map(os_str_to_string).collect::<Vec<_>>();
        if parts.is_empty() {
            continue;
        }

        let mut parent = ".".to_string();
        for (index, part) in parts.iter().take(parts.len().saturating_sub(1)).enumerate() {
            directories
                .entry(parent.clone())
                .or_default()
                .insert(format!("{part}/"));
            let current = parts[..=index].join("/");
            directories.entry(current.clone()).or_default();
            parent = current;
        }

        directories
            .entry(parent)
            .or_default()
            // @constraint tool.project_index.directory_map.nonempty_path Tracked file rows must contain at least one path segment before they enter the project index.
            .insert(parts.last().cloned().expect("path parts are non-empty"));
    }

    directories
        .into_iter()
        .map(|(directory, entries)| {
            let mut entries = entries.into_iter().collect::<Vec<_>>();
            entries.sort_by(
                |left, right| match (left.ends_with('/'), right.ends_with('/')) {
                    (true, true) | (false, false) => left.cmp(right),
                    (true, false) => std::cmp::Ordering::Less,
                    (false, true) => std::cmp::Ordering::Greater,
                },
            );
            (directory, entries)
        })
        .collect()
}

/// @behavior tool.project_index.warning.collect The project index warning collector reports indexed directories with many direct filesystem entries.
fn collect_directory_warnings(
    root: &Path,
    tracked_files: &[PathBuf],
    warning_threshold: usize,
) -> Result<Vec<DirectoryWarning>, String> {
    let directory_map = build_directory_map(tracked_files);
    let mut warnings = Vec::new();

    for directory in directory_map.keys() {
        let directory_path = if directory == "." {
            root.to_path_buf()
        } else {
            root.join(directory)
        };
        let entry_count = match fs::read_dir(&directory_path) {
            Ok(entries) => entries.count(),
            // @behavior tool.project_index.warning.missing_dir Missing indexed directories are skipped during warning collection.
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            // @behavior tool.project_index.warning.read_error The project index reports unreadable indexed directories with their filesystem path.
            Err(error) => {
                return Err(format!(
                    "failed to read {}: {error}",
                    directory_path.display()
                ));
            }
        };
        if entry_count > warning_threshold {
            warnings.push(DirectoryWarning {
                path: directory.clone(),
                entry_count,
            });
        }
    }

    Ok(warnings)
}

/// @behavior tool.project_index.upsert The project index updater replaces the generated block or creates the project-index section in AGENTS.md.
fn upsert_index_block(existing: &str, block: &str, line_ending: &str) -> Result<String, String> {
    let begin_matches = existing.matches(BEGIN_MARKER).count();
    let end_matches = existing.matches(END_MARKER).count();
    if begin_matches > 1 || end_matches > 1 {
        // @constraint tool.project_index.upsert.marker_count AGENTS.md must contain at most one generated project-index block.
        return Err("AGENTS.md contains duplicate project index markers".to_string());
    }
    if begin_matches != end_matches {
        // @constraint tool.project_index.upsert.marker_balance AGENTS.md generated project-index markers must be balanced.
        return Err("AGENTS.md project index markers are unbalanced".to_string());
    }

    if begin_matches == 0 {
        if let Some(section_start) = find_project_index_section_start(existing) {
            let section_end = find_section_end(existing, section_start);
            let mut updated = String::new();
            updated.push_str(&existing[..section_start]);
            updated.push_str(PROJECT_INDEX_HEADING);
            updated.push_str(line_ending);
            updated.push_str(line_ending);
            updated.push_str(block);
            if section_end < existing.len() && !starts_with_newline(&existing[section_end..]) {
                updated.push_str(line_ending);
            }
            updated.push_str(&existing[section_end..]);
            return Ok(updated);
        }

        let mut appended = existing.trim_end().to_string();
        if appended.is_empty() {
            appended.push_str(PROJECT_INDEX_HEADING);
            appended.push_str(line_ending);
            appended.push_str(line_ending);
        } else {
            appended.push_str(line_ending);
            appended.push_str(line_ending);
            appended.push_str(PROJECT_INDEX_HEADING);
            appended.push_str(line_ending);
            appended.push_str(line_ending);
        }
        appended.push_str(block);
        appended.push_str(line_ending);
        return Ok(appended);
    }

    let start = existing
        .find(BEGIN_MARKER)
        // @constraint tool.project_index.upsert.marker_lookup_begin Begin-marker lookup must succeed after marker counts pass.
        .expect("marker count already checked");
    let end = existing
        .find(END_MARKER)
        // @constraint tool.project_index.upsert.marker_lookup_end End-marker lookup must succeed after marker counts pass.
        .expect("marker count already checked")
        + END_MARKER.len();
    let mut updated = String::new();
    updated.push_str(&existing[..start]);
    updated.push_str(block);
    updated.push_str(&existing[end..]);
    Ok(updated)
}

fn os_str_to_string(value: &OsStr) -> String {
    value.to_string_lossy().into_owned()
}

fn detect_line_ending(path: &Path) -> &'static str {
    let Ok(content) = fs::read_to_string(path) else {
        return "\n";
    };
    if content.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    }
}

fn starts_with_newline(content: &str) -> bool {
    content.starts_with('\n') || content.starts_with("\r\n")
}

fn find_project_index_section_start(content: &str) -> Option<usize> {
    content
        .match_indices(PROJECT_INDEX_HEADING)
        .find(|(index, _)| {
            let prefix_ok = *index == 0 || content[..*index].ends_with('\n');
            let suffix_index = index + PROJECT_INDEX_HEADING.len();
            let suffix_ok = suffix_index == content.len()
                || content[suffix_index..].starts_with('\n')
                || content[suffix_index..].starts_with("\r\n");
            prefix_ok && suffix_ok
        })
        .map(|(index, _)| index)
}

fn find_section_end(content: &str, section_start: usize) -> usize {
    let search_start = section_start + PROJECT_INDEX_HEADING.len();
    let remainder = &content[search_start..];
    if let Some(next_heading_offset) = remainder.find("\n## ") {
        search_start + next_heading_offset + 1
    } else {
        content.len()
    }
}

#[cfg(test)]
mod tests {
    use super::{CheckStatus, check_agents_md, update_agents_md};
    use std::fs;
    use std::path::Path;
    use std::process::Command;
    use tempfile::TempDir;

    #[test]
    fn update_creates_index_from_tracked_files_and_skips_git_ignored_files() {
        let repo = TestRepo::new();
        repo.write("README.md", "# repo\n");
        repo.write(".gitignore", "ignored.txt\n");
        repo.write("src/lib.rs", "pub fn lib() {}\n");
        repo.write("ignored.txt", "skip me\n");
        repo.git_add(&["README.md", ".gitignore", "src/lib.rs"]);

        let warnings = update_agents_md(repo.path(), 200).expect("update should succeed");

        // @verifies tool.project_index.update
        assert!(warnings.is_empty(), "unexpected warnings: {warnings:?}");

        let agents_md = repo.read("AGENTS.md");
        // @verifies tool.project_index.render
        assert!(agents_md.contains("|.:{src/,.gitignore,README.md}"));
        assert!(agents_md.contains("|src:{lib.rs}"));
        assert!(agents_md.contains(".gitignore"));
        assert!(!agents_md.contains("ignored.txt"));
    }

    #[test]
    fn check_reports_stale_when_tracked_files_change() {
        let repo = TestRepo::new();
        repo.write("README.md", "# repo\n");
        repo.write("src/lib.rs", "pub fn lib() {}\n");
        repo.git_add(&["README.md", "src/lib.rs"]);
        update_agents_md(repo.path(), 200).expect("initial update should succeed");

        repo.write("src/main.rs", "fn main() {}\n");
        repo.git_add(&["src/main.rs"]);

        let status = check_agents_md(repo.path(), 200).expect("check should run");

        // @verifies tool.project_index.status
        assert!(matches!(status, CheckStatus::Stale { .. }));
    }

    #[test]
    fn update_warns_when_indexed_directory_has_many_disk_entries_even_if_untracked() {
        let repo = TestRepo::new();
        repo.write("README.md", "# repo\n");
        repo.write("bulk/tracked.txt", "tracked\n");
        for index in 0..201 {
            repo.write(&format!("bulk/untracked-{index}.txt"), "noise\n");
        }
        repo.git_add(&["README.md", "bulk/tracked.txt"]);

        let warnings = update_agents_md(repo.path(), 200).expect("update should succeed");

        // @verifies tool.project_index.warning
        assert_eq!(warnings.len(), 1, "warnings: {warnings:?}");
        assert_eq!(warnings[0].path, "bulk");
        assert_eq!(warnings[0].entry_count, 202);
    }

    struct TestRepo {
        tempdir: TempDir,
    }

    impl TestRepo {
        fn new() -> Self {
            let tempdir = TempDir::new().expect("tempdir should exist");
            run_git(tempdir.path(), &["init"]);
            run_git(tempdir.path(), &["config", "user.name", "Test User"]);
            run_git(
                tempdir.path(),
                &["config", "user.email", "test@example.com"],
            );
            Self { tempdir }
        }

        fn path(&self) -> &Path {
            self.tempdir.path()
        }

        fn write(&self, relative_path: &str, content: &str) {
            let full_path = self.path().join(relative_path);
            if let Some(parent) = full_path.parent() {
                fs::create_dir_all(parent).expect("parent directory should exist");
            }
            fs::write(full_path, content).expect("file should be written");
        }

        fn read(&self, relative_path: &str) -> String {
            fs::read_to_string(self.path().join(relative_path)).expect("file should exist")
        }

        fn git_add(&self, paths: &[&str]) {
            let mut command = isolated_git_command();
            command.current_dir(self.path());
            command.arg("add");
            for path in paths {
                command.arg(path);
            }
            let output = command.output().expect("git add should run");
            // @verifies tool.project_index.git_files
            assert!(
                output.status.success(),
                "git add failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }

    fn run_git(root: &Path, args: &[&str]) {
        let output = isolated_git_command()
            .current_dir(root)
            .args(args)
            .output()
            .expect("git command should run");
        // @verifies tool.project_index.git_env
        assert!(
            output.status.success(),
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&output.stderr)
        );
    }

    fn isolated_git_command() -> Command {
        let mut command = Command::new("git");

        for (key, _) in std::env::vars_os() {
            if key.to_string_lossy().starts_with("GIT_") {
                command.env_remove(&key);
            }
        }

        let isolated_home = std::env::temp_dir().join(format!(
            "xtask-git-home-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock should be valid")
                .as_nanos()
        ));
        let isolated_git_config = isolated_home.join("gitconfig");

        fs::create_dir_all(isolated_home.join(".config")).expect("isolated git home should exist");
        fs::write(&isolated_git_config, "").expect("isolated git config should exist");
        command.env("HOME", &isolated_home);
        command.env("XDG_CONFIG_HOME", isolated_home.join(".config"));
        command.env("GIT_CONFIG_GLOBAL", &isolated_git_config);

        command
    }
}
