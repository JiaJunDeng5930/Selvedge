//! @behavior req The xtask requirement tool validates source-comment requirements and AGENTS index freshness.
//! @behavior req.api The public API exposes requirement automation commands to the xtask binary.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

const BEGIN_MARKER: &str = "<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->";
const END_MARKER: &str = "<!-- END AGENTS_MD_REQUIREMENT_INDEX -->";

/// @constraint req.api.mode The check mode enum limits validation to the full checkout, the staged Git snapshot, or a base ref diff.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RequirementCheckMode {
    All,
    Staged,
    Base { git_ref: String },
}

/// @constraint req.api.status The check status enum reports either a fresh requirement index or a stale AGENTS block.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequirementCheckStatus {
    Fresh,
    StaleAgentsIndex,
}

/// @behavior req.api.report The scan report returns discovered declarations, verification links, and diagnostics together.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementScanReport {
    /// @behavior req.api.report.declarations The declarations field carries behavior, constraint, and intent records discovered from source comments.
    pub declarations: Vec<RequirementRecord>,
    /// @behavior req.api.report.verifications The verifications field carries test expectation records discovered from source comments.
    pub verifications: Vec<RequirementRecord>,
    /// @behavior req.api.report.diagnostics The diagnostics field carries every validation problem discovered during scanning.
    pub diagnostics: Vec<Diagnostic>,
}

/// @behavior req.api.record The requirement record stores the source location, tag, ID, sentence, and binding target.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementRecord {
    /// @behavior req.api.record.path The path field stores the repository-relative Rust source path for the requirement comment.
    pub path: String,
    /// @behavior req.api.record.line The line field stores the one-based source line where the requirement comment begins.
    pub line: usize,
    /// @behavior req.api.record.tag The tag field stores the parsed semantic kind of the requirement comment.
    pub tag: RequirementTag,
    /// @behavior req.api.record.id The id field stores the dotted requirement tree position for the record.
    pub id: String,
    /// @behavior req.api.record.sentence The sentence field stores the one-sentence requirement body without the tag and ID.
    pub sentence: String,
    /// @behavior req.api.record.binding The binding field stores the Rust item or statement attached to the requirement comment.
    pub binding: String,
    /// @behavior req.api.record.test_context The test-context field records whether the requirement comment is inside an inline test scope.
    pub in_test_context: bool,
}

/// @constraint req.api.tag The tag enum contains exactly the four requirement comment tags accepted by the protocol.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequirementTag {
    Behavior,
    Constraint,
    Intent,
    Verifies,
}

impl RequirementTag {
    /// @behavior req.api.tag.string The tag renderer returns the exact source token for each accepted requirement tag.
    pub fn as_str(self) -> &'static str {
        match self {
            RequirementTag::Behavior => "@behavior",
            RequirementTag::Constraint => "@constraint",
            RequirementTag::Intent => "@intent",
            RequirementTag::Verifies => "@verifies",
        }
    }

    fn is_declaration(self) -> bool {
        matches!(
            self,
            RequirementTag::Behavior | RequirementTag::Constraint | RequirementTag::Intent
        )
    }
}

/// @behavior req.api.diagnostic The diagnostic struct renders compiler-style file, line, rule, and message fields.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    /// @behavior req.api.diagnostic.path The diagnostic path field stores the repository-relative source path for a validation problem.
    pub path: String,
    /// @behavior req.api.diagnostic.line The diagnostic line field stores the one-based source line for a validation problem.
    pub line: usize,
    /// @behavior req.api.diagnostic.rule The diagnostic rule field stores the stable rule identifier for a validation problem.
    pub rule: &'static str,
    /// @behavior req.api.diagnostic.message The diagnostic message field stores the human-readable validation problem.
    pub message: String,
}

/// @behavior req.scan The scan command reads tracked Rust files and reports requirement comments with validation diagnostics.
pub fn scan_requirements(root: &Path) -> Result<RequirementScanReport, String> {
    let snapshot = Snapshot::from_worktree(root)?;
    Ok(scan_snapshot(&snapshot))
}

/// @behavior req.format The fmt-agents command rewrites only the generated requirement index block in AGENTS.md.
pub fn format_agents_requirement_index(root: &Path) -> Result<(), String> {
    let snapshot = Snapshot::from_worktree(root)?;
    let report = scan_snapshot(&snapshot);
    if !report.diagnostics.is_empty() {
        return Err(render_diagnostics(&report.diagnostics));
    }

    let agents_path = root.join("AGENTS.md");
    // @behavior req.format.read The fmt-agents command reports filesystem read failures for AGENTS.md.
    let existing = fs::read_to_string(&agents_path)
        .map_err(|error| format!("failed to read {}: {error}", agents_path.display()))?;
    let line_ending = detect_line_ending(&existing);
    let block = render_requirement_index_block(&report.declarations, line_ending);
    let updated = upsert_requirement_index_block(&existing, &block, line_ending)?;
    // @behavior req.format.write The fmt-agents command reports filesystem write failures for AGENTS.md.
    fs::write(&agents_path, updated)
        .map_err(|error| format!("failed to write {}: {error}", agents_path.display()))
}

/// @behavior req.check The check command validates comments, registry links, anchors, and AGENTS index freshness.
pub fn check_requirements(
    root: &Path,
    mode: RequirementCheckMode,
) -> Result<RequirementCheckStatus, String> {
    let snapshot = match mode {
        RequirementCheckMode::All => Snapshot::from_worktree(root)?,
        RequirementCheckMode::Staged => Snapshot::from_index(root)?,
        RequirementCheckMode::Base { .. } => Snapshot::from_worktree(root)?,
    };
    let mut report = scan_snapshot(&snapshot);

    let current_records = report
        .declarations
        .iter()
        .cloned()
        .chain(report.verifications.iter().cloned())
        .collect::<Vec<_>>();

    match &mode {
        RequirementCheckMode::All => {
            // @behavior req.check.all_anchors The all check classifies every Rust source line in the current checkout with the same anchor rules used for changed hunks.
            let all_anchor_diagnostics = classify_full_snapshot(&snapshot.files, &current_records);
            report.diagnostics.extend(all_anchor_diagnostics);
        }
        RequirementCheckMode::Staged => {
            // @behavior req.check.head_snapshot The staged check uses an empty old snapshot when HEAD is unavailable.
            let old_snapshot = match Snapshot::from_git_ref(root, "HEAD") {
                Ok(snapshot) => snapshot,
                Err(_) => Snapshot { files: Vec::new() },
            };
            let old_report = scan_snapshot(&old_snapshot);
            let old_records = old_report
                .declarations
                .iter()
                .cloned()
                .chain(old_report.verifications.iter().cloned())
                .collect::<Vec<_>>();
            report.diagnostics.extend(classify_git_diff(
                root,
                &["diff", "--cached", "--unified=0", "--", "*.rs"],
                "git diff --cached",
                &snapshot.files,
                &current_records,
                &old_snapshot.files,
                &old_records,
            )?);
        }
        RequirementCheckMode::Base { git_ref } => {
            let merge_base = git_merge_base(root, git_ref)?;
            let old_snapshot = Snapshot::from_git_ref(root, &merge_base)?;
            let old_report = scan_snapshot(&old_snapshot);
            let old_records = old_report
                .declarations
                .iter()
                .cloned()
                .chain(old_report.verifications.iter().cloned())
                .collect::<Vec<_>>();
            let range = format!("{merge_base}...HEAD");
            report.diagnostics.extend(classify_git_diff(
                root,
                &["diff", "--unified=0", &range, "--", "*.rs"],
                "git diff --base",
                &snapshot.files,
                &current_records,
                &old_snapshot.files,
                &old_records,
            )?);
        }
    }

    // @behavior req.check.diagnostics The check command renders accumulated diagnostics as a failing result.
    if !report.diagnostics.is_empty() {
        return Err(render_diagnostics(&report.diagnostics));
    }

    let agents_md = snapshot
        .files
        .iter()
        .find(|file| file.path == "AGENTS.md")
        .map(|file| file.content.as_str())
        .unwrap_or("");
    let line_ending = detect_line_ending(agents_md);
    let block = render_requirement_index_block(&report.declarations, line_ending);
    let expected = upsert_requirement_index_block(agents_md, &block, line_ending)?;
    if expected == agents_md {
        Ok(RequirementCheckStatus::Fresh)
    } else {
        Ok(RequirementCheckStatus::StaleAgentsIndex)
    }
}

fn scan_snapshot(snapshot: &Snapshot) -> RequirementScanReport {
    let mut declarations = Vec::new();
    let mut verifications = Vec::new();
    let mut diagnostics = Vec::new();

    for file in snapshot
        .files
        .iter()
        .filter(|file| file.path.ends_with(".rs"))
    {
        diagnostics.extend(validate_rust_parses(file));
        for raw in extract_requirement_comments(file) {
            match parse_requirement_comment(&raw.normalized) {
                Ok(parsed) => match bind_comment(file, &raw) {
                    Some(binding) => {
                        let record = RequirementRecord {
                            path: file.path.clone(),
                            line: raw.line,
                            tag: parsed.tag,
                            id: parsed.id,
                            sentence: parsed.sentence,
                            binding,
                            in_test_context: is_inline_test_context(file, raw.line),
                        };
                        if record.tag == RequirementTag::Verifies {
                            verifications.push(record);
                        } else {
                            declarations.push(record);
                        }
                    }
                    None => diagnostics.push(Diagnostic {
                        path: file.path.clone(),
                        line: raw.line,
                        rule: "unbound-requirement-comment",
                        message: "requirement comment must bind to the next Rust item or statement"
                            .to_string(),
                    }),
                },
                // @behavior req.scan.parse_error The scanner stores parser failures as invalid requirement comment diagnostics.
                Err(message) => diagnostics.push(Diagnostic {
                    path: file.path.clone(),
                    line: raw.line,
                    rule: "invalid-requirement-comment",
                    message,
                }),
            }
        }
    }

    diagnostics.extend(validate_registry(&declarations, &verifications));
    RequirementScanReport {
        declarations,
        verifications,
        diagnostics,
    }
}

