//! @behavior req The xtask requirement tool validates source-comment requirements and AGENTS index freshness.
//! @behavior req.api The public API exposes requirement automation commands to the xtask binary.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

const BEGIN_MARKER: &str = "<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->";
const END_MARKER: &str = "<!-- END AGENTS_MD_REQUIREMENT_INDEX -->";

/// @constraint req.api.mode The check mode enum limits validation to either the full checkout or the staged Git snapshot.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequirementCheckMode {
    All,
    Staged,
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
    pub declarations: Vec<RequirementRecord>,
    pub verifications: Vec<RequirementRecord>,
    pub diagnostics: Vec<Diagnostic>,
}

/// @behavior req.api.record The requirement record stores the source location, tag, ID, sentence, and binding target.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementRecord {
    pub path: String,
    pub line: usize,
    pub tag: RequirementTag,
    pub id: String,
    pub sentence: String,
    pub binding: String,
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
    pub path: String,
    pub line: usize,
    pub rule: &'static str,
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
    let existing = fs::read_to_string(&agents_path)
        .map_err(|error| format!("failed to read {}: {error}", agents_path.display()))?;
    let line_ending = detect_line_ending(&existing);
    let block = render_requirement_index_block(&report.declarations, line_ending);
    let updated = upsert_requirement_index_block(&existing, &block, line_ending)?;
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
    };
    let mut report = scan_snapshot(&snapshot);

    if mode == RequirementCheckMode::Staged {
        report.diagnostics.extend(classify_staged_diff(
            root,
            &snapshot.files,
            &snapshot.records,
        )?);
    }

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

