//! @behavior tool.readme The README gate validates package README freshness metadata and Mermaid diagrams.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const METADATA_BEGIN: &str = "<!-- selvedge-package-readme";
const METADATA_END: &str = "-->";

/// @behavior tool.readme.status The README freshness status reports whether every package README metadata commit still covers package source changes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReadmeFreshnessStatus {
    Fresh,
    Stale { packages: Vec<StalePackage> },
}

/// @behavior tool.readme.stale_package Stale package reports name package path, README path, metadata commit, and changed package files.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StalePackage {
    /// @behavior tool.readme.stale_package.package Stale package diagnostics include the Cargo package name.
    pub package: String,
    /// @behavior tool.readme.stale_package.package_path Stale package diagnostics include the package directory path.
    pub package_path: String,
    /// @behavior tool.readme.stale_package.readme_path Stale package diagnostics include the package README path.
    pub readme_path: String,
    /// @behavior tool.readme.stale_package.freshness_commit Stale package diagnostics include the README metadata freshness commit.
    pub freshness_commit: String,
    /// @behavior tool.readme.stale_package.changed_files Stale package diagnostics include every changed tracked package file except the package README.
    pub changed_files: Vec<String>,
}

/// @behavior tool.readme.freshness The package README freshness check fails packages whose non-README tracked files changed after the README metadata commit.
pub fn check_package_readmes_freshness(root: &Path) -> Result<ReadmeFreshnessStatus, String> {
    let packages = workspace_packages(root)?;
    let mut stale_packages = Vec::new();

    for package in packages {
        let readme_path = package.path.join("README.md");
        let readme_content = read_file(root, &readme_path)?;
        let metadata = parse_metadata(&package, &readme_content)?;
        ensure_commit_exists(root, &metadata.freshness_commit)?;
        let changed_files =
            changed_package_files_since(root, &metadata.freshness_commit, &package)?;
        if !changed_files.is_empty() {
            stale_packages.push(StalePackage {
                package: package.name,
                package_path: path_to_string(&package.path),
                readme_path: path_to_string(&readme_path),
                freshness_commit: metadata.freshness_commit,
                changed_files,
            });
        }
    }

    if stale_packages.is_empty() {
        Ok(ReadmeFreshnessStatus::Fresh)
    } else {
        Ok(ReadmeFreshnessStatus::Stale {
            packages: stale_packages,
        })
    }
}