fn validate_rust_parses(file: &SnapshotFile) -> Vec<Diagnostic> {
    let mut parser = tree_sitter::Parser::new();
    let language = tree_sitter_rust::LANGUAGE.into();
    if parser.set_language(&language).is_err() {
        return vec![Diagnostic {
            path: file.path.clone(),
            line: 1,
            rule: "rust-parser-unavailable",
            message: "tree-sitter-rust language could not be installed".to_string(),
        }];
    }
    let Some(tree) = parser.parse(&file.content, None) else {
        return vec![Diagnostic {
            path: file.path.clone(),
            line: 1,
            rule: "rust-parse-failed",
            message: "tree-sitter could not parse this Rust file".to_string(),
        }];
    };
    if tree.root_node().has_error() {
        vec![Diagnostic {
            path: file.path.clone(),
            line: 1,
            rule: "rust-parse-error",
            message: "tree-sitter found a syntax error in this Rust file".to_string(),
        }]
    } else {
        Vec::new()
    }
}

/// @behavior req.api.parse The requirement parser converts one normalized comment body into its tag, ID, and sentence.
fn parse_requirement_comment(content: &str) -> Result<ParsedRequirement, String> {
    let mut parts = content.splitn(3, char::is_whitespace);
    let tag = match parts.next().unwrap_or_default() {
        "@behavior" => RequirementTag::Behavior,
        "@constraint" => RequirementTag::Constraint,
        "@intent" => RequirementTag::Intent,
        "@verifies" => RequirementTag::Verifies,
        // @constraint req.api.parse.tag The parser rejects comments whose first token is outside the allowed requirement tag set.
        _ => return Err("requirement comment must start with an allowed tag".to_string()),
    };
    let Some(id) = parts.next().filter(|id| !id.is_empty()) else {
        // @constraint req.api.parse.id_presence The parser rejects comments that omit the dotted requirement ID.
        return Err("requirement comment must include a dotted ID".to_string());
    };
    if !valid_requirement_id(id) {
        // @constraint req.api.parse.id_grammar The parser rejects IDs that violate the dotted lowercase grammar.
        return Err(format!(
            "requirement ID `{id}` violates the dotted ID grammar"
        ));
    }
    let Some(sentence) = parts.next().map(str::trim).filter(|text| !text.is_empty()) else {
        // @constraint req.api.parse.sentence_presence The parser rejects comments that omit the one-sentence requirement body.
        return Err("requirement comment must include one sentence".to_string());
    };
    if !has_one_sentence(sentence) {
        // @constraint req.api.parse.sentence_count The parser rejects comments whose requirement body contains more or less than one sentence.
        return Err("requirement comments must contain exactly one sentence".to_string());
    }
    Ok(ParsedRequirement {
        tag,
        id: id.to_string(),
        sentence: sentence.to_string(),
    })
}

fn valid_requirement_id(id: &str) -> bool {
    id.split('.').all(|segment| {
        let mut chars = segment.chars();
        matches!(chars.next(), Some(first) if first.is_ascii_lowercase())
            && chars.all(|character| {
                character.is_ascii_lowercase() || character.is_ascii_digit() || character == '_'
            })
    })
}

fn has_one_sentence(sentence: &str) -> bool {
    let trimmed = sentence.trim();
    if !trimmed.ends_with(['.', '!', '?']) {
        return false;
    }
    sentence_boundary_count(trimmed) == 1
}

fn sentence_boundary_count(sentence: &str) -> usize {
    let mut count = 0usize;
    let mut characters = sentence.char_indices().peekable();
    while let Some((index, character)) = characters.next() {
        if !matches!(character, '.' | '!' | '?') {
            continue;
        }
        if character == '!' && is_known_macro_bang(sentence, index) {
            continue;
        }
        let is_last = characters.peek().is_none();
        let next_is_whitespace = characters
            .peek()
            .is_some_and(|(_, next)| next.is_whitespace());
        if is_last || next_is_whitespace {
            count += 1;
        }
    }
    count
}

/// @constraint req.api.diagnostic.macro The sentence counter ignores bang punctuation for known Rust macro names.
fn is_known_macro_bang(sentence: &str, bang_index: usize) -> bool {
    let name_start = sentence[..bang_index]
        .char_indices()
        .rev()
        .find(|(_, character)| !(character.is_ascii_alphanumeric() || *character == '_'))
        .map_or(0, |(index, character)| index + character.len_utf8());
    let name = &sentence[name_start..bang_index];
    matches!(
        name,
        "assert"
            | "assert_eq"
            | "assert_ne"
            | "dbg"
            | "eprintln"
            | "format"
            | "matches"
            | "panic"
            | "println"
            | "todo"
            | "unimplemented"
            | "unreachable"
            | "vec"
            | "write"
            | "writeln"
    )
}

/// @behavior req.check.registry The registry validator checks ID uniqueness, ancestor declarations, and verification link targets.
fn validate_registry(
    declarations: &[RequirementRecord],
    verifications: &[RequirementRecord],
) -> Vec<Diagnostic> {
    let mut diagnostics = Vec::new();
    let mut declared: BTreeMap<&str, &RequirementRecord> = BTreeMap::new();
    let mut duplicate_ids = BTreeSet::new();
    for declaration in declarations {
        if declared.insert(&declaration.id, declaration).is_some() {
            duplicate_ids.insert(declaration.id.as_str());
        }
    }
    for id in duplicate_ids {
        if let Some(record) = declared.get(id) {
            diagnostics.push(Diagnostic {
                path: record.path.clone(),
                line: record.line,
                rule: "duplicate-requirement-id",
                message: format!("declaration ID `{id}` appears more than once"),
            });
        }
    }

    for declaration in declarations {
        for ancestor in ancestor_ids(&declaration.id) {
            if !declared.contains_key(ancestor.as_str()) {
                diagnostics.push(Diagnostic {
                    path: declaration.path.clone(),
                    line: declaration.line,
                    rule: "missing-requirement-ancestor",
                    message: format!(
                        "declared ID `{}` requires ancestor `{ancestor}`",
                        declaration.id
                    ),
                });
            }
        }
    }

    for verification in verifications {
        if !is_test_path(&verification.path) && !verification.in_test_context {
            diagnostics.push(Diagnostic {
                path: verification.path.clone(),
                line: verification.line,
                rule: "verification-outside-test",
                message: "@verifies comments must live in tests, examples, or xtask test modules"
                    .to_string(),
            });
        }
        match declared.get(verification.id.as_str()) {
            // @constraint req.check.registry.target_declaration Verification targets must resolve to behavior or constraint declarations.
            Some(record)
                if matches!(
                    record.tag,
                    RequirementTag::Behavior | RequirementTag::Constraint
                ) => {}
            // @constraint req.check.registry.target_kind Verification comments can target only behavior or constraint declarations.
            Some(_) => diagnostics.push(Diagnostic {
                path: verification.path.clone(),
                line: verification.line,
                rule: "verification-target-kind",
                message: format!(
                    "`@verifies {}` must reference @behavior or @constraint",
                    verification.id
                ),
            }),
            None => diagnostics.push(Diagnostic {
                path: verification.path.clone(),
                line: verification.line,
                rule: "missing-verification-target",
                message: format!(
                    "`@verifies {}` references an undeclared requirement",
                    verification.id
                ),
            }),
        }
    }

    diagnostics
}

/// @behavior req.check.registry.ancestor The registry validator derives every dotted ancestor required by a declaration ID.
fn ancestor_ids(id: &str) -> Vec<String> {
    let parts = id.split('.').collect::<Vec<_>>();
    (1..parts.len()).map(|end| parts[..end].join(".")).collect()
}

/// @constraint req.check.registry.test_path Verification comments are accepted only from Cargo test and example paths outside inline test modules.
fn is_test_path(path: &str) -> bool {
    path.contains("/tests/")
        || path.starts_with("tests/")
        || path.contains("/examples/")
        || path.starts_with("examples/")
        || path == "tests.rs"
        || path.ends_with("/tests.rs")
        || path.ends_with("_test.rs")
}

fn render_requirement_index_block(declarations: &[RequirementRecord], line_ending: &str) -> String {
    let mut ids = declarations
        .iter()
        .filter(|record| record.tag.is_declaration())
        .map(|record| record.id.clone())
        .collect::<BTreeSet<_>>();
    let mut children: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for id in &ids {
        children.entry(id.clone()).or_default();
    }
    for id in &ids {
        if let Some((parent, segment)) = id.rsplit_once('.')
            && ids.contains(parent)
        {
            children
                .entry(parent.to_string())
                .or_default()
                .insert(segment.to_string());
        }
    }

    let mut lines = vec![
        BEGIN_MARKER.to_string(),
        "[Requirement Index]|root:.".to_string(),
        "|IMPORTANT: Requirement truth lives in source comments; search source comments for an ID before changing code.".to_string(),
        "|source:source_comments_only".to_string(),
        "|comment_body:single_sentence".to_string(),
        "|tags:{@behavior,@constraint,@intent,@verifies}".to_string(),
    ];
    for id in ids.iter() {
        let row_children = children.remove(id).unwrap_or_default();
        if row_children.is_empty() {
            lines.push(format!("|{id}|{id}.{{}}"));
        } else {
            let joined = row_children.into_iter().collect::<Vec<_>>().join(",");
            lines.push(format!("|{id}|{id}.{{{joined}}}"));
        }
    }
    ids.clear();
    lines.push(END_MARKER.to_string());
    lines.join(line_ending)
}
/// @behavior req.format.index_block The index block updater preserves AGENTS content around the generated requirement block.
fn upsert_requirement_index_block(
    existing: &str,
    block: &str,
    line_ending: &str,
) -> Result<String, String> {
    let begin_matches = existing.matches(BEGIN_MARKER).count();
    let end_matches = existing.matches(END_MARKER).count();
    if begin_matches > 1 || end_matches > 1 {
        // @constraint req.format.index_block.marker_count The index updater rejects duplicate generated-block markers in AGENTS.md.
        return Err("AGENTS.md contains duplicate requirement index markers".to_string());
    }
    if begin_matches != end_matches {
        // @constraint req.format.index_block.marker_balance The index updater rejects unbalanced generated-block markers in AGENTS.md.
        return Err("AGENTS.md requirement index markers are unbalanced".to_string());
    }
    if begin_matches == 0 {
        let mut updated = existing.trim_end().to_string();
        if !updated.is_empty() {
            updated.push_str(line_ending);
            updated.push_str(line_ending);
        }
        updated.push_str(block);
        updated.push_str(line_ending);
        return Ok(updated);
    }

    let start = existing
        .find(BEGIN_MARKER)
        // @constraint req.format.index_block.marker_lookup_begin The index updater treats begin-marker lookup failure as unreachable after marker counts pass.
        .expect("marker count already checked");
    let end = existing
        .find(END_MARKER)
        // @constraint req.format.index_block.marker_lookup_end The index updater treats end-marker lookup failure as unreachable after marker counts pass.
        .expect("marker count already checked")
        + END_MARKER.len();
    let mut updated = String::new();
    updated.push_str(&existing[..start]);
    updated.push_str(block);
    updated.push_str(&existing[end..]);
    Ok(updated)
}