fn parse_requirement_comment(content: &str) -> Result<ParsedRequirement, String> {
    let mut parts = content.splitn(3, char::is_whitespace);
    let tag = match parts.next().unwrap_or_default() {
        "@behavior" => RequirementTag::Behavior,
        "@constraint" => RequirementTag::Constraint,
        "@intent" => RequirementTag::Intent,
        "@verifies" => RequirementTag::Verifies,
        _ => return Err("requirement comment must start with an allowed tag".to_string()),
    };
    let Some(id) = parts.next().filter(|id| !id.is_empty()) else {
        return Err("requirement comment must include a dotted ID".to_string());
    };
    if !valid_requirement_id(id) {
        return Err(format!(
            "requirement ID `{id}` violates the dotted ID grammar"
        ));
    }
    let Some(sentence) = parts.next().map(str::trim).filter(|text| !text.is_empty()) else {
        return Err("requirement comment must include one sentence".to_string());
    };
    if !has_one_sentence(sentence) {
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
    while let Some((_, character)) = characters.next() {
        if !matches!(character, '.' | '!' | '?') {
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

    let mut verified_ids = BTreeSet::new();
    for verification in verifications {
        verified_ids.insert(verification.id.as_str());
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
            Some(record)
                if matches!(
                    record.tag,
                    RequirementTag::Behavior | RequirementTag::Constraint
                ) => {}
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

    for declaration in declarations {
        if !matches!(
            declaration.tag,
            RequirementTag::Behavior | RequirementTag::Constraint
        ) {
            continue;
        }
        if has_declared_child(&declaration.id, declarations) {
            continue;
        }
        if !verified_ids.contains(declaration.id.as_str()) {
            diagnostics.push(Diagnostic {
                path: declaration.path.clone(),
                line: declaration.line,
                rule: "unverified-leaf-requirement",
                message: format!(
                    "leaf {} `{}` must have at least one @verifies reference",
                    declaration.tag.as_str(),
                    declaration.id
                ),
            });
        }
    }

    diagnostics
}

fn has_declared_child(id: &str, declarations: &[RequirementRecord]) -> bool {
    let prefix = format!("{id}.");
    declarations
        .iter()
        .any(|declaration| declaration.id.starts_with(&prefix))
}

fn ancestor_ids(id: &str) -> Vec<String> {
    let parts = id.split('.').collect::<Vec<_>>();
    (1..parts.len()).map(|end| parts[..end].join(".")).collect()
}

fn is_test_path(path: &str) -> bool {
    path.contains("/tests/")
        || path.starts_with("tests/")
        || path.contains("/examples/")
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

fn upsert_requirement_index_block(
    existing: &str,
    block: &str,
    line_ending: &str,
) -> Result<String, String> {
    let begin_matches = existing.matches(BEGIN_MARKER).count();
    let end_matches = existing.matches(END_MARKER).count();
    if begin_matches > 1 || end_matches > 1 {
        return Err("AGENTS.md contains duplicate requirement index markers".to_string());
    }
    if begin_matches != end_matches {
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
        .expect("marker count already checked");
    let end = existing
        .find(END_MARKER)
        .expect("marker count already checked")
        + END_MARKER.len();
    let mut updated = String::new();
    updated.push_str(&existing[..start]);
    updated.push_str(block);
    updated.push_str(&existing[end..]);
    Ok(updated)
}

fn classify_staged_diff(
    root: &Path,
    files: &[SnapshotFile],
    records: &[RequirementRecord],
) -> Result<Vec<Diagnostic>, String> {
    let output = isolated_git_command()
        .current_dir(root)
        .args(["diff", "--cached", "--unified=0", "--", "*.rs"])
        .output()
        .map_err(|error| format!("failed to run git diff --cached: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "git diff --cached failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    let mut diagnostics = Vec::new();
    let mut current_path = None::<String>;
    let mut new_line = 0usize;
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        if let Some(path) = line.strip_prefix("+++ b/") {
            current_path = Some(path.to_string());
            continue;
        }
        if let Some(hunk) = line.strip_prefix("@@ ") {
            new_line = parse_hunk_new_start(hunk);
            continue;
        }
        if !line.starts_with('+') || line.starts_with("+++") {
            if new_line > 0 && !line.starts_with('-') {
                new_line += 1;
            }
            continue;
        }
        let Some(path) = current_path.as_deref() else {
            continue;
        };
        let added = line.trim_start_matches('+').trim();
        if added.is_empty() || added.starts_with("//") || added.starts_with("/*") {
            new_line += 1;
            continue;
        }

        if let Some((rule, required)) = classify_added_line(added) {
            let in_test_context = files
                .iter()
                .find(|file| file.path == path)
                .is_some_and(|file| is_inline_test_context(file, new_line))
                || is_test_path(path);
            if in_test_context && rule != "missing-test-expectation-anchor" {
                new_line += 1;
                continue;
            }
            let (rule, required) = if !in_test_context && rule == "missing-test-expectation-anchor"
            {
                if is_assertion_line(added) {
                    (
                        "missing-failure-policy-anchor",
                        vec![RequirementTag::Behavior, RequirementTag::Constraint],
                    )
                } else {
                    new_line += 1;
                    continue;
                }
            } else {
                (rule, required)
            };
            let has_anchor = records.iter().any(|record| {
                record.path == path
                    && required.contains(&record.tag)
                    && record.line <= new_line
                    && new_line.saturating_sub(record.line) <= 8
            });
            if !has_anchor {
                diagnostics.push(Diagnostic {
                    path: path.to_string(),
                    line: new_line,
                    rule,
                    message: format!(
                        "changed Rust hunk requires one of {} near the enclosing code unit",
                        required
                            .iter()
                            .map(|tag| tag.as_str())
                            .collect::<Vec<_>>()
                            .join(" or ")
                    ),
                });
            }
        }
        new_line += 1;
    }
    Ok(diagnostics)
}

/// @intent req.detector The diff detector table maps Rust syntax signals to required requirement tags.
fn classify_added_line(line: &str) -> Option<(&'static str, Vec<RequirementTag>)> {
    if is_assertion_line(line) || line.contains("mock") || line.contains("fixture") {
        return Some((
            "missing-test-expectation-anchor",
            vec![RequirementTag::Verifies],
        ));
    }
    if is_visible_contract_line(line)
        || line.starts_with("pub use ")
        || line.contains("Serialize")
        || line.contains("Deserialize")
    {
        return Some((
            "missing-contract-anchor",
            vec![RequirementTag::Behavior, RequirementTag::Constraint],
        ));
    }
    if line.starts_with("pub trait ")
        || line.starts_with("trait ")
        || is_visible_trait_line(line)
        || line.contains("dyn ")
        || line.contains("Box<dyn")
        || line.contains("Arc<dyn")
    {
        return Some(("missing-structure-intent", vec![RequirementTag::Intent]));
    }
    if line.contains("tokio::time::timeout")
        || line.contains("map_err")
        || line.contains("panic!")
        || line.contains("unwrap")
        || line.contains("expect(")
        || line.contains("Err(")
    {
        return Some((
            "missing-failure-policy-anchor",
            vec![RequirementTag::Behavior, RequirementTag::Constraint],
        ));
    }
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

/// @behavior req.detector.assertion The assertion detector classifies production assertions as failure-policy changes and test assertions as verification changes.
fn is_assertion_line(line: &str) -> bool {
    line.contains("assert!")
        || line.contains("assert_eq!")
        || line.contains("assert_ne!")
        || line.contains("matches!")
}

/// @behavior req.detector.structure The structure detector classifies visible trait declarations as structure-intent changes.
fn is_visible_trait_line(line: &str) -> bool {
    visible_line_remainder(line).is_some_and(|rest| rest.starts_with("trait "))
}

/// @behavior req.detector.contract The visible contract detector classifies unrestricted and restricted Rust APIs as contract changes.
fn is_visible_contract_line(line: &str) -> bool {
    visible_line_remainder(line).is_some_and(|rest| {
        is_visible_function_remainder(rest)
            || rest.starts_with("struct ")
            || rest.starts_with("enum ")
            || rest.starts_with("type ")
            || rest.starts_with("const ")
            || rest.starts_with("static ")
    })
}

fn visible_line_remainder(line: &str) -> Option<&str> {
    let rest = line.strip_prefix("pub")?;
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

fn parse_hunk_new_start(hunk: &str) -> usize {
    hunk.split_whitespace()
        .find_map(|part| part.strip_prefix('+'))
        .and_then(|part| part.split(',').next())
        .and_then(|line| line.parse::<usize>().ok())
        .unwrap_or(0)
}

fn extract_requirement_comments(file: &SnapshotFile) -> Vec<RawRequirementComment> {
    let mut comments = Vec::new();
    let lines = file.content.lines().collect::<Vec<_>>();
    let mut index = 0usize;
    while index < lines.len() {
        let line = lines[index];
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
            let mut body = String::new();
            let mut current = rest;
            loop {
                if let Some(end) = current.find("*/") {
                    body.push_str(&current[..end]);
                    break;
                }
                body.push_str(current);
                index += 1;
                if index >= lines.len() {
                    break;
                }
                body.push(' ');
                current = lines[index].trim();
            }
            let normalized = body.trim().trim_start_matches('*').trim();
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
    let mut pending_cfg_test = false;
    let mut brace_depth = 0usize;
    let mut test_module_depths = Vec::new();

    for source_line in file.content.lines().take(line.saturating_sub(1)) {
        let trimmed = source_line.trim();
        test_module_depths.retain(|module_depth| brace_depth > *module_depth);
        if trimmed.starts_with("#[cfg(test)]") {
            pending_cfg_test = true;
        }

        let opens = source_line.matches('{').count();
        let closes = source_line.matches('}').count();
        if pending_cfg_test && trimmed.contains("mod ") && trimmed.contains('{') {
            test_module_depths.push(brace_depth);
            pending_cfg_test = false;
        } else if !trimmed.starts_with("#[") && !trimmed.is_empty() {
            pending_cfg_test = false;
        }
        brace_depth = brace_depth.saturating_add(opens).saturating_sub(closes);
    }

    test_module_depths
        .iter()
        .any(|module_depth| brace_depth > *module_depth)
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
    records: Vec<RequirementRecord>,
}

impl Snapshot {
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
                Err(error) if error.kind() == io::ErrorKind::InvalidData => continue,
                Err(error) => {
                    return Err(format!("failed to read {}: {error}", full_path.display()));
                }
            }
        }
        let records = Vec::new();
        Ok(Self { files, records })
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
        let report = scan_snapshot(&Self {
            files: files.clone(),
            records: Vec::new(),
        });
        Ok(Self {
            files,
            records: report
                .declarations
                .into_iter()
                .chain(report.verifications)
                .collect(),
        })
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

fn git_path_list(root: &Path, args: &[&str]) -> Result<Vec<PathBuf>, String> {
    let output = isolated_git_command()
        .current_dir(root)
        .args(args)
        .output()
        .map_err(|error| format!("failed to run git {}: {error}", args.join(" ")))?;
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
        format_agents_requirement_index, is_visible_contract_line, parse_requirement_comment,
        scan_requirements,
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
    // @verifies req.format The test verifies that fmt-agents writes requirement tree rows into AGENTS.md.
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
        repo.write(
            "tests/scan_contract.rs",
            "// @verifies req.scan The test verifies that scan comments are indexed.\n#[test]\nfn scan_comments_are_indexed() {\n    assert!(true);\n}\n",
        );
        repo.git_add(&["AGENTS.md", "src/lib.rs", "tests/scan_contract.rs"]);

        format_agents_requirement_index(repo.path()).expect("format should succeed");

        let agents = repo.read("AGENTS.md");
        assert!(agents.contains("|req|req.{scan}"));
        assert!(agents.contains("|req.scan|req.scan.{}"));
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

        assert_eq!(status, RequirementCheckStatus::StaleAgentsIndex);
    }

    #[test]
    // @verifies req.api.mode The test verifies that full-check mode scans the whole tracked checkout.
    fn scan_reports_missing_leaf_verification() {
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

        // @verifies req.check The assertion verifies that inline test comments avoid outside-test diagnostics.
        assert!(
            report
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.rule == "unverified-leaf-requirement")
        );
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
