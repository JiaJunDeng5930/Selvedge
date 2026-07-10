fn main() {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_io()
        .enable_time()
        .build()
        .expect("create CLI runtime");
    let status = runtime.block_on(selvedge::run_cli(selvedge::CliRunArgs {
        argv: std::env::args().collect(),
    }));
    let _ = selvedge::write_cli_exit_status(&status, std::io::stderr());

    std::process::exit(selvedge::exit_code(&status));
}
