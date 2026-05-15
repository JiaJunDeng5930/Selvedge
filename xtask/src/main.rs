//! @behavior tool.cli The xtask CLI dispatches AGENTS index and requirement commands from one entrypoint.
//! @behavior tool.cli.project_index The xtask CLI exposes project-index update and check commands for AGENTS.md.

use std::env;
use std::path::PathBuf;
use std::process;

use xtask::agents_index::{CheckStatus, DirectoryWarning, check_agents_md, update_agents_md};
use xtask::readme_gate::{
    ReadmeFreshnessStatus, check_package_readme_mermaid, check_package_readmes_freshness,
};
use xtask::requirements::{
    RequirementCheckMode, RequirementCheckStatus, check_requirements,
    format_agents_requirement_index, scan_requirements,
};

const WARNING_THRESHOLD: usize = 200;

fn main() {
    let root = workspace_root();
    let args = env::args().skip(1).collect::<Vec<_>>();
    let exit_code = match args.as_slice() {
        [command, action] if command == "agents-index" && action == "update" => {
            match update_agents_md(&root, WARNING_THRESHOLD) {
                // @behavior tool.cli.project_index.update_success The project-index update command prints directory warnings and exits successfully after updating AGENTS.md.
                Ok(warnings) => {
                    print_warnings(&warnings);
                    0
                }
                // @behavior tool.cli.project_index.update_error The project-index update command prints update errors and exits with failure.
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action] if command == "agents-index" && action == "check" => {
            match check_agents_md(&root, WARNING_THRESHOLD) {
                // @behavior tool.cli.project_index.check_fresh The project-index check command prints directory warnings and exits successfully when AGENTS.md is current.
                Ok(CheckStatus::Fresh { warnings }) => {
                    print_warnings(&warnings);
                    0
                }
                // @behavior tool.cli.project_index.check_stale The project-index check command prints directory warnings, stale-index guidance, and failure when AGENTS.md is stale.
                Ok(CheckStatus::Stale { warnings }) => {
                    print_warnings(&warnings);
                    eprintln!("AGENTS.md project index is stale. Run `just agents-index`.");
                    1
                }
                // @behavior tool.cli.project_index.check_error The project-index check command prints check errors and exits with failure.
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action] if command == "req" && action == "scan" => match scan_requirements(&root)
        {
            Ok(report) => {
                print_requirement_report(&report);
                // @behavior tool.cli.scan_status The scan command exits successfully when diagnostics are empty and fails when scanner diagnostics are present.
                if report.diagnostics.is_empty() { 0 } else { 1 }
            }
            // @behavior tool.cli.scan_error The scan command prints scanner errors and exits with failure.
            Err(error) => {
                eprintln!("{error}");
                1
            }
        },
        [command, action] if command == "readme" && action == "check-freshness" => {
            match check_package_readmes_freshness(&root) {
                Ok(ReadmeFreshnessStatus::Fresh) => 0,
                Ok(ReadmeFreshnessStatus::Stale { packages }) => {
                    // @behavior tool.cli.readme_freshness_stale The README freshness command prints every stale package and exits with failure.
                    for package in packages {
                        eprintln!(
                            "{}: stale README freshness metadata at {}",
                            package.package, package.readme_path
                        );
                        eprintln!("  freshness_commit: {}", package.freshness_commit);
                        for changed_file in package.changed_files {
                            eprintln!("  changed: {changed_file}");
                        }
                    }
                    1
                }
                // @behavior tool.cli.readme_freshness_error The README freshness command prints checker errors and exits with failure.
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action] if command == "readme" && action == "check-mermaid" => {
            match check_package_readme_mermaid(&root) {
                Ok(()) => 0,
                // @behavior tool.cli.readme_mermaid_error The README Mermaid command prints renderer diagnostics and exits with failure.
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action] if command == "req" && action == "fmt-agents" => {
            match format_agents_requirement_index(&root) {
                Ok(()) => 0,
                // @behavior tool.cli.format_error The fmt-agents command prints formatter errors and exits with failure.
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action, flag] if command == "req" && action == "check" && flag == "--staged" => {
            match check_requirements(&root, RequirementCheckMode::Staged) {
                Ok(RequirementCheckStatus::Fresh) => 0,
                // @behavior tool.cli.staged_stale The staged-check branch tells users to regenerate and stage AGENTS.md when the staged requirement index is stale.
                Ok(RequirementCheckStatus::StaleAgentsIndex) => {
                    eprintln!(
                        "AGENTS.md:1: stale-requirement-index: run `cargo xtask req fmt-agents` and stage AGENTS.md"
                    );
                    1
                }
                // @behavior tool.cli.staged_error The staged-check branch prints requirement check errors and exits with failure.
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action, flag] if command == "req" && action == "check" && flag == "--all" => {
            match check_requirements(&root, RequirementCheckMode::All) {
                Ok(RequirementCheckStatus::Fresh) => 0,
                // @behavior tool.cli.all_stale The all-check branch tells users to regenerate AGENTS.md when the checkout requirement index is stale.
                Ok(RequirementCheckStatus::StaleAgentsIndex) => {
                    eprintln!(
                        "AGENTS.md:1: stale-requirement-index: run `cargo xtask req fmt-agents`"
                    );
                    1
                }
                // @behavior tool.cli.all_error The all-check branch prints requirement check errors and exits with failure.
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action, flag, git_ref]
            if command == "req" && action == "check" && flag == "--base" =>
        {
            // @behavior tool.cli.base_ref The base-check branch passes the user supplied Git ref into base diff validation.
            let git_ref = git_ref.to_string();
            match check_requirements(&root, RequirementCheckMode::Base { git_ref }) {
                Ok(RequirementCheckStatus::Fresh) => 0,
                // @behavior tool.cli.base_stale The base-check branch tells users to regenerate AGENTS.md when the checkout requirement index is stale.
                Ok(RequirementCheckStatus::StaleAgentsIndex) => {
                    eprintln!(
                        "AGENTS.md:1: stale-requirement-index: run `cargo xtask req fmt-agents`"
                    );
                    1
                }
                // @behavior tool.cli.base_error The base-check branch prints requirement check errors and exits with failure.
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        _ => {
            // @behavior tool.cli.usage_error Unsupported xtask arguments print usage and exit with code 2.
            eprintln!(
                "usage: cargo xtask agents-index <update|check>\n       cargo xtask readme <check-freshness|check-mermaid>\n       cargo xtask req <scan|fmt-agents>\n       cargo xtask req check <--staged|--all|--base <git-ref>>"
            );
            2
        }
    };

    process::exit(exit_code);
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        // @constraint tool.cli.workspace_root The xtask binary must resolve its Cargo manifest parent as the workspace root before reading repository files.
        .expect("xtask should live under the workspace root")
        .to_path_buf()
}

fn print_warnings(warnings: &[DirectoryWarning]) {
    // @behavior tool.cli.project_index.warning_output Project-index directory warnings are printed to stderr with path and entry count.
    for warning in warnings {
        eprintln!(
            "warning: index path `{}` has {} direct filesystem entries",
            warning.path, warning.entry_count
        );
    }
}

fn print_requirement_report(report: &xtask::requirements::RequirementScanReport) {
    // @behavior tool.cli.scan_output The scan report prints declarations and verifications to stdout and diagnostics to stderr.
    for declaration in &report.declarations {
        println!(
            "{}:{}: {} {} -> {}",
            declaration.path,
            declaration.line,
            declaration.tag.as_str(),
            declaration.id,
            declaration.binding
        );
    }
    for verification in &report.verifications {
        println!(
            "{}:{}: {} {} -> {}",
            verification.path,
            verification.line,
            verification.tag.as_str(),
            verification.id,
            verification.binding
        );
    }
    for diagnostic in &report.diagnostics {
        eprintln!(
            "{}:{}: {}: {}",
            diagnostic.path, diagnostic.line, diagnostic.rule, diagnostic.message
        );
    }
}