/// @behavior tool.readme.mermaid The Mermaid check renders every package README Mermaid fence and reports every compile failure.
pub fn check_package_readme_mermaid(root: &Path) -> Result<(), String> {
    let packages = workspace_packages(root)?;
    let mut diagnostics = Vec::new();

    for package in packages {
        let readme_path = package.path.join("README.md");
        let readme_content = read_file(root, &readme_path)?;
        let diagrams = extract_mermaid_diagrams(&readme_content);
        if diagrams.is_empty() {
            diagnostics.push(format!(
                "{}:1: missing-mermaid: package README must contain at least one Mermaid diagram",
                path_to_string(&readme_path)
            ));
            continue;
        }
        for diagram in diagrams {
            // @behavior tool.readme.mermaid.invalid Mermaid renderer failures are reported with the README path and fenced block line.
            if let Err(error) = mermaid_rs_renderer::render(&diagram.source) {
                diagnostics.push(format!(
                    "{}:{}: invalid-mermaid: {}",
                    path_to_string(&readme_path),
                    diagram.line,
                    error
                ));
            }
        }
    }

    if diagnostics.is_empty() {
        Ok(())
    } else {
        // @behavior tool.readme.mermaid.diagnostics The Mermaid check returns all package README compile diagnostics together.
        Err(diagnostics.join("\n"))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct WorkspacePackage {
    name: String,
    path: PathBuf,
    diff_pathspecs: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ReadmeMetadata {
    freshness_commit: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MermaidDiagram {
    line: usize,
    source: String,
}

/// @behavior tool.readme.packages Package discovery reads tracked Cargo workspace package manifests from Cargo metadata.
fn workspace_packages(root: &Path) -> Result<Vec<WorkspacePackage>, String> {
    let metadata = cargo_workspace_metadata(root)?;
    let workspace_members = metadata
        .get("workspace_members")
        .and_then(serde_json::Value::as_array)
        // @behavior tool.readme.packages.workspace_members Package discovery reports cargo metadata output missing the workspace member list before README checks run.
        .ok_or_else(|| "cargo metadata output is missing workspace_members".to_owned())?
        .iter()
        .map(|member| {
            member.as_str().map(str::to_owned).ok_or_else(|| {
                "cargo metadata workspace_members entries must be strings".to_owned()
            })
        })
        .collect::<Result<BTreeSet<_>, _>>()?;
    let metadata_packages = metadata
        .get("packages")
        .and_then(serde_json::Value::as_array)
        // @behavior tool.readme.packages.metadata_packages Package discovery reports cargo metadata output missing the package list before README checks run.
        .ok_or_else(|| "cargo metadata output is missing packages".to_owned())?;
    let mut packages = Vec::new();
    for package_metadata in metadata_packages {
        let id = metadata_string(package_metadata, "id", "package id")?;
        if !workspace_members.contains(&id) {
            continue;
        }
        let manifest_path = metadata_path_to_relative(
            root,
            &metadata_string(package_metadata, "manifest_path", "manifest path")?,
        )?;
        if !git_path_tracked(root, &manifest_path)? {
            continue;
        }
        let name = metadata_string(package_metadata, "name", "package name")?;
        let path = manifest_path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
            .map_or_else(|| PathBuf::from("."), Path::to_path_buf);
        let diff_pathspecs = package_diff_pathspecs_from_metadata(root, &path, package_metadata)?;
        packages.push(WorkspacePackage {
            name,
            path,
            diff_pathspecs,
        });
    }
    packages.sort_by(|left, right| left.path.cmp(&right.path));
    Ok(packages)
}

/// @behavior tool.readme.packages.excludes Package discovery follows Cargo workspace exclude entries when selecting README gate packages.
/// @behavior tool.readme.packages.metadata Package discovery runs cargo metadata without dependency resolution to match Cargo workspace membership semantics.
fn cargo_workspace_metadata(root: &Path) -> Result<serde_json::Value, String> {
    let output = Command::new("cargo")
        .current_dir(root)
        .args(["metadata", "--format-version", "1", "--no-deps"])
        .output()
        // @behavior tool.readme.packages.metadata_spawn_failure Package discovery reports process errors when cargo metadata cannot be started.
        .map_err(|error| format!("failed to run cargo metadata: {error}"))?;
    if !output.status.success() {
        // @behavior tool.readme.packages.metadata_failure Package discovery reports cargo metadata stderr when workspace discovery fails.
        return Err(format!(
            "cargo metadata failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    serde_json::from_slice(&output.stdout)
        // @behavior tool.readme.packages.metadata_json Package discovery reports invalid cargo metadata JSON before README checks run.
        .map_err(|error| format!("failed to parse cargo metadata JSON: {error}"))
}

fn metadata_string(
    object: &serde_json::Value,
    field: &str,
    description: &str,
) -> Result<String, String> {
    object
        .get(field)
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| format!("cargo metadata package is missing {description}"))
}

/// @behavior tool.readme.packages.metadata_path Package discovery reports cargo metadata paths that cannot be resolved relative to the workspace root.
fn metadata_path_to_relative(root: &Path, metadata_path: &str) -> Result<PathBuf, String> {
    let root = fs::canonicalize(root)
        .map_err(|error| format!("failed to canonicalize {}: {error}", root.display()))?;
    let path = fs::canonicalize(metadata_path)
        .map_err(|error| format!("failed to canonicalize {metadata_path}: {error}"))?;
    path.strip_prefix(&root)
        .map(Path::to_path_buf)
        .map_err(|_| {
            format!(
                "{metadata_path} is outside the workspace root {}",
                root.display()
            )
        })
}

fn git_path_tracked(root: &Path, relative_path: &Path) -> Result<bool, String> {
    let path = path_to_string(relative_path);
    let output = isolated_git_command()
        .current_dir(root)
        .args(["ls-files", "--error-unmatch", "--", &path])
        .output()
        // @behavior tool.readme.packages.git_spawn_failure Package discovery reports process errors when Git cannot be started.
        .map_err(|error| format!("failed to run git ls-files for package manifests: {error}"))?;
    if output.status.success() {
        return Ok(true);
    }
    if output.status.code() == Some(1) {
        return Ok(false);
    }
    // @behavior tool.readme.packages.git_failure Package discovery reports Git stderr when tracked manifest discovery fails.
    Err(format!(
        "git ls-files failed for {}: {}",
        path,
        String::from_utf8_lossy(&output.stderr).trim()
    ))
}

/// @behavior tool.readme.changed_files.root_scope The root package freshness diff checks the root package manifest, default Cargo target paths, and metadata target input paths.
fn package_diff_pathspecs_from_metadata(
    root: &Path,
    package_path: &Path,
    package_metadata: &serde_json::Value,
) -> Result<Vec<String>, String> {
    if package_path != Path::new(".") {
        return Ok(vec![path_to_string(package_path)]);
    }

    let mut pathspecs = BTreeSet::from([
        "Cargo.toml".to_owned(),
        "benches".to_owned(),
        "build.rs".to_owned(),
        "examples".to_owned(),
        "src".to_owned(),
        "tests".to_owned(),
    ]);
    let targets = package_metadata
        .get("targets")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "cargo metadata package is missing target list".to_owned())?;
    for target in targets {
        let src_path =
            metadata_path_to_relative(root, &metadata_string(target, "src_path", "target path")?)?;
        pathspecs.insert(root_target_pathspec(&src_path));
    }
    Ok(pathspecs.into_iter().collect())
}

fn root_target_pathspec(src_path: &Path) -> String {
    match src_path.iter().next().map(|part| part.to_string_lossy()) {
        Some(first) if matches!(first.as_ref(), "src" | "tests" | "examples" | "benches") => {
            first.into_owned()
        }
        Some(_) => src_path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
            .map_or_else(|| path_to_string(src_path), path_to_string),
        None => path_to_string(src_path),
    }
}

/// @behavior tool.readme.metadata README metadata parsing reads the package name and freshness commit from the selvedge metadata block.
fn parse_metadata(
    package: &WorkspacePackage,
    readme_content: &str,
) -> Result<ReadmeMetadata, String> {
    // @behavior tool.readme.metadata.missing README metadata parsing reports package README files missing the selvedge metadata block.
    let start = readme_content.find(METADATA_BEGIN).ok_or_else(|| {
        format!(
            "{}/README.md:1: missing-readme-metadata: add selvedge-package-readme metadata",
            path_to_string(&package.path)
        )
    })?;
    let after_start = start + METADATA_BEGIN.len();
    let end = readme_content[after_start..]
        .find(METADATA_END)
        .map(|offset| after_start + offset)
        .ok_or_else(|| {
            format!(
                "{}/README.md:1: unterminated-readme-metadata: close selvedge-package-readme metadata",
                path_to_string(&package.path)
            )
        })?;
    let block = &readme_content[after_start..end];
    let mut metadata_package = None;
    let mut freshness_commit = None;

    for line in block.lines() {
        let trimmed = line.trim();
        if let Some(value) = trimmed.strip_prefix("package:") {
            metadata_package = Some(value.trim().to_owned());
        } else if let Some(value) = trimmed.strip_prefix("freshness_commit:") {
            freshness_commit = Some(value.trim().to_owned());
        }
    }

    let metadata_package = metadata_package.ok_or_else(|| {
        format!(
            "{}/README.md:1: missing-package-field: metadata must include package",
            path_to_string(&package.path)
        )
    })?;
    if metadata_package != package.name {
        // @behavior tool.readme.metadata.package_mismatch README metadata parsing reports package field values that differ from the Cargo package name.
        return Err(format!(
            "{}/README.md:1: package-mismatch: metadata package `{metadata_package}` does not match Cargo package `{}`",
            path_to_string(&package.path),
            package.name
        ));
    }

    let freshness_commit = freshness_commit.ok_or_else(|| {
        format!(
            "{}/README.md:1: missing-freshness-commit: metadata must include freshness_commit",
            path_to_string(&package.path)
        )
    })?;
    if !is_full_hex_commit(&freshness_commit) {
        // @behavior tool.readme.metadata.invalid_commit README metadata parsing reports freshness commits that are not full forty-character hex commit hashes.
        return Err(format!(
            "{}/README.md:1: invalid-freshness-commit: freshness_commit must be a 40-character hex commit hash",
            path_to_string(&package.path)
        ));
    }

    Ok(ReadmeMetadata { freshness_commit })
}

fn is_full_hex_commit(value: &str) -> bool {
    value.len() == 40 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

/// @behavior tool.readme.commit Commit validation accepts README freshness commits that resolve to repository commits.
fn ensure_commit_exists(root: &Path, commit: &str) -> Result<(), String> {
    let object = format!("{commit}^{{commit}}");
    let output = isolated_git_command()
        .current_dir(root)
        .args(["cat-file", "-e", &object])
        .output()
        // @behavior tool.readme.commit.spawn_failure Commit validation reports process errors when Git cannot be started.
        .map_err(|error| format!("failed to run git cat-file: {error}"))?;
    if output.status.success() {
        Ok(())
    } else {
        // @behavior tool.readme.commit.unknown Commit validation reports README freshness commits that are absent from the repository.
        Err(format!("freshness commit `{commit}` is not a known commit"))
    }
}

/// @behavior tool.readme.changed_files The freshness diff lists tracked package files changed since the README metadata commit and excludes the package README.
fn changed_package_files_since(
    root: &Path,
    commit: &str,
    package: &WorkspacePackage,
) -> Result<Vec<String>, String> {
    let range = format!("{commit}..HEAD");
    let pathspecs = &package.diff_pathspecs;
    let mut command = isolated_git_command();
    command
        .current_dir(root)
        .args(["diff", "--name-only", "-z", &range, "--"]);
    for pathspec in pathspecs {
        command.arg(pathspec);
    }
    let output = command
        .output()
        // @behavior tool.readme.changed_files.spawn_failure Freshness diff reports process errors when Git cannot be started.
        .map_err(|error| {
            format!(
                "failed to run git diff for {}: {error}",
                pathspecs.join(", ")
            )
        })?;
    if !output.status.success() {
        // @behavior tool.readme.changed_files.git_failure Freshness diff reports Git stderr when package diff collection fails.
        return Err(format!(
            "git diff failed for {}: {}",
            pathspecs.join(", "),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    let readme_path = package_readme_path(&package.path);
    let mut changed_files = output
        .stdout
        .split(|byte| *byte == b'\0')
        .filter(|entry| !entry.is_empty())
        .map(|entry| String::from_utf8_lossy(entry).into_owned())
        .filter(|path| path != &readme_path)
        .collect::<Vec<_>>();
    changed_files.sort();
    Ok(changed_files)
}

/// @behavior tool.readme.changed_files.readme_exclusion README freshness diff excludes the README path for root and nested packages.
fn package_readme_path(package_path: &Path) -> String {
    if package_path == Path::new(".") {
        "README.md".to_owned()
    } else {
        path_to_string(&package_path.join("README.md"))
    }
}

fn extract_mermaid_diagrams(content: &str) -> Vec<MermaidDiagram> {
    let mut diagrams = Vec::new();
    let mut current_line = 0;
    let mut current_source = Vec::new();
    let mut in_mermaid = false;

    for (index, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        if in_mermaid {
            if trimmed == "```" {
                diagrams.push(MermaidDiagram {
                    line: current_line,
                    source: current_source.join("\n"),
                });
                current_source.clear();
                in_mermaid = false;
            } else {
                current_source.push(line.to_owned());
            }
        } else if trimmed == "```mermaid" {
            current_line = index + 1;
            in_mermaid = true;
        }
    }

    if in_mermaid {
        diagrams.push(MermaidDiagram {
            line: current_line,
            source: current_source.join("\n"),
        });
    }

    diagrams
}

fn read_file(root: &Path, relative_path: &Path) -> Result<String, String> {
    let path = root.join(relative_path);
    // @behavior tool.readme.read_file Package README checks report filesystem read errors with the affected path.
    fs::read_to_string(&path).map_err(|error| format!("failed to read {}: {error}", path.display()))
}

fn path_to_string(path: &Path) -> String {
    path.iter()
        .map(|part| part.to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

fn isolated_git_command() -> Command {
    let mut command = Command::new("git");

    for (key, _) in std::env::vars_os() {
        if key.to_string_lossy().starts_with("GIT_") {
            command.env_remove(&key);
        }
    }

    command
}

#[cfg(test)]
mod tests {
    use super::{
        ReadmeFreshnessStatus, check_package_readme_mermaid, check_package_readmes_freshness,
    };
    use std::fs;
    use std::path::Path;
    use std::process::Command;
    use tempfile::TempDir;

    #[test]
    fn freshness_ignores_readme_changes_after_metadata_commit() {
        let repo = TestRepo::new();
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        repo.git_add(&["crates/demo/Cargo.toml", "crates/demo/src/lib.rs"]);
        repo.git_commit("create package");
        let commit = repo.head();
        repo.write("crates/demo/README.md", &readme("demo", &commit, "A --> B"));
        repo.git_add(&["crates/demo/README.md"]);
        repo.git_commit("document package");

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        // @verifies tool.readme.freshness
        assert_eq!(status, ReadmeFreshnessStatus::Fresh);
    }

    #[test]
    fn freshness_reports_package_changes_after_metadata_commit() {
        let repo = TestRepo::new();
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        repo.git_add(&["crates/demo/Cargo.toml", "crates/demo/src/lib.rs"]);
        repo.git_commit("create package");
        let commit = repo.head();
        repo.write("crates/demo/README.md", &readme("demo", &commit, "A --> B"));
        repo.git_add(&["crates/demo/README.md"]);
        repo.git_commit("document package");
        repo.write("crates/demo/src/lib.rs", "pub fn demo() -> u8 { 1 }\n");
        repo.git_add(&["crates/demo/src/lib.rs"]);
        repo.git_commit("change package");

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        // @verifies tool.readme.status
        let ReadmeFreshnessStatus::Stale { packages } = status else {
            panic!("expected stale package");
        };
        assert_eq!(packages[0].package, "demo");
        assert_eq!(packages[0].changed_files, vec!["crates/demo/src/lib.rs"]);
    }

    #[test]
    fn mermaid_check_renders_package_readme_diagrams() {
        let repo = TestRepo::new();
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        repo.write(
            "crates/demo/README.md",
            &readme("demo", &repo.head(), "A --> B"),
        );
        repo.git_add(&[
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/demo/README.md",
        ]);

        // @verifies tool.readme.mermaid
        check_package_readme_mermaid(repo.path()).expect("diagram should compile");
    }

    #[test]
    fn workspace_excludes_are_skipped_by_readme_gates() {
        let repo = TestRepo::new();
        repo.write(
            "Cargo.toml",
            "[workspace]\nmembers = [\"crates/*\"]\nexclude = [\"crates/template\"]\n",
        );
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        repo.write(
            "crates/template/Cargo.toml",
            "[package]\nname = \"template\"\nedition = \"2024\"\n",
        );
        repo.git_add(&[
            "Cargo.toml",
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/template/Cargo.toml",
        ]);
        repo.git_commit("create workspace packages");
        let commit = repo.head();
        repo.write("crates/demo/README.md", &readme("demo", &commit, "A --> B"));
        repo.git_add(&["crates/demo/README.md"]);
        repo.git_commit("document package");

        // @verifies tool.readme.packages.excludes
        check_package_readme_mermaid(repo.path()).expect("excluded packages should be skipped");
        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");
        assert_eq!(status, ReadmeFreshnessStatus::Fresh);
    }

    #[test]
    fn workspace_member_globs_skip_nested_manifests() {
        let repo = TestRepo::new();
        repo.write("Cargo.toml", "[workspace]\nmembers = [\"crates/*\"]\n");
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        // @verifies tool.readme.packages.metadata
        repo.write(
            "crates/demo/fixtures/nested/Cargo.toml",
            "[package]\nname = \"nested\"\nedition = \"2024\"\n",
        );
        // @verifies tool.readme.packages.metadata
        repo.git_add(&[
            "Cargo.toml",
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/demo/fixtures/nested/Cargo.toml",
        ]);
        // @verifies tool.readme.packages.metadata
        repo.git_commit("create nested fixture manifest");
        let commit = repo.head();
        repo.write("crates/demo/README.md", &readme("demo", &commit, "A --> B"));
        repo.git_add(&["crates/demo/README.md"]);
        repo.git_commit("document package");

        // @verifies tool.readme.packages.metadata
        check_package_readme_mermaid(repo.path())
            .expect("nested manifests outside Cargo workspace membership should be skipped");
    }

    #[test]
    fn root_package_freshness_tracks_metadata_targets() {
        let repo = TestRepo::new();
        repo.write(
            "Cargo.toml",
            "[package]\nname = \"root-demo\"\nedition = \"2024\"\n\n[workspace]\nmembers = []\n",
        );
        repo.write("src/lib.rs", "pub fn root_demo() {}\n");
        repo.git_add(&["Cargo.toml", "src/lib.rs"]);
        repo.git_commit("create root package");
        let commit = repo.head();
        repo.write("README.md", &readme("root-demo", &commit, "A --> B"));
        repo.git_add(&["README.md"]);
        repo.git_commit("document root package");
        repo.write("build.rs", "fn main() {}\n");
        repo.write("examples/demo.rs", "fn main() {}\n");
        repo.git_add(&["build.rs", "examples/demo.rs"]);
        repo.git_commit("add root package targets");

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        // @verifies tool.readme.changed_files.root_scope
        let ReadmeFreshnessStatus::Stale { packages } = status else {
            panic!("expected stale root package");
        };
        assert_eq!(packages[0].package, "root-demo");
        assert_eq!(
            packages[0].changed_files,
            vec!["build.rs", "examples/demo.rs"]
        );
    }

    #[test]
    fn root_package_freshness_tracks_deleted_default_targets() {
        let repo = TestRepo::new();
        repo.write(
            "Cargo.toml",
            "[package]\nname = \"root-demo\"\nedition = \"2024\"\n\n[workspace]\nmembers = []\n",
        );
        repo.write("src/lib.rs", "pub fn root_demo() {}\n");
        repo.write("build.rs", "fn main() {}\n");
        repo.git_add(&["Cargo.toml", "src/lib.rs", "build.rs"]);
        repo.git_commit("create root package with build script");
        let commit = repo.head();
        repo.write("README.md", &readme("root-demo", &commit, "A --> B"));
        repo.git_add(&["README.md"]);
        repo.git_commit("document root package");
        // @verifies tool.readme.changed_files.root_scope
        repo.git_rm(&["build.rs"]);
        repo.git_commit("remove root build script");

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        // @verifies tool.readme.changed_files.root_scope
        let ReadmeFreshnessStatus::Stale { packages } = status else {
            panic!("expected stale root package");
        };
        assert_eq!(packages[0].package, "root-demo");
        assert_eq!(packages[0].changed_files, vec!["build.rs"]);
    }

    fn readme(package: &str, commit: &str, diagram_body: &str) -> String {
        format!(
            "# {package}\n\n<!-- selvedge-package-readme\npackage: {package}\nfreshness_commit: {commit}\n-->\n\n```mermaid\nflowchart TD\n  {diagram_body}\n```\n"
        )
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
            fs::write(tempdir.path().join("README.md"), "# repo\n").expect("root readme");
            fs::write(
                tempdir.path().join("Cargo.toml"),
                "[workspace]\nmembers = [\"crates/demo\"]\n",
            )
            .expect("root manifest");
            run_git(tempdir.path(), &["add", "Cargo.toml", "README.md"]);
            run_git(
                tempdir.path(),
                &["-c", "commit.gpgsign=false", "commit", "-m", "initial"],
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

        fn git_add(&self, paths: &[&str]) {
            let mut args = vec!["add"];
            args.extend_from_slice(paths);
            run_git(self.path(), &args);
        }

        fn git_commit(&self, message: &str) {
            run_git(
                self.path(),
                &["-c", "commit.gpgsign=false", "commit", "-m", message],
            );
        }

        fn git_rm(&self, paths: &[&str]) {
            let mut args = vec!["rm"];
            args.extend_from_slice(paths);
            run_git(self.path(), &args);
        }

        fn head(&self) -> String {
            run_git(self.path(), &["rev-parse", "HEAD"])
        }
    }

    fn run_git(path: &Path, args: &[&str]) -> String {
        let mut command = Command::new("git");
        command
            .current_dir(path)
            .env("PRE_COMMIT_ALLOW_NO_CONFIG", "1")
            .args(args);

        for (key, _) in std::env::vars_os() {
            if key.to_string_lossy().starts_with("GIT_") {
                command.env_remove(&key);
            }
        }

        let output = command.output().expect("git command should run");
        // @verifies tool.readme.freshness
        assert!(
            output.status.success(),
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8_lossy(&output.stdout).trim().to_owned()
    }
}
