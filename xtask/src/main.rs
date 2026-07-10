use std::env;
use std::path::PathBuf;
use std::process;

use xtask::agents_index::{CheckStatus, DirectoryWarning, check_agents_md, update_agents_md};
use xtask::readme_gate::{
    ReadmeFreshnessStatus, check_package_readme_mermaid, check_package_readmes_freshness,
};

const WARNING_THRESHOLD: usize = 200;

fn main() {
    let root = workspace_root();
    let args = env::args().skip(1).collect::<Vec<_>>();
    let exit_code = match args.as_slice() {
        [command, action] if command == "agents-index" && action == "update" => {
            match update_agents_md(&root, WARNING_THRESHOLD) {
                Ok(warnings) => {
                    print_warnings(&warnings);
                    0
                }
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action] if command == "agents-index" && action == "check" => {
            match check_agents_md(&root, WARNING_THRESHOLD) {
                Ok(CheckStatus::Fresh { warnings }) => {
                    print_warnings(&warnings);
                    0
                }
                Ok(CheckStatus::Stale { warnings }) => {
                    print_warnings(&warnings);
                    eprintln!("AGENTS.md project index is stale. Run `just agents-index`.");
                    1
                }
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action] if command == "readme" && action == "check-freshness" => {
            match check_package_readmes_freshness(&root) {
                Ok(ReadmeFreshnessStatus::Fresh) => 0,
                Ok(ReadmeFreshnessStatus::Stale { packages }) => {
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
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        [command, action] if command == "readme" && action == "check-mermaid" => {
            match check_package_readme_mermaid(&root) {
                Ok(()) => 0,
                Err(error) => {
                    eprintln!("{error}");
                    1
                }
            }
        }
        _ => {
            eprintln!(
                "usage: cargo xtask agents-index <update|check>\n       cargo xtask readme <check-freshness|check-mermaid>"
            );
            2
        }
    };

    process::exit(exit_code);
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("xtask should live under the workspace root")
        .to_path_buf()
}

fn print_warnings(warnings: &[DirectoryWarning]) {
    for warning in warnings {
        eprintln!(
            "warning: index path `{}` has {} direct filesystem entries",
            warning.path, warning.entry_count
        );
    }
}
