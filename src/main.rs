fn main() {
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