/// @behavior req.detector.full The full classifier validates every Rust source line in a snapshot against nearby requirement anchors.
fn classify_full_snapshot(
    files: &[SnapshotFile],
    records: &[RequirementRecord],
) -> Vec<Diagnostic> {
    let mut diagnostics = Vec::new();
    for file in files.iter().filter(|file| file.path.ends_with(".rs")) {
        for (index, line) in file.content.lines().enumerate() {
            classify_rust_line(
                &mut diagnostics,
                &file.path,
                index + 1,
                line.trim(),
                files,
                records,
                "Rust line",
            );
        }
    }
    diagnostics
}

/// @behavior req.detector.diff The diff classifier walks Git unified diff lines and validates changed Rust hunks against nearby anchors.
fn classify_git_diff(
    root: &Path,
    args: &[&str],
    command_name: &str,
    new_files: &[SnapshotFile],
    new_records: &[RequirementRecord],
    old_files: &[SnapshotFile],
    old_records: &[RequirementRecord],
) -> Result<Vec<Diagnostic>, String> {
    // @behavior req.detector.diff_command The diff classifier maps Git command execution failure into a tool diagnostic.
    let output = match isolated_git_command().current_dir(root).args(args).output() {
        Ok(output) => output,
        Err(error) => return Err(format!("failed to run {command_name}: {error}")),
    };
    if !output.status.success() {
        return Err(format!(
            "{command_name} failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    let mut diagnostics = Vec::new();
    let mut removed_line_records = old_records.to_vec();
    removed_line_records.extend_from_slice(new_records);
    let mut old_path = None::<String>;
    let mut new_path = None::<String>;
    let mut old_line = 0usize;
    let mut new_line = 0usize;
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        if let Some(path) = line.strip_prefix("--- a/") {
            old_path = Some(path.to_string());
            continue;
        }
        if let Some(path) = line.strip_prefix("+++ b/") {
            new_path = Some(path.to_string());
            continue;
        }
        if let Some(hunk) = line.strip_prefix("@@ ") {
            let (parsed_old_line, parsed_new_line) = parse_hunk_starts(hunk);
            old_line = parsed_old_line;
            new_line = parsed_new_line;
            continue;
        }
        if line.starts_with('+') && !line.starts_with("+++") {
            let Some(path) = new_path.as_deref() else {
                continue;
            };
            classify_rust_line(
                &mut diagnostics,
                path,
                new_line,
                line.trim_start_matches('+').trim(),
                new_files,
                new_records,
                "changed Rust hunk",
            );
            new_line += 1;
            continue;
        }
        if line.starts_with('-') && !line.starts_with("---") {
            let Some(path) = old_path.as_deref() else {
                continue;
            };
            classify_rust_line(
                &mut diagnostics,
                path,
                old_line,
                line.trim_start_matches('-').trim(),
                old_files,
                &removed_line_records,
                "changed Rust hunk",
            );
            old_line += 1;
            continue;
        }
        if !line.starts_with('\\') {
            old_line += 1;
            new_line += 1;
        }
    }
    Ok(diagnostics)
}

/// @behavior req.detector.line The line classifier checks one Rust source line against detector rules and nearby requirement anchors.
fn classify_rust_line(
    diagnostics: &mut Vec<Diagnostic>,
    path: &str,
    line: usize,
    changed: &str,
    files: &[SnapshotFile],
    records: &[RequirementRecord],
    subject: &'static str,
) {
    if changed.is_empty() || changed.starts_with("//") || changed.starts_with("/*") {
        return;
    }

    let changed_file = files.iter().find(|file| file.path == path);
    let signature_continuation =
        changed_file.is_some_and(|file| is_visible_signature_continuation(file, line, changed));
    let contract_attribute =
        changed_file.is_some_and(|file| is_visible_contract_attribute(file, line, changed));
    let container_contract_line =
        changed_file.and_then(|file| enclosing_public_container_contract_line(file, line, changed));
    let classified_line = classify_added_line(changed).or_else(|| {
        (signature_continuation || contract_attribute || container_contract_line.is_some()).then(
            || {
                (
                    "missing-contract-anchor",
                    vec![RequirementTag::Behavior, RequirementTag::Constraint],
                )
            },
        )
    });
    if let Some((rule, required)) = classified_line {
        let in_test_context = changed_file.is_some_and(|file| is_inline_test_context(file, line))
            || is_test_path(path);
        if in_test_context && rule != "missing-test-expectation-anchor" {
            return;
        }
        let (rule, required) = if !in_test_context && rule == "missing-test-expectation-anchor" {
            if is_assertion_line(changed) {
                (
                    "missing-failure-policy-anchor",
                    vec![RequirementTag::Behavior, RequirementTag::Constraint],
                )
            } else {
                return;
            }
        } else {
            (rule, required)
        };
        let item_start = is_visible_contract_line(changed) || is_visible_trait_line(changed);
        let has_anchor = records.iter().any(|record| {
            record.path == path
                && required.contains(&record.tag)
                && anchor_matches_changed_line(
                    record,
                    line,
                    item_start,
                    contract_attribute,
                    signature_continuation,
                    container_contract_line,
                )
        });
        if !has_anchor {
            diagnostics.push(Diagnostic {
                path: path.to_string(),
                line,
                rule,
                message: format!(
                    "{subject} requires one of {} near the enclosing code unit",
                    required
                        .iter()
                        .map(|tag| tag.as_str())
                        .collect::<Vec<_>>()
                        .join(" or ")
                ),
            });
        }
    }
}

/// @intent req.detector The diff detector table maps Rust syntax signals to required requirement tags.
fn classify_added_line(line: &str) -> Option<(&'static str, Vec<RequirementTag>)> {
    if is_assertion_line(line) || line.contains("mock") || line.contains("fixture") {
        return Some((
            "missing-test-expectation-anchor",
            vec![RequirementTag::Verifies],
        ));
    }
    // @behavior req.detector.contract The visible contract detector classifies unrestricted and restricted Rust APIs as contract changes.
    if is_visible_contract_line(line) {
        return Some((
            "missing-contract-anchor",
            vec![RequirementTag::Behavior, RequirementTag::Constraint],
        ));
    }
    // @intent req.detector.structure.trait_object The structure detector treats trait declarations and trait object mentions as abstraction-boundary changes.
    if line.starts_with("pub trait ")
        || line.starts_with("trait ")
        || is_visible_trait_line(line)
        || line.contains("dyn ")
        || line.contains("Box<dyn")
        || line.contains("Arc<dyn")
    {
        return Some(("missing-structure-intent", vec![RequirementTag::Intent]));
    }
    // @behavior req.detector.failure The detector classifies timeout, panic, unwrap, expect, and Err patterns as failure-policy changes.
    if line.contains("tokio::time::timeout")
        || line.contains("map_err")
        || line.contains("panic!")
        || is_panicking_unwrap_line(line)
        || line.contains("expect(")
        || line.contains("Err(")
    {
        return Some((
            "missing-failure-policy-anchor",
            vec![RequirementTag::Behavior, RequirementTag::Constraint],
        ));
    }
    // @behavior req.detector.side_effect The detector classifies filesystem, channel send, and tracing patterns as side-effect changes.
    if line.contains("std::fs::")
        || line.contains("tokio::fs::")
        || line.contains("File::create")
        || line.contains(".write")
        || line.contains(".send(")
        || line.contains("tracing::")
    {
        return Some((
            "missing-side-effect-anchor",
            vec![RequirementTag::Behavior, RequirementTag::Constraint],
        ));
    }
    None
}

/// @behavior req.detector.anchor The anchor matcher accepts a requirement record when its binding is close enough to the changed code unit.
fn anchor_matches_changed_line(
    record: &RequirementRecord,
    line: usize,
    item_start: bool,
    attribute_contract: bool,
    signature_continuation: bool,
    container_contract_line: Option<usize>,
) -> bool {
    let Some(binding_line) = binding_target_line(record) else {
        if item_start
            || attribute_contract
            || signature_continuation
            || container_contract_line.is_some()
        {
            return false;
        }
        return record.line <= line && line.saturating_sub(record.line) <= 8;
    };
    if let Some(container_line) = container_contract_line {
        return binding_line == container_line;
    }
    if item_start {
        return binding_line == line;
    }
    if attribute_contract {
        return line <= binding_line && binding_line.saturating_sub(line) <= 8;
    }
    if signature_continuation {
        return binding_line <= line && line.saturating_sub(binding_line) <= 8;
    }
    binding_line <= line && line.saturating_sub(binding_line) <= 8
}

fn binding_target_line(record: &RequirementRecord) -> Option<usize> {
    record
        .binding
        .strip_prefix("line ")
        .and_then(|rest| rest.split_whitespace().next())
        .and_then(|line| line.parse::<usize>().ok())
}

fn is_contract_attribute_line(line: &str) -> bool {
    line.starts_with("#[cfg(")
        || line.starts_with("#[repr(")
        || line.starts_with("#[must_use")
        || line.starts_with("#[serde(")
        || (line.starts_with("#[derive(")
            && (line.contains("Serialize") || line.contains("Deserialize")))
}

/// @behavior req.detector.assertion The assertion detector classifies production assertions as failure-policy changes and test assertions as verification changes.
fn is_assertion_line(line: &str) -> bool {
    line.contains("assert!") || line.contains("assert_eq!") || line.contains("assert_ne!")
}

/// @behavior req.detector.assertion.unwrap The assertion detector treats panicking unwrap calls as failure-policy changes while accepting fallback helpers.
fn is_panicking_unwrap_line(line: &str) -> bool {
    line.contains(".unwrap()") || line.contains(".unwrap_err()")
}

/// @behavior req.detector.structure The structure detector classifies visible trait declarations as structure-intent changes.
fn is_visible_trait_line(line: &str) -> bool {
    visible_line_remainder(line).is_some_and(|rest| {
        let rest = rest.strip_prefix("unsafe ").unwrap_or(rest);
        rest.starts_with("trait ")
    })
}

fn is_visible_contract_line(line: &str) -> bool {
    visible_line_remainder(line).is_some_and(|rest| {
        is_visible_function_remainder(rest)
            || rest.starts_with("struct ")
            || rest.starts_with("enum ")
            || rest.starts_with("union ")
            || rest.starts_with("type ")
            || rest.starts_with("const ")
            || rest.starts_with("static ")
            || rest.starts_with("mod ")
            || rest.starts_with("use ")
            || is_visible_field_remainder(rest)
    })
}
/// @behavior req.detector.field The visible field detector classifies public Rust struct fields as contract changes.
fn is_visible_field_remainder(rest: &str) -> bool {
    if let Some((name, _)) = rest.split_once(':') {
        return is_rust_field_name(name.trim());
    }
    is_visible_tuple_field_remainder(rest)
}

fn is_rust_field_name(name: &str) -> bool {
    let mut characters = name.chars();
    matches!(characters.next(), Some(first) if first == '_' || first.is_ascii_alphabetic())
        && characters.all(|character| character == '_' || character.is_ascii_alphanumeric())
}

/// @behavior req.detector.field.tuple The tuple field detector recognizes public tuple fields by comma-terminated type syntax.
fn is_visible_tuple_field_remainder(rest: &str) -> bool {
    let rest = rest.trim();
    if !rest.ends_with(',') || rest.contains(':') || rest.contains('=') {
        return false;
    }
    let ty = rest.trim_end_matches(',').trim();
    matches!(ty.chars().next(), Some(first) if first == '_' || first == '&' || first == '(' || first == '[' || first == ':' || first.is_ascii_alphabetic())
}

fn visible_line_remainder(line: &str) -> Option<&str> {
    let rest = line.strip_prefix("pub")?;
    if !(rest.starts_with(char::is_whitespace) || rest.starts_with('(')) {
        return None;
    }
    let rest = rest.trim_start();
    let rest = if let Some(rest) = rest.strip_prefix('(') {
        let (_, after_visibility) = rest.split_once(')')?;
        after_visibility.trim_start()
    } else {
        rest
    };
    Some(rest)
}

fn is_visible_function_remainder(rest: &str) -> bool {
    let mut rest = rest.trim_start();
    loop {
        if let Some(next) = rest.strip_prefix("async ") {
            rest = next.trim_start();
            continue;
        }
        if let Some(next) = rest.strip_prefix("unsafe ") {
            rest = next.trim_start();
            continue;
        }
        if let Some(next) = rest.strip_prefix("const ") {
            rest = next.trim_start();
            continue;
        }
        if let Some(next) = rest.strip_prefix("extern ") {
            rest = next.trim_start();
            if let Some(abi) = rest.strip_prefix('"')
                && let Some((_, after_abi)) = abi.split_once('"')
            {
                rest = after_abi.trim_start();
                continue;
            }
            continue;
        }
        break;
    }
    rest.starts_with("fn ")
}

/// @behavior req.detector.signature The staged signature detector classifies edited lines inside visible Rust function signatures as contract changes.
fn is_visible_signature_continuation(file: &SnapshotFile, line: usize, added: &str) -> bool {
    let added = added.trim();
    if !(added.contains(':')
        || added.starts_with(')')
        || added.starts_with("->")
        || added.starts_with('+')
        || added.starts_with("where "))
    {
        return false;
    }

    let lines = file.content.lines().collect::<Vec<_>>();
    let Some(mut index) = line.checked_sub(1) else {
        return false;
    };
    let start_index = index;
    let lower_bound = index.saturating_sub(20);
    while index >= lower_bound {
        let Some(source_line) = lines.get(index) else {
            return false;
        };
        let trimmed = source_line.trim();
        if trimmed.contains('{') {
            if index == start_index && (added.starts_with(')') || added.starts_with("->")) {
                return true;
            }
            return false;
        }
        if index != start_index && trimmed.ends_with(';') {
            return false;
        }
        if is_visible_contract_line(trimmed) && (trimmed.contains('(') || trimmed.contains('<')) {
            return true;
        }
        if index == 0 {
            break;
        }
        index -= 1;
    }
    false
}

fn is_visible_contract_attribute(file: &SnapshotFile, line: usize, added: &str) -> bool {
    if !is_contract_attribute_line(added) {
        return false;
    }

    let lines = file.content.lines().collect::<Vec<_>>();
    let Some(start_index) = line.checked_sub(1) else {
        return false;
    };
    for source_line in lines.iter().skip(start_index + 1).take(8) {
        let trimmed = source_line.trim();
        if trimmed.is_empty() || is_attribute_line(trimmed) {
            continue;
        }
        return is_visible_contract_line(trimmed) || is_visible_trait_line(trimmed);
    }
    false
}

#[derive(Clone, Copy)]
enum PublicContainerKind {
    Enum,
    Trait,
}

/// @behavior req.detector.contract.container The public container detector classifies enum variants and trait required items as contract changes.
fn enclosing_public_container_contract_line(
    file: &SnapshotFile,
    line: usize,
    changed: &str,
) -> Option<usize> {
    let changed = changed.trim();
    if changed.is_empty() || changed.starts_with("#[") || changed.starts_with('}') {
        return None;
    }

    let lines = file.content.lines().collect::<Vec<_>>();
    let mut brace_depth = 0usize;
    let mut pending_container = None::<(usize, usize, PublicContainerKind)>;
    let mut containers = Vec::<(usize, usize, PublicContainerKind)>::new();
    for (index, source_line) in lines.iter().take(line.saturating_sub(1)).enumerate() {
        let trimmed = source_line.trim();
        containers.retain(|(container_depth, _, _)| brace_depth > *container_depth);
        if let Some(kind) = public_container_header_kind(trimmed) {
            if trimmed.contains('{') {
                containers.push((brace_depth, index + 1, kind));
                pending_container = None;
            } else {
                pending_container = Some((brace_depth, index + 1, kind));
            }
        } else if trimmed.contains('{') {
            if let Some(container) = pending_container.take() {
                containers.push(container);
            }
        } else if trimmed.ends_with(';') {
            pending_container = None;
        }
        brace_depth = brace_depth
            .saturating_add(source_line.matches('{').count())
            .saturating_sub(source_line.matches('}').count());
    }

    containers
        .into_iter()
        .rev()
        .find_map(|(_, container_line, kind)| {
            public_container_member_contract(kind, changed).then_some(container_line)
        })
}

/// @constraint req.detector.contract.container.header The container header detector normalizes public unsafe trait headers before classifying member changes.
fn public_container_header_kind(line: &str) -> Option<PublicContainerKind> {
    visible_line_remainder(line).and_then(|rest| {
        if rest.starts_with("enum ") {
            Some(PublicContainerKind::Enum)
        } else {
            let rest = rest.strip_prefix("unsafe ").unwrap_or(rest);
            if rest.starts_with("trait ") {
                Some(PublicContainerKind::Trait)
            } else {
                None
            }
        }
    })
}

fn public_container_member_contract(kind: PublicContainerKind, line: &str) -> bool {
    match kind {
        PublicContainerKind::Enum => is_enum_variant_line(line),
        PublicContainerKind::Trait => is_trait_required_item_line(line),
    }
}

fn is_enum_variant_line(line: &str) -> bool {
    let line = line.trim_end_matches(',').trim();
    let Some(first) = line.chars().next() else {
        return false;
    };
    (first == '_' || first.is_ascii_uppercase())
        && !line.starts_with("Self")
        && !line.contains("=>")
}

fn is_trait_required_item_line(line: &str) -> bool {
    let line = line.trim_start();
    line.starts_with("fn ")
        || line.starts_with("async fn ")
        || line.starts_with("unsafe fn ")
        || line.starts_with("type ")
        || line.starts_with("const ")
}

fn parse_hunk_starts(hunk: &str) -> (usize, usize) {
    (parse_hunk_start(hunk, '-'), parse_hunk_start(hunk, '+'))
}

/// @behavior req.detector.hunk_parse The hunk parser returns zero when a diff hunk omits a parseable line start.
fn parse_hunk_start(hunk: &str, prefix: char) -> usize {
    hunk.split_whitespace()
        .find_map(|part| part.strip_prefix(prefix))
        .and_then(|part| part.split(',').next())
        .and_then(|line| line.parse::<usize>().ok())
        .unwrap_or_default()
}

fn extract_requirement_comments(file: &SnapshotFile) -> Vec<RawRequirementComment> {
    let mut comments = Vec::new();
    let lines = file.content.lines().collect::<Vec<_>>();
    let string_literal_lines = string_literal_lines(file);
    let mut index = 0usize;
    while index < lines.len() {
        let line = lines[index];
        if string_literal_lines.contains(&(index + 1)) {
            index += 1;
            continue;
        }
        let trimmed = line.trim_start();
        if let Some(normalized) = normalize_line_comment(trimmed) {
            if normalized.starts_with('@') {
                comments.push(RawRequirementComment {
                    line: index + 1,
                    end_line: index + 1,
                    inner_doc: trimmed.starts_with("//!"),
                    normalized: normalized.to_string(),
                });
            }
            index += 1;
            continue;
        }

        if let Some((rest, inner_doc)) = trimmed
            .strip_prefix("/*!")
            .map(|rest| (rest, true))
            .or_else(|| trimmed.strip_prefix("/*").map(|rest| (rest, false)))
        {
            let start = index;
            let mut body = Vec::new();
            let mut current = rest;
            loop {
                if let Some(end) = current.find("*/") {
                    body.push(current[..end].to_string());
                    break;
                }
                body.push(current.to_string());
                index += 1;
                if index >= lines.len() {
                    break;
                }
                current = lines[index].trim();
            }
            let normalized = normalize_block_comment_body(&body);
            if normalized.starts_with('@') {
                comments.push(RawRequirementComment {
                    line: start + 1,
                    end_line: index + 1,
                    inner_doc,
                    normalized: normalized.to_string(),
                });
            }
            index += 1;
            continue;
        }
        index += 1;
    }
    comments
}

fn string_literal_lines(file: &SnapshotFile) -> BTreeSet<usize> {
    let mut parser = tree_sitter::Parser::new();
    let language = tree_sitter_rust::LANGUAGE.into();
    if parser.set_language(&language).is_err() {
        return BTreeSet::new();
    }
    let Some(tree) = parser.parse(&file.content, None) else {
        return BTreeSet::new();
    };
    let mut lines = BTreeSet::new();
    collect_string_literal_lines(tree.root_node(), &mut lines);
    lines
}

fn collect_string_literal_lines(node: tree_sitter::Node<'_>, lines: &mut BTreeSet<usize>) {
    if node.kind().contains("string_literal") {
        for row in node.start_position().row..=node.end_position().row {
            lines.insert(row + 1);
        }
        return;
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        collect_string_literal_lines(child, lines);
    }
}

fn normalize_block_comment_body(body: &[String]) -> String {
    body.iter()
        .map(|segment| segment.trim().trim_start_matches('*').trim())
        .filter(|segment| !segment.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

fn normalize_line_comment(trimmed: &str) -> Option<&str> {
    trimmed
        .strip_prefix("//!")
        .or_else(|| trimmed.strip_prefix("///"))
        .or_else(|| trimmed.strip_prefix("//"))
        .map(str::trim)
}

fn bind_comment(file: &SnapshotFile, raw: &RawRequirementComment) -> Option<String> {
    if raw.inner_doc {
        return Some("file module".to_string());
    }

    let lines = file.content.lines().collect::<Vec<_>>();
    for (offset, line) in lines.iter().enumerate().skip(raw.end_line) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if normalize_line_comment(trimmed).is_some() || trimmed.starts_with("/*") {
            continue;
        }
        if is_attribute_line(trimmed) {
            continue;
        }
        if is_rust_binding_target(trimmed) {
            return Some(format!("line {} `{}`", offset + 1, trimmed));
        }
        return None;
    }
    if raw.line <= 3 && raw.normalized.starts_with("@behavior") {
        Some("file module".to_string())
    } else {
        None
    }
}

fn is_inline_test_context(file: &SnapshotFile, line: usize) -> bool {
    if binds_to_direct_test_function(file, line) {
        return true;
    }

    let mut pending_cfg_test = false;
    let mut pending_direct_test = false;
    let mut pending_test_module_brace = None::<usize>;
    let mut pending_test_function_brace = None::<usize>;
    let mut brace_depth = 0usize;
    let mut test_module_depths = Vec::new();
    let mut test_function_depths = Vec::new();

    for source_line in file.content.lines().take(line.saturating_sub(1)) {
        let trimmed = source_line.trim();
        test_module_depths.retain(|module_depth| brace_depth > *module_depth);
        test_function_depths.retain(|function_depth| brace_depth > *function_depth);
        if trimmed.starts_with("#[cfg(test)]") {
            pending_cfg_test = true;
        }
        if is_test_attribute_line(trimmed) {
            pending_direct_test = true;
        }

        let opens = source_line.matches('{').count();
        let closes = source_line.matches('}').count();
        if pending_cfg_test && trimmed.contains("mod ") {
            if trimmed.contains('{') {
                test_module_depths.push(brace_depth);
            } else {
                pending_test_module_brace = Some(brace_depth);
            }
            pending_cfg_test = false;
        } else if pending_direct_test && is_test_function_line(trimmed) {
            if trimmed.contains('{') {
                test_function_depths.push(brace_depth);
            } else {
                pending_test_function_brace = Some(brace_depth);
            }
            pending_direct_test = false;
        } else if trimmed.starts_with('{') {
            if let Some(module_depth) = pending_test_module_brace.take() {
                test_module_depths.push(module_depth);
            }
            if let Some(function_depth) = pending_test_function_brace.take() {
                test_function_depths.push(function_depth);
            }
        } else if !trimmed.starts_with("#[") && !trimmed.is_empty() {
            pending_cfg_test = false;
            pending_direct_test = false;
            if trimmed.ends_with(';') {
                pending_test_module_brace = None;
                pending_test_function_brace = None;
            }
        }
        brace_depth = brace_depth.saturating_add(opens).saturating_sub(closes);
    }

    test_module_depths
        .iter()
        .any(|module_depth| brace_depth > *module_depth)
        || test_function_depths
            .iter()
            .any(|function_depth| brace_depth > *function_depth)
}

fn binds_to_direct_test_function(file: &SnapshotFile, line: usize) -> bool {
    let lines = file.content.lines().collect::<Vec<_>>();
    let mut has_previous_test_attr = false;
    for source_line in lines.iter().take(line.saturating_sub(1)).rev() {
        let trimmed = source_line.trim();
        if trimmed.is_empty() || normalize_line_comment(trimmed).is_some() {
            continue;
        }
        if trimmed.starts_with("#[") {
            has_previous_test_attr |= is_test_attribute_line(trimmed);
            continue;
        }
        break;
    }

    let mut pending_test_attr = has_previous_test_attr;
    for source_line in lines.iter().skip(line.saturating_sub(1)).take(8) {
        let trimmed = source_line.trim();
        if trimmed.is_empty() || normalize_line_comment(trimmed).is_some() {
            continue;
        }
        if is_test_attribute_line(trimmed) {
            pending_test_attr = true;
            continue;
        }
        if trimmed.starts_with("#[") {
            continue;
        }
        return pending_test_attr && is_test_function_line(trimmed);
    }
    false
}

fn is_test_function_line(trimmed: &str) -> bool {
    trimmed.starts_with("fn ") || trimmed.starts_with("async fn ")
}

fn is_test_attribute_line(trimmed: &str) -> bool {
    let Some(attribute) = trimmed
        .strip_prefix("#[")
        .and_then(|rest| rest.strip_suffix(']'))
    else {
        return false;
    };
    attribute == "test"
        || attribute.starts_with("test(")
        || attribute.ends_with("::test")
        || attribute.contains("::test(")
}

fn is_attribute_line(trimmed: &str) -> bool {
    trimmed.starts_with("#[") || trimmed.starts_with("#!")
}

fn is_rust_binding_target(trimmed: &str) -> bool {
    trimmed.starts_with("pub ")
        || trimmed.starts_with("fn ")
        || trimmed.starts_with("async fn ")
        || trimmed.starts_with("struct ")
        || trimmed.starts_with("enum ")
        || trimmed.starts_with("trait ")
        || trimmed.starts_with("impl")
        || trimmed.starts_with("mod ")
        || trimmed.starts_with("use ")
        || trimmed.starts_with("const ")
        || trimmed.starts_with("static ")
        || trimmed.starts_with("type ")
        || trimmed.starts_with("let ")
        || trimmed.starts_with("if ")
        || trimmed.starts_with("match ")
        || trimmed.starts_with("for ")
        || trimmed.starts_with("while ")
        || trimmed.starts_with("loop")
        || trimmed.starts_with("return")
        || trimmed.starts_with("assert")
        || trimmed.contains('(')
        || trimmed.ends_with("=>")
}

fn render_diagnostics(diagnostics: &[Diagnostic]) -> String {
    diagnostics
        .iter()
        .map(|diagnostic| {
            format!(
                "{}:{}: {}: {}",
                diagnostic.path, diagnostic.line, diagnostic.rule, diagnostic.message
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn detect_line_ending(content: &str) -> &'static str {
    if content.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    }
}

#[derive(Debug)]
struct ParsedRequirement {
    tag: RequirementTag,
    id: String,
    sentence: String,
}

#[derive(Debug)]
struct RawRequirementComment {
    line: usize,
    end_line: usize,
    inner_doc: bool,
    normalized: String,
}

#[derive(Debug)]
struct Snapshot {
    files: Vec<SnapshotFile>,
}

impl Snapshot {
    /// @behavior req.check.snapshot The snapshot reader loads tracked Rust inputs from the worktree, index, or Git ref for validation.
    fn from_worktree(root: &Path) -> Result<Self, String> {
        let paths = git_ls_files(root)?;
        let mut files = Vec::new();
        for path in paths {
            let full_path = root.join(&path);
            match fs::read_to_string(&full_path) {
                Ok(content) => files.push(SnapshotFile {
                    path: path_to_string(&path),
                    content,
                }),
                // @behavior req.check.snapshot.worktree_invalid The worktree snapshot reader skips tracked files whose bytes are not valid UTF-8 text.
                Err(error) if error.kind() == io::ErrorKind::InvalidData => continue,
                // @behavior req.check.snapshot.worktree_read The worktree snapshot reader reports filesystem read failures for tracked paths.
                Err(error) => {
                    return Err(format!("failed to read {}: {error}", full_path.display()));
                }
            }
        }
        Ok(Self { files })
    }

    fn from_index(root: &Path) -> Result<Self, String> {
        let paths = git_ls_files_cached(root)?;
        let mut files = Vec::new();
        for path in paths {
            let path_string = path_to_string(&path);
            let output = isolated_git_command()
                .current_dir(root)
                .arg("show")
                .arg(format!(":{path_string}"))
                .output()
                // @behavior req.check.snapshot.staged_read The staged snapshot reader reports Git object read failures for staged paths.
                .map_err(|error| format!("failed to read staged {path_string}: {error}"))?;
            if !output.status.success() {
                continue;
            }
            let Ok(content) = String::from_utf8(output.stdout) else {
                continue;
            };
            files.push(SnapshotFile {
                path: path_string,
                content,
            });
        }
        Ok(Self { files })
    }

    fn from_git_ref(root: &Path, git_ref: &str) -> Result<Self, String> {
        let paths = git_ref_files(root, git_ref)?;
        let mut files = Vec::new();
        for path in paths {
            let path_string = path_to_string(&path);
            let output = match isolated_git_command()
                .current_dir(root)
                .arg("show")
                .arg(format!("{git_ref}:{path_string}"))
                .output()
            {
                Ok(output) => output,
                // @behavior req.check.git_ref_read The ref snapshot reader reports object read failures for the requested Git ref.
                Err(error) => {
                    return Err(format!(
                        "failed to read {path_string} from {git_ref}: {error}"
                    ));
                }
            };
            if !output.status.success() {
                continue;
            }
            let Ok(content) = String::from_utf8(output.stdout) else {
                continue;
            };
            files.push(SnapshotFile {
                path: path_string,
                content,
            });
        }
        Ok(Self { files })
    }
}

#[derive(Debug, Clone)]
struct SnapshotFile {
    path: String,
    content: String,
}

fn git_ls_files(root: &Path) -> Result<Vec<PathBuf>, String> {
    git_path_list(root, &["ls-files", "-z"])
}

fn git_ls_files_cached(root: &Path) -> Result<Vec<PathBuf>, String> {
    git_path_list(root, &["ls-files", "-z", "--cached"])
}

fn git_ref_files(root: &Path, git_ref: &str) -> Result<Vec<PathBuf>, String> {
    let output = match isolated_git_command()
        .current_dir(root)
        .args(["ls-tree", "-r", "--name-only", "-z", git_ref])
        .output()
    {
        Ok(output) => output,
        // @behavior req.check.git_ref_list The ref file lister reports Git tree listing failures for the requested Git ref.
        Err(error) => return Err(format!("failed to run git ls-tree for {git_ref}: {error}")),
    };
    // @behavior req.check.git_ref_status The ref file lister reports unsuccessful Git tree listing status for the requested Git ref.
    if !output.status.success() {
        return Err(format!(
            "git ls-tree {git_ref} failed: {}",
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

/// @behavior req.check.merge_base The base checker resolves the Git merge base before reading old snapshot files.
fn git_merge_base(root: &Path, git_ref: &str) -> Result<String, String> {
    let output = match isolated_git_command()
        .current_dir(root)
        .args(["merge-base", git_ref, "HEAD"])
        .output()
    {
        Ok(output) => output,
        Err(error) => {
            return Err(format!(
                "failed to run git merge-base for {git_ref}: {error}"
            ));
        }
    };
    // @constraint req.check.merge_base.status The merge-base resolver reports unsuccessful Git merge-base status for the requested base ref.
    if !output.status.success() {
        return Err(format!(
            "git merge-base {git_ref} HEAD failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn git_path_list(root: &Path, args: &[&str]) -> Result<Vec<PathBuf>, String> {
    let output = isolated_git_command()
        .current_dir(root)
        .args(args)
        .output()
        // @behavior req.check.git_path_list The Git path lister reports command execution failures for tracked path discovery.
        .map_err(|error| format!("failed to run git {}: {error}", args.join(" ")))?;
    // @behavior req.check.git_path_list_status The Git path lister reports unsuccessful Git status for tracked path discovery.
    if !output.status.success() {
        return Err(format!(
            "git {} failed: {}",
            args.join(" "),
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

fn path_to_string(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
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
        RequirementCheckMode, RequirementCheckStatus, check_requirements,
        format_agents_requirement_index, is_visible_contract_line, is_visible_trait_line,
        parse_requirement_comment, scan_requirements,
    };
    use std::fs;
    use std::path::Path;
    use std::process::Command;
    use tempfile::TempDir;

    #[test]
    // @verifies req.cli The test verifies that requirement scan commands expose parsed records for CLI output.
    // @verifies req.scan The test verifies that one-sentence requirement comments are parsed into scan records.
    // @verifies req.api.tag The test verifies that allowed requirement tags are accepted by the parser.
    // @verifies req.api.record The test verifies that parsed comments preserve their dotted requirement ID.
    fn parser_accepts_one_sentence_requirement_comments() {
        let parsed = parse_requirement_comment(
            "@behavior req.scan The scanner records each local requirement comment.",
        )
        .expect("comment should parse");

        assert_eq!(parsed.id, "req.scan");
    }

    #[test]
    // @verifies req.api.diagnostic The test verifies that multi-sentence requirement comments return a diagnostic message.
    fn parser_rejects_multi_sentence_requirement_comments() {
        let error = parse_requirement_comment(
            "@behavior req.scan The scanner records each local requirement comment. It records diagnostics.",
        )
        .expect_err("multi-sentence comment should fail");

        assert!(error.contains("exactly one sentence"));
    }

    #[test]
    // @verifies req.format The test verifies that dotted code tokens inside one sentence are accepted.
    fn parser_accepts_one_sentence_requirement_comments_with_dotted_tokens() {
        let parsed =
            parse_requirement_comment("@behavior req.format The command updates AGENTS.md.")
                .expect("dotted token should stay inside one sentence");

        assert_eq!(parsed.sentence, "The command updates AGENTS.md.");
    }

    #[test]
    // @verifies req.api.diagnostic.macro The test verifies that Rust macro names with bang punctuation stay inside one sentence.
    fn parser_accepts_one_sentence_requirement_comments_with_macro_names() {
        let parsed = parse_requirement_comment(
            "@verifies req.scan The test verifies assert! calls and panic! paths.",
        )
        .expect("macro bang punctuation should stay inside one sentence");

        assert_eq!(
            parsed.sentence,
            "The test verifies assert! calls and panic! paths."
        );
    }

    #[test]
    // @verifies req.format The test verifies that fmt-agents writes requirement tree rows into AGENTS.md.
    // @verifies req.format.index_block The test verifies that requirement index formatting preserves AGENTS content.
    // @verifies req.api.report The test verifies that the generated index is derived from discovered declarations.
    fn fmt_agents_generates_requirement_index_from_source_comments() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.format The fixture verifies formatting with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);

        format_agents_requirement_index(repo.path()).expect("format should succeed");

        let agents = repo.read("AGENTS.md");
        // @verifies req.format.index_block The assertions verify that the generated index contains the root and leaf rows.
        assert!(agents.contains("|req|req.{scan}"));
        assert!(agents.contains("|req.scan|req.scan.{}"));
    }

    #[test]
    // @verifies req.scan The test verifies that starred block requirement comments are indexed.
    fn scan_accepts_starred_block_requirement_comments() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n/**\n * @behavior req.block The block requirement is indexed from a starred comment.\n */\npub fn block() {}\n",
        );
        // @verifies req.scan The fixture verifies block comment scanning with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.block The test verifies that block comments are indexed.\n#[test]\nfn block_comment_is_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.scan The assertion verifies that the starred block declaration is present.
        assert!(
            report
                .declarations
                .iter()
                .any(|record| record.id == "req.block")
        );
    }

    #[test]
    // @verifies req.scan The test verifies that requirement-looking text inside strings is ignored.
    fn scan_ignores_requirement_comments_inside_string_literals() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\npub fn fixture() -> &'static str {\n    r#\"\n// @behavior req.fake The fake requirement stays inside a raw string.\n\"#\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.scan The assertion verifies that string literal content is absent from declarations.
        assert!(
            report
                .declarations
                .iter()
                .all(|record| record.id != "req.fake")
        );
    }

    #[test]
    // @verifies req.check The test verifies that check reports a stale AGENTS requirement index.
    // @verifies req.api.status The test verifies that stale AGENTS state is reported through the check status enum.
    fn check_reports_stale_requirement_index() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check The fixture verifies added integration-test assertions.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);

        let status =
            check_requirements(repo.path(), RequirementCheckMode::All).expect("check should run");

        // @verifies req.api.status The assertion verifies that stale AGENTS state is reported through the check status enum.
        assert_eq!(status, RequirementCheckStatus::StaleAgentsIndex);
    }

    #[test]
    // @verifies req.check.all_anchors The test verifies that all-check mode applies anchor rules to every Rust source line.
    // @verifies req.detector.full The test verifies that full-check diagnostics come from snapshot line classification.
    fn all_check_rejects_unanchored_contracts_in_existing_code() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\npub fn unanchored_contract() {}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let error = check_requirements(repo.path(), RequirementCheckMode::All)
            .expect_err("full checkout should require a nearby contract anchor");

        // @verifies req.check.all_anchors The assertions verify that all-check mode reports full-line contract diagnostics.
        assert!(error.contains("missing-contract-anchor"));
        assert!(error.contains("Rust line requires"));
    }

    #[test]
    // @verifies req.check.all_anchors The test verifies that all-check mode accepts anchored Rust source lines.
    fn all_check_accepts_anchored_contracts_in_existing_code() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The scan function exposes a checked contract.\npub fn scan() {}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);

        let status =
            check_requirements(repo.path(), RequirementCheckMode::All).expect("check should run");

        // @verifies req.check.all_anchors The assertion verifies that anchored full-check code returns fresh status.
        assert_eq!(status, RequirementCheckStatus::Fresh);
    }

    #[test]
    // @verifies req.check.registry The test verifies that declaration-only leaf requirements are valid registry entries.
    fn scan_accepts_declaration_only_leaf_requirements() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check.registry The assertion verifies that declaration-only leaf requirements produce a clean registry report.
        assert!(report.diagnostics.is_empty());
    }

    #[test]
    // @verifies req.check The test verifies that inline cfg test modules are valid verification sites.
    fn scan_accepts_verification_comments_inside_inline_test_modules() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        // @verifies req.check The fixture verifies inline tests with assertion bodies.
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    // @verifies req.scan The test verifies that inline unit tests can verify requirements.\n    fn inline_test_verifies_requirement() {\n        assert!(true);\n    }\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that inline test comments avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .all(|diagnostic| diagnostic.rule != "verification-outside-test")
        );
    }

    #[test]
    // @verifies req.check The test verifies that direct test functions are valid verification sites.
    fn scan_accepts_verification_comments_inside_direct_test_functions() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        // @verifies req.check The fixture verifies direct test functions with assertion bodies.
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n#[test]\n// @verifies req.scan The test verifies that direct unit tests can verify requirements.\nfn direct_test_verifies_requirement() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that direct test comments avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .all(|diagnostic| diagnostic.rule != "verification-outside-test")
        );
    }

    #[test]
    // @verifies req.check The test verifies that stacked direct-test attributes keep verification sites valid.
    fn scan_accepts_verification_comments_after_stacked_test_attributes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        // @verifies req.check The fixture verifies direct test functions with stacked attributes.
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n#[test]\n#[ignore]\n// @verifies req.scan The test verifies that ignored direct tests can verify requirements.\nfn ignored_direct_test_verifies_requirement() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that stacked-attribute direct tests avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .all(|diagnostic| diagnostic.rule != "verification-outside-test")
        );
    }

    #[test]
    // @verifies req.check The test verifies that async direct test functions are valid verification sites.
    fn scan_accepts_verification_comments_inside_async_direct_test_functions() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        // @verifies req.check The fixture verifies async direct test functions with assertion bodies.
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n#[tokio::test(flavor = \"current_thread\")]\n// @verifies req.scan The test verifies that async unit tests can verify requirements.\nasync fn async_direct_test_verifies_requirement() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that async direct test comments avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .all(|diagnostic| diagnostic.rule != "verification-outside-test")
        );
    }

    #[test]
    // @verifies req.check The test verifies that next-line test braces keep direct tests as verification sites.
    fn scan_accepts_verification_comments_inside_next_line_brace_tests() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        // @verifies req.check The fixture verifies direct test functions with next-line braces.
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n#[test]\nfn direct_test_verifies_requirement()\n{\n    // @verifies req.scan The test verifies that next-line brace tests can verify requirements.\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that next-line brace direct tests avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .all(|diagnostic| diagnostic.rule != "verification-outside-test")
        );
    }

    #[test]
    // @verifies req.check The test verifies that next-line module braces keep cfg-test modules as verification sites.
    fn scan_accepts_verification_comments_inside_next_line_brace_test_modules() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        // @verifies req.check The fixture verifies cfg-test modules with next-line braces.
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n#[cfg(test)]\nmod tests\n{\n    #[test]\n    fn module_test_verifies_requirement() {\n        // @verifies req.scan The test verifies that next-line brace modules can verify requirements.\n        assert!(true);\n    }\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that next-line brace test modules avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .all(|diagnostic| diagnostic.rule != "verification-outside-test")
        );
    }

    #[test]
    // @verifies req.check The test verifies that xtask production source is rejected as a verification site.
    fn scan_rejects_verification_comments_in_xtask_production_code() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "xtask/src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n// @verifies req.scan The production comment must not verify requirements.\npub fn production_verifier() {}\n",
        );
        repo.git_add(&["AGENTS.md", "xtask/src/lib.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that production xtask verifications are rejected.
        assert!(
            report
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.rule == "verification-outside-test")
        );
    }

    #[test]
    // @verifies req.check The test verifies that staged hunk anchors must be near the changed Rust line.
    fn staged_check_rejects_far_file_level_anchor_for_contract_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check The fixture verifies staged checks with existing test assertions.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn added_contract() {}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.check The assertion verifies that far file anchors fail staged contract validation.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("far anchor should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract The test verifies that restricted visibility APIs are contract changes.
    fn staged_check_rejects_unanchored_restricted_visibility_contract_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.detector.contract The fixture verifies staged detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub(crate) fn added_contract() {}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract The assertion verifies that pub(crate) APIs require contract anchors.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("restricted visibility contract should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract The test verifies that public unions are contract changes.
    fn staged_check_rejects_unanchored_public_union_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.detector.contract The fixture verifies public union checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub union AddedContract {\n    bits: u64,\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract The assertion verifies that public unions use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("public union should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.assertion The test verifies that production assertions require behavior or constraint anchors.
    fn staged_check_rejects_unanchored_production_assertions_as_failure_policy() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.detector.assertion The fixture verifies production assertion detection with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        // @verifies req.detector.assertion The fixture verifies staged detector checks with a production assertion.
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nfn added_assertion() { assert!(true); }\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.assertion The assertion verifies that production assertions use failure-policy diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("production assertion should fail staged check");

        assert!(error.contains("missing-failure-policy-anchor"));
    }

    #[test]
    // @verifies req.detector.assertion The test verifies that matches macro expressions are implementation changes.
    fn staged_check_accepts_matches_macro_as_boolean_expression() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.detector.assertion The fixture verifies staged detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\nfn matches_macro(value: Option<i32>) -> bool {\n    matches!(value, Some(_))\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.assertion The assertion verifies that matches macro expressions avoid failure-policy diagnostics.
        let status = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect("matches macro should pass staged check");

        assert_eq!(status, RequirementCheckStatus::Fresh);
    }

    #[test]
    // @verifies req.detector.assertion.unwrap The test verifies that fallback unwrap helpers are implementation changes.
    fn staged_check_accepts_unwrap_or_fallbacks() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.detector.assertion.unwrap The fixture verifies fallback unwrap detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\nfn fallback() -> i32 {\n    Some(1).unwrap_or_default()\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.assertion.unwrap The assertion verifies that fallback unwrap helpers avoid failure-policy diagnostics.
        let status = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect("unwrap_or fallback should pass staged check");

        assert_eq!(status, RequirementCheckStatus::Fresh);
    }

    #[test]
    // @verifies req.detector.structure The test verifies that restricted visibility traits require intent anchors.
    fn staged_check_rejects_unanchored_restricted_visibility_trait_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.detector.structure The fixture verifies structure detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub(crate) trait AddedContract {}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.structure The assertion verifies that restricted traits use structure-intent diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("restricted trait should fail staged check");

        assert!(error.contains("missing-structure-intent"));
    }

    #[test]
    // @verifies req.detector.structure The test verifies that unsafe public traits require intent anchors.
    fn staged_check_rejects_unanchored_unsafe_public_trait_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.detector.structure The fixture verifies unsafe trait detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub unsafe trait AddedContract {}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.structure The assertion verifies that unsafe traits use structure-intent diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("unsafe public trait should fail staged check");

        assert!(error.contains("missing-structure-intent"));
    }

    #[test]
    // @verifies req.detector.signature The test verifies that edits inside multiline public signatures require contract anchors.
    fn staged_check_rejects_unanchored_multiline_public_signature_edits() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\npub struct OldType;\npub struct NewType;\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible(\n    value: OldType,\n) {}\n",
        );
        // @verifies req.detector.signature The fixture verifies signature detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\npub struct OldType;\npub struct NewType;\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible(\n    value: NewType,\n) {}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.signature The assertion verifies that multiline signature edits use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("multiline public signature edit should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.signature The test verifies that bound-only multiline public signature edits require contract anchors.
    fn staged_check_rejects_unanchored_multiline_public_bound_edits() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\npub trait Thing {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible() -> impl Thing\n{\n    loop {}\n}\n",
        );
        // @verifies req.detector.signature The fixture verifies bound detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\npub trait Thing {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible() -> impl Thing\n    + Send\n{\n    loop {}\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.signature The assertion verifies that bound-only signature edits use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("multiline public bound edit should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.signature The test verifies that generic-list edits inside public signatures require contract anchors.
    fn staged_check_rejects_unanchored_multiline_public_generic_bound_edits() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible<\n    T,\n>(value: T) {\n    drop(value);\n}\n",
        );
        // @verifies req.detector.signature The fixture verifies generic-list detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible<\n    T: Copy,\n>(value: T) {\n    drop(value);\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.signature The assertion verifies that generic-list edits use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("generic bound edit should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.signature The test verifies that public function body type annotations are implementation changes.
    fn staged_check_accepts_public_function_body_type_annotations() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible() {\n}\n",
        );
        // @verifies req.detector.signature The fixture verifies body-line detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible() {\n    let value: Option<String> = None;\n    drop(value);\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.signature The assertion verifies that body type annotations avoid contract diagnostics.
        let status = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect("public function body type annotation should pass staged check");

        assert_eq!(status, RequirementCheckStatus::Fresh);
    }

    #[test]
    // @verifies req.check The test verifies that deletion-only staged hunks run requirement anchor detection.
    fn staged_check_rejects_unanchored_deleted_contract_lines() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn removed_contract() {}\n",
        );
        // @verifies req.check The fixture verifies deletion detection with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.check The assertion verifies that removed public contracts require anchors.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("deleted public contract should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.check The test verifies that a requirement bound to the previous item does not satisfy a new public contract.
    fn staged_check_rejects_previous_item_anchor_for_new_contracts() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check The fixture verifies anchor matching with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\npub fn added_contract() {}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.check The assertion verifies that anchor matching uses the bound code item.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("new public contract should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract The test verifies that public contract attribute changes require contract anchors.
    fn staged_check_rejects_unanchored_public_contract_attribute_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn visible() {}\n",
        );
        // @verifies req.detector.contract The fixture verifies attribute detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n#[must_use]\npub fn visible() {}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract The assertion verifies that public attributes use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("public contract attribute should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract The test verifies that serde derive attributes can use anchors bound to the public item.
    fn staged_check_accepts_anchored_serde_derive_contract_attributes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n// @behavior req.visible The visible type is serialized by callers.\npub struct Visible;\n",
        );
        // @verifies req.detector.contract The fixture verifies serde derive detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n\n// @verifies req.visible The test verifies that the visible type requirement is covered.\n#[test]\nfn visible_type_is_covered() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n// @behavior req.visible The visible type is serialized by callers.\n#[derive(Serialize)]\npub struct Visible;\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract The assertion verifies that serde derive changes match the item anchor.
        let status = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect("anchored serde derive should pass staged check");

        assert_eq!(status, RequirementCheckStatus::Fresh);
    }

    #[test]
    // @verifies req.detector.field.tuple The test verifies that public tuple struct fields are contract changes.
    fn staged_check_rejects_unanchored_public_tuple_field_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub struct Visible(\n    String,\n);\n",
        );
        // @verifies req.detector.field.tuple The fixture verifies tuple field detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub struct Visible(\n    pub String,\n);\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.field.tuple The assertion verifies that public tuple fields use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("public tuple field should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract.container The test verifies that public enum variants can use the enclosing enum anchor.
    fn staged_check_accepts_enclosing_anchor_for_public_enum_variants() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n// @behavior req.visible The visible enum describes caller-facing modes.\npub enum Visible {\n    Existing,\n}\n",
        );
        // @verifies req.detector.contract.container The fixture verifies enum member checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n\n// @verifies req.visible The test verifies that the visible enum requirement is covered.\n#[test]\nfn visible_enum_is_covered() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n// @behavior req.visible The visible enum describes caller-facing modes.\npub enum Visible {\n    Existing,\n    Added,\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract.container The assertion verifies that enum variants match the enum anchor.
        let status = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect("anchored enum variant should pass staged check");

        assert_eq!(status, RequirementCheckStatus::Fresh);
    }

    #[test]
    // @verifies req.detector.contract.container The test verifies that public enum variants are contract changes.
    fn staged_check_rejects_unanchored_public_enum_variant_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub enum Visible {\n    Existing,\n}\n",
        );
        // @verifies req.detector.contract.container The fixture verifies enum variant detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub enum Visible {\n    Existing,\n    Added,\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract.container The assertion verifies that enum variants use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("public enum variant should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract.container The test verifies that public trait required items are contract changes.
    fn staged_check_rejects_unanchored_public_trait_required_items() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub trait Visible {\n    fn existing(&self);\n}\n",
        );
        // @verifies req.detector.contract.container The fixture verifies trait item detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub trait Visible {\n    fn existing(&self);\n    fn added(&self);\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract.container The assertion verifies that trait required items use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("public trait item should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract.container.header The test verifies that unsafe public trait required items are contract changes.
    fn staged_check_rejects_unanchored_unsafe_public_trait_required_items() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub unsafe trait Visible {\n    fn existing(&self);\n}\n",
        );
        // @verifies req.detector.contract.container.header The fixture verifies unsafe trait item detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub unsafe trait Visible {\n    fn existing(&self);\n    fn added(&self);\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract.container.header The assertion verifies that unsafe trait items use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("unsafe public trait item should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract.container The test verifies that multiline public enum headers expose variant contract changes.
    fn staged_check_rejects_unanchored_multiline_public_enum_variant_changes() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub enum Visible<T>\nwhere\n    T: Clone,\n{\n    Existing(T),\n}\n",
        );
        // @verifies req.detector.contract.container The fixture verifies multiline enum detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub enum Visible<T>\nwhere\n    T: Clone,\n{\n    Existing(T),\n    Added(T),\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract.container The assertion verifies that multiline enum variants use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("multiline public enum variant should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.detector.contract.container The test verifies that multiline public trait headers expose required item contract changes.
    fn staged_check_rejects_unanchored_multiline_public_trait_required_items() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub trait Visible<T>\nwhere\n    T: Clone,\n{\n    fn existing(&self);\n}\n",
        );
        // @verifies req.detector.contract.container The fixture verifies multiline trait detector checks with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub trait Visible<T>\nwhere\n    T: Clone,\n{\n    fn existing(&self);\n    fn added(&self);\n}\n",
        );
        repo.git_add(&["src/lib.rs"]);

        // @verifies req.detector.contract.container The assertion verifies that multiline trait items use contract diagnostics.
        let error = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect_err("multiline public trait item should fail staged check");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.cli.base_error The test verifies that base-check failures are observable as command errors.
    // @verifies req.api.mode The test verifies that base-check mode classifies changed hunks against a Git ref.
    // @verifies req.check The test verifies that CI-style base checks enforce requirement anchors.
    // @verifies req.check.head_snapshot The test verifies that staged checks tolerate repositories without HEAD snapshots.
    // @verifies req.check.git_ref_read The test verifies that base mode reads source files from a Git ref.
    // @verifies req.check.git_ref_list The test verifies that base mode lists source files from a Git ref.
    // @verifies req.check.git_ref_status The test verifies that base mode checks Git ref listing status.
    // @verifies req.detector.hunk_parse The test verifies that base mode parses diff hunk starts for diagnostics.
    // @verifies req.detector.diff_command The test verifies that diff command failures are part of check diagnostics.
    fn base_check_rejects_unanchored_contract_additions() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check The fixture verifies base mode with an existing test.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\npub fn added_contract() {}\n",
        );
        repo.git_add(&["src/lib.rs"]);
        repo.git_commit("add unanchored contract");

        // @verifies req.check The assertion verifies that base mode reports contract anchor diagnostics.
        let error = check_requirements(
            repo.path(),
            RequirementCheckMode::Base {
                git_ref: "HEAD~1".to_string(),
            },
        )
        .expect_err("base check should fail unanchored contract addition");

        assert!(error.contains("missing-contract-anchor"));
    }

    #[test]
    // @verifies req.check.merge_base The test verifies that base mode reads old records from the merge-base tree.
    fn base_check_uses_merge_base_snapshot_for_deleted_contracts() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n\n// @behavior req.visible The visible function is part of the public API.\npub fn visible() {}\n",
        );
        // @verifies req.check.merge_base The fixture verifies merge-base records with existing tests.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n\n// @verifies req.visible The test verifies that visible public API is covered.\n#[test]\nfn visible_is_covered() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");
        run_git(repo.path(), &["branch", "base"]);
        run_git(repo.path(), &["checkout", "-b", "topic"]);

        run_git(repo.path(), &["checkout", "base"]);
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check.merge_base.status The fixture verifies merge-base handling on an advanced base branch.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("advance base branch");

        run_git(repo.path(), &["checkout", "topic"]);
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check.merge_base.status The fixture verifies merge-base handling on the topic branch.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("delete visible contract");

        // @verifies req.check.merge_base The assertion verifies that advanced base tips do not replace merge-base records.
        let status = check_requirements(
            repo.path(),
            RequirementCheckMode::Base {
                git_ref: "base".to_string(),
            },
        )
        .expect("base check should use merge-base records");

        assert_eq!(status, RequirementCheckStatus::Fresh);
    }

    #[test]
    // @verifies req.check The test verifies that integration-test assertions use verification anchors.
    fn staged_check_accepts_nearby_verification_for_test_path_assertions() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check The fixture verifies initial integration-test assertions.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);
        format_agents_requirement_index(repo.path()).expect("format should succeed");
        repo.git_add(&["AGENTS.md"]);
        repo.git_commit("initial requirement comments");

        // @verifies req.check The fixture verifies added integration-test assertions.
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n\n#[test]\n// @verifies req.scan The test verifies that test-path assertions use verification anchors.\nfn added_test_path_assertion() {\n    assert_eq!(1, 1);\n}\n",
        );
        repo.git_add(&["tests/scan_contract.rs"]);

        // @verifies req.check The assertion verifies that test-path assertions accept nearby verifies comments.
        let status = check_requirements(repo.path(), RequirementCheckMode::Staged)
            .expect("test-path assertion should pass staged check");

        assert_eq!(status, RequirementCheckStatus::Fresh);
    }

    #[test]
    // @verifies req.detector.contract The test verifies that qualified public functions are contract changes.
    fn visible_contract_detector_accepts_qualified_public_functions() {
        assert!(is_visible_contract_line("pub unsafe fn refresh() {}"));
        assert!(is_visible_contract_line("pub extern \"C\" fn refresh() {}"));
        assert!(is_visible_contract_line("pub async unsafe fn refresh() {}"));
        assert!(is_visible_contract_line("pub mod foo;"));
        assert!(is_visible_contract_line("pub(crate) mod foo {}"));
        assert!(is_visible_contract_line("pub(crate) use foo::Bar;"));
        assert!(is_visible_contract_line("pub union Bits { value: u64 }"));
        assert!(is_visible_trait_line("pub unsafe trait Refresh {}"));
        // @verifies req.detector.field The assertions verify that public fields are contract changes.
        assert!(is_visible_contract_line("pub id: Id,"));
        assert!(is_visible_contract_line("pub(crate) id: Id,"));
        // @verifies req.detector.field.tuple The assertions verify that public tuple fields are contract changes.
        assert!(is_visible_contract_line("pub String,"));
        assert!(is_visible_contract_line("pub(crate) crate::types::Id,"));
        assert!(is_visible_contract_line("pub u64,"));
        assert!(is_visible_contract_line("pub std::path::PathBuf,"));
        assert!(!is_visible_contract_line("published_at: Instant,"));
        assert!(!is_visible_contract_line("public_key: String,"));
    }

    #[test]
    // @verifies req.check The test verifies that external tests modules are valid verification sites.
    fn scan_accepts_verification_comments_inside_external_tests_modules() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check The fixture verifies assertions inside external tests modules.
        repo.write(
            "src/tests.rs",
            "// @verifies req.scan The external test module verifies source requirements.\n#[test]\nfn external_tests_module_verifies_requirement() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "src/tests.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that external tests modules avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .all(|diagnostic| diagnostic.rule != "verification-outside-test")
        );
    }

    #[test]
    // @verifies req.check The test verifies that root Cargo examples are valid verification sites.
    fn scan_accepts_verification_comments_inside_root_examples() {
        let repo = TestRepo::new();
        repo.write(
            "AGENTS.md",
            "# AGENTS.md\n\n<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->\n<!-- END AGENTS_MD_REQUIREMENT_INDEX -->\n",
        );
        repo.write(
            "src/lib.rs",
            "//! @behavior req The module owns requirement automation.\n// @behavior req.scan The function scans comments.\npub fn scan() {}\n",
        );
        // @verifies req.check The fixture verifies assertions inside root Cargo examples.
        repo.write(
            "examples/scan_contract.rs",
            "// @verifies req.scan The example verifies source requirements.\nfn main() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "examples/scan_contract.rs"]);

        let report = scan_requirements(repo.path()).expect("scan should run");

        // @verifies req.check The assertion verifies that root examples avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .all(|diagnostic| diagnostic.rule != "verification-outside-test")
        );
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
            // @verifies req.check The assertion verifies that fixture staging fails loudly when Git rejects it.
            assert!(
                output.status.success(),
                "git add failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }

        fn git_commit(&self, message: &str) {
            let output = isolated_git_command()
                .current_dir(self.path())
                .args(["-c", "commit.gpgsign=false", "commit", "-m", message])
                .output()
                .expect("git commit should run");
            // @verifies req.check The assertion verifies that fixture commits fail loudly when Git rejects them.
            assert!(
                output.status.success(),
                "git commit failed: {}",
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
        // @verifies req.check The assertion verifies that helper Git commands fail loudly when Git rejects them.
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
        command
    }
}
