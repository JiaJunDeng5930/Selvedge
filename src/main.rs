fn main() {
    // @behavior selvedge.cli.process.main The CLI binary runs selvedge::run_cli on a current-thread Tokio runtime and exits with the mapped process code.
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .expect("create CLI runtime");
    let status = runtime.block_on(selvedge::run_cli(selvedge::CliRunArgs {
        argv: std::env::args().collect(),
    }));

    std::process::exit(selvedge::exit_code(&status));
}
