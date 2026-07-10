use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const METADATA_BEGIN: &str = "<!-- selvedge-package-readme";
const METADATA_END: &str = "-->";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReadmeFreshnessStatus {
    Fresh,
    Stale { packages: Vec<StalePackage> },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StalePackage {
    pub package: String,
    pub package_path: String,
    pub readme_path: String,
    pub freshness_fingerprint: String,
    pub current_fingerprint: String,
}

pub fn check_package_readmes_freshness(root: &Path) -> Result<ReadmeFreshnessStatus, String> {
    let packages = workspace_packages(root)?;
    let mut stale_packages = Vec::new();

    for package in packages {
        let readme_path = package.path.join("README.md");
        let readme_content = read_file(root, &readme_path)?;
        let metadata = parse_metadata(&package, &readme_content)?;
        let current_fingerprint = package_content_fingerprint(root, &package)?;
        if metadata.freshness_fingerprint != current_fingerprint {
            stale_packages.push(StalePackage {
                package: package.name,
                package_path: path_to_string(&package.path),
                readme_path: path_to_string(&readme_path),
                freshness_fingerprint: metadata.freshness_fingerprint,
                current_fingerprint,
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

pub fn update_package_readmes_freshness(root: &Path) -> Result<(), String> {
    let updates = workspace_packages(root)?
        .into_iter()
        .map(|package| {
            let readme_path = package.path.join("README.md");
            let readme_content = read_file(root, &readme_path)?;
            let fingerprint = package_content_fingerprint(root, &package)?;
            let updated = update_fingerprint_metadata(&package, &readme_content, &fingerprint)?;
            Ok((readme_path, updated))
        })
        .collect::<Result<Vec<_>, String>>()?;

    for (readme_path, updated) in updates {
        fs::write(root.join(&readme_path), updated).map_err(|error| {
            format!(
                "failed to write {}: {error}",
                root.join(&readme_path).display()
            )
        })?;
    }
    Ok(())
}

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
    freshness_fingerprint: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MermaidDiagram {
    line: usize,
    source: String,
}

fn workspace_packages(root: &Path) -> Result<Vec<WorkspacePackage>, String> {
    let metadata = cargo_workspace_metadata(root)?;
    let workspace_members = metadata
        .get("workspace_members")
        .and_then(serde_json::Value::as_array)
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

fn cargo_workspace_metadata(root: &Path) -> Result<serde_json::Value, String> {
    let output = Command::new("cargo")
        .current_dir(root)
        .args(["metadata", "--format-version", "1", "--no-deps"])
        .output()
        .map_err(|error| format!("failed to run cargo metadata: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "cargo metadata failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    serde_json::from_slice(&output.stdout)
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
        .map_err(|error| format!("failed to run git ls-files for package manifests: {error}"))?;
    if output.status.success() {
        return Ok(true);
    }
    if output.status.code() == Some(1) {
        return Ok(false);
    }
    Err(format!(
        "git ls-files failed for {}: {}",
        path,
        String::from_utf8_lossy(&output.stderr).trim()
    ))
}

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

fn parse_metadata(
    package: &WorkspacePackage,
    readme_content: &str,
) -> Result<ReadmeMetadata, String> {
    let (start, end) = metadata_block_range(package, readme_content)?;
    let block = &readme_content[start..end];
    let mut metadata_package = None;
    let mut freshness_fingerprint = None;

    for line in block.lines() {
        let trimmed = line.trim();
        if let Some(value) = trimmed.strip_prefix("package:") {
            metadata_package = Some(value.trim().to_owned());
        } else if let Some(value) = trimmed.strip_prefix("freshness_fingerprint:") {
            freshness_fingerprint = Some(value.trim().to_owned());
        }
    }

    let metadata_package = metadata_package.ok_or_else(|| {
        format!(
            "{}/README.md:1: missing-package-field: metadata must include package",
            path_to_string(&package.path)
        )
    })?;
    if metadata_package != package.name {
        return Err(format!(
            "{}/README.md:1: package-mismatch: metadata package `{metadata_package}` does not match Cargo package `{}`",
            path_to_string(&package.path),
            package.name
        ));
    }

    let freshness_fingerprint = freshness_fingerprint.ok_or_else(|| {
        format!(
            "{}/README.md:1: missing-freshness-fingerprint: metadata must include freshness_fingerprint",
            path_to_string(&package.path)
        )
    })?;
    if !is_hex_fingerprint(&freshness_fingerprint) {
        return Err(format!(
            "{}/README.md:1: invalid-freshness-fingerprint: freshness_fingerprint must be a 40- or 64-character hex hash",
            path_to_string(&package.path)
        ));
    }

    Ok(ReadmeMetadata {
        freshness_fingerprint,
    })
}

fn metadata_block_range(
    package: &WorkspacePackage,
    readme_content: &str,
) -> Result<(usize, usize), String> {
    let marker_start = readme_content.find(METADATA_BEGIN).ok_or_else(|| {
        format!(
            "{}/README.md:1: missing-readme-metadata: add selvedge-package-readme metadata",
            path_to_string(&package.path)
        )
    })?;
    let start = marker_start + METADATA_BEGIN.len();
    let end = readme_content[start..]
        .find(METADATA_END)
        .map(|offset| start + offset)
        .ok_or_else(|| {
            format!(
                "{}/README.md:1: unterminated-readme-metadata: close selvedge-package-readme metadata",
                path_to_string(&package.path)
            )
        })?;
    Ok((start, end))
}

fn is_hex_fingerprint(value: &str) -> bool {
    matches!(value.len(), 40 | 64) && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn package_readme_path(package_path: &Path) -> String {
    if package_path == Path::new(".") {
        "README.md".to_owned()
    } else {
        path_to_string(&package_path.join("README.md"))
    }
}

fn package_content_fingerprint(root: &Path, package: &WorkspacePackage) -> Result<String, String> {
    let mut list_command = isolated_git_command();
    list_command
        .current_dir(root)
        .args(["ls-files", "--stage", "-z", "--"]);
    for pathspec in &package.diff_pathspecs {
        list_command.arg(pathspec);
    }
    let output = list_command
        .output()
        .map_err(|error| format!("failed to list tracked package files: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "git ls-files failed for {}: {}",
            package.diff_pathspecs.join(", "),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    let readme_path = package_readme_path(&package.path);
    let mut entries = Vec::new();
    for entry in output.stdout.split(|byte| *byte == b'\0') {
        if entry.is_empty() {
            continue;
        }
        let separator = entry
            .iter()
            .position(|byte| *byte == b'\t')
            .ok_or_else(|| "git ls-files returned an invalid index entry".to_owned())?;
        let path = &entry[separator + 1..];
        if path == readme_path.as_bytes() {
            continue;
        }
        let mut fields = entry[..separator].split(|byte| byte.is_ascii_whitespace());
        let _mode = fields.next();
        let blob = fields
            .next()
            .ok_or_else(|| "git ls-files index entry is missing a blob hash".to_owned())?;
        let stage = fields
            .next()
            .ok_or_else(|| "git ls-files index entry is missing a stage".to_owned())?;
        if stage != b"0" {
            return Err(format!(
                "cannot fingerprint unmerged package file {}",
                String::from_utf8_lossy(path)
            ));
        }
        entries.push((path.to_vec(), blob.to_vec()));
    }
    entries.sort_by(|left, right| left.0.cmp(&right.0));

    let mut hash_command = isolated_git_command();
    let mut child = hash_command
        .current_dir(root)
        .args(["hash-object", "--stdin"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to run git hash-object: {error}"))?;
    {
        let stdin = child
            .stdin
            .as_mut()
            .ok_or_else(|| "failed to open git hash-object stdin".to_owned())?;
        for (path, blob) in entries {
            stdin
                .write_all(&path)
                .and_then(|()| stdin.write_all(&[0]))
                .and_then(|()| stdin.write_all(&blob))
                .and_then(|()| stdin.write_all(&[0]))
                .map_err(|error| format!("failed to write package fingerprint input: {error}"))?;
        }
    }
    let output = child
        .wait_with_output()
        .map_err(|error| format!("failed to wait for git hash-object: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "git hash-object failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn update_fingerprint_metadata(
    package: &WorkspacePackage,
    readme_content: &str,
    fingerprint: &str,
) -> Result<String, String> {
    parse_metadata(package, readme_content)?;
    let (start, end) = metadata_block_range(package, readme_content)?;
    let block = &readme_content[start..end];

    let key = "freshness_fingerprint:";
    let key_start = block.find(key).ok_or_else(|| {
        format!(
            "{}/README.md:1: missing-freshness-fingerprint: metadata must include freshness_fingerprint",
            path_to_string(&package.path)
        )
    })?;
    let value_start = key_start + key.len();
    let value_end = block[value_start..]
        .find(['\r', '\n'])
        .map_or(block.len(), |offset| value_start + offset);
    let mut updated = readme_content.to_owned();
    updated.replace_range(
        start + value_start..start + value_end,
        &format!(" {fingerprint}"),
    );
    Ok(updated)
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
        update_package_readmes_freshness,
    };
    use std::fs;
    use std::path::Path;
    use std::process::Command;
    use tempfile::TempDir;

    #[test]
    fn update_freshness_writes_current_content_fingerprint() {
        let repo = TestRepo::new();
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        repo.write(
            "crates/demo/README.md",
            &fingerprint_readme("demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&[
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/demo/README.md",
        ]);

        update_package_readmes_freshness(repo.path()).expect("update should succeed");

        let updated = fs::read_to_string(repo.path().join("crates/demo/README.md"))
            .expect("README should be readable");
        assert!(!updated.contains(&format!("freshness_fingerprint: {}", "0".repeat(40))));
        assert!(updated.contains("freshness_fingerprint: "));
        assert_eq!(
            check_package_readmes_freshness(repo.path()).expect("freshness check should run"),
            ReadmeFreshnessStatus::Fresh
        );
    }

    #[test]
    fn freshness_reports_staged_package_content_changes() {
        let repo = TestRepo::new();
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        repo.write(
            "crates/demo/README.md",
            &fingerprint_readme("demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&[
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/demo/README.md",
        ]);
        update_package_readmes_freshness(repo.path()).expect("update should succeed");
        repo.git_add(&["crates/demo/README.md"]);
        repo.git_commit("document package");
        repo.write("crates/demo/src/lib.rs", "pub fn demo() -> u8 { 1 }\n");
        repo.git_add(&["crates/demo/src/lib.rs"]);

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        assert!(matches!(status, ReadmeFreshnessStatus::Stale { .. }));
    }

    #[test]
    fn freshness_ignores_readme_only_changes() {
        let repo = TestRepo::new();
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        repo.write(
            "crates/demo/README.md",
            &fingerprint_readme("demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&[
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/demo/README.md",
        ]);
        update_package_readmes_freshness(repo.path()).expect("update should succeed");
        let readme = repo
            .read("crates/demo/README.md")
            .replace("A --> B", "A --> C");
        repo.write("crates/demo/README.md", &readme);
        repo.git_add(&["crates/demo/README.md"]);

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        assert_eq!(status, ReadmeFreshnessStatus::Fresh);
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
            &fingerprint_readme("demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&[
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/demo/README.md",
        ]);

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
        repo.write(
            "crates/demo/README.md",
            &fingerprint_readme("demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&["crates/demo/README.md"]);
        update_package_readmes_freshness(repo.path()).expect("update should succeed");

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
        repo.write(
            "crates/demo/fixtures/nested/Cargo.toml",
            "[package]\nname = \"nested\"\nedition = \"2024\"\n",
        );
        repo.git_add(&[
            "Cargo.toml",
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/demo/fixtures/nested/Cargo.toml",
        ]);
        repo.write(
            "crates/demo/README.md",
            &fingerprint_readme("demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&["crates/demo/README.md"]);

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
        repo.write(
            "README.md",
            &fingerprint_readme("root-demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&["Cargo.toml", "src/lib.rs", "README.md"]);
        update_package_readmes_freshness(repo.path()).expect("update should succeed");
        repo.git_add(&["README.md"]);
        repo.write("build.rs", "fn main() {}\n");
        repo.write("examples/demo.rs", "fn main() {}\n");
        repo.git_add(&["build.rs", "examples/demo.rs"]);

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        let ReadmeFreshnessStatus::Stale { packages } = status else {
            panic!("expected stale root package");
        };
        assert_eq!(packages[0].package, "root-demo");
        assert_ne!(
            packages[0].freshness_fingerprint,
            packages[0].current_fingerprint
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
        repo.write(
            "README.md",
            &fingerprint_readme("root-demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&["Cargo.toml", "src/lib.rs", "build.rs", "README.md"]);
        update_package_readmes_freshness(repo.path()).expect("update should succeed");
        repo.git_add(&["README.md"]);
        repo.git_commit("document root package");
        repo.git_rm(&["build.rs"]);

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        let ReadmeFreshnessStatus::Stale { packages } = status else {
            panic!("expected stale root package");
        };
        assert_eq!(packages[0].package, "root-demo");
        assert_ne!(
            packages[0].freshness_fingerprint,
            packages[0].current_fingerprint
        );
    }

    #[test]
    fn freshness_accepts_equivalent_content_after_history_rewrite() {
        let repo = TestRepo::new();
        repo.write(
            "crates/demo/Cargo.toml",
            "[package]\nname = \"demo\"\nedition = \"2024\"\n",
        );
        repo.write("crates/demo/src/lib.rs", "pub fn demo() {}\n");
        repo.write(
            "crates/demo/README.md",
            &fingerprint_readme("demo", &"0".repeat(40), "A --> B"),
        );
        repo.git_add(&[
            "crates/demo/Cargo.toml",
            "crates/demo/src/lib.rs",
            "crates/demo/README.md",
        ]);
        update_package_readmes_freshness(repo.path()).expect("update should succeed");
        repo.git_add(&["crates/demo/README.md"]);
        repo.git_commit("document package");
        let rewritten_head = repo.commit_tree("rewritten history");
        repo.git_reset_hard(&rewritten_head);

        let status =
            check_package_readmes_freshness(repo.path()).expect("freshness check should run");

        assert_eq!(status, ReadmeFreshnessStatus::Fresh);
    }

    fn fingerprint_readme(package: &str, fingerprint: &str, diagram_body: &str) -> String {
        format!(
            "# {package}\n\n<!-- selvedge-package-readme\npackage: {package}\nfreshness_fingerprint: {fingerprint}\n-->\n\n```mermaid\nflowchart TD\n  {diagram_body}\n```\n"
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

        fn read(&self, relative_path: &str) -> String {
            fs::read_to_string(self.path().join(relative_path)).expect("file should be readable")
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

        fn commit_tree(&self, message: &str) -> String {
            run_git(self.path(), &["commit-tree", "HEAD^{tree}", "-m", message])
        }

        fn git_reset_hard(&self, commit: &str) {
            run_git(self.path(), &["reset", "--hard", commit]);
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
        assert!(
            output.status.success(),
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8_lossy(&output.stdout).trim().to_owned()
    }
}
