//! The script command surface has one definition for discovery, bindings and dispatch.

use serde_json::{Value, json};

macro_rules! kernel_commands {
    ($($variant:ident => ($name:literal, $signature:literal, $docs:literal)),+ $(,)?) => {
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        pub(crate) enum KernelCommand { $($variant),+ }
        impl KernelCommand {
            pub(crate) const ALL: &[Self] = &[$(Self::$variant),+];
            pub(crate) fn name(self) -> &'static str {
                match self { $(Self::$variant => $name),+ }
            }
            fn signature(self) -> &'static str {
                match self { $(Self::$variant => $signature),+ }
            }
            fn docs(self) -> &'static str {
                match self { $(Self::$variant => $docs),+ }
            }
            pub(crate) fn parse(name: &str) -> Option<Self> {
                Self::ALL.iter().copied().find(|command| command.name() == name)
            }
        }
    };
}

kernel_commands! {
    Read => ("tasks.read", "tasks.read({task_id?, after_node_id?, limit?} = {}) -> Promise<Task>",
        "Read task status and paginated history; task_id defaults to the current caller. limit is 1..100. Status is active, frozen, stopped, or archived."),
    Logs => ("tasks.logs", "tasks.logs({task_id?, after_node_id?, limit?} = {}) -> Promise<HistoryPage>",
        "Read the selected task's history page, with the same cursor and limit as tasks.read."),
    Send => ("tasks.send", "tasks.send({task_id, message}) -> Promise<SendResult>",
        "Send a message to self or a direct child. The durable result is replayed on retry."),
    Fork => ("tasks.fork", "tasks.fork({child_count, messages?, environment?}) -> Promise<ForkResult>",
        "Create direct children. environment is shared (default), copy, or new. Children are readable immediately and start after the enclosing command commits; copy takes the final command state."),
    Archive => ("tasks.archive", "tasks.archive({task_id?} = {}) -> Promise<StatusResult>",
        "Archive an active, frozen, or stopped self or direct child. Self changes take effect when the enclosing command commits."),
    Freeze => ("tasks.freeze", "tasks.freeze({task_id?} = {}) -> Promise<StatusResult>",
        "Freeze an active self or direct child. Self changes take effect when the enclosing command commits."),
    Unfreeze => ("tasks.unfreeze", "tasks.unfreeze({task_id?} = {}) -> Promise<StatusResult>",
        "Unfreeze a frozen self or direct child."),
    Stop => ("tasks.stop", "tasks.stop({task_id?} = {}) -> Promise<StatusResult>",
        "Stop an active self or direct child. Self changes take effect when the enclosing command commits."),
    Bash => ("tools.exec_bash", "tools.exec_bash({command, timeout_ms?}) -> Promise<BashResult>",
        "Run Bash through the host with bounded output. Startup rejects previously uncompleted shell operations. An interrupted external operation is never silently rerun."),
    WriteFile => ("tools.write_file", "tools.write_file({path, content}) -> Promise<WriteResult>",
        "Write UTF-8 file content through the host. Startup rejects previously uncompleted writes. An interrupted external operation is never silently rerun."),
}

pub(crate) fn kernel_metadata() -> Value {
    Value::Array(
        KernelCommand::ALL
            .iter()
            .map(|command| {
                json!({
                    "name": command.name(), "signature": command.signature(), "docs": command.docs()
                })
            })
            .collect(),
    )
}

pub(crate) fn kernel_bootstrap() -> String {
    let metadata = kernel_metadata();
    let mut bootstrap = format!(
        "globalThis.kernel = Object.freeze({{describe: () => ({metadata})}});\n\
         globalThis.tasks = {{}}; globalThis.tools = {{}};\n"
    );
    for command in KernelCommand::ALL {
        // Only the stable command name is captured. Caller identity belongs to the invocation host.
        bootstrap.push_str(&format!(
            "{} = function(args = {{}}) {{ return __selvedgeHost({:?}, args); }};\n",
            command.name(),
            command.name()
        ));
    }
    bootstrap.push_str("Object.freeze(tasks); Object.freeze(tools);\n");
    bootstrap
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discovered_commands_have_dispatch_and_bindings() {
        let bootstrap = kernel_bootstrap();
        for metadata in kernel_metadata().as_array().expect("metadata array") {
            let name = metadata["name"].as_str().expect("command name");
            assert!(KernelCommand::parse(name).is_some());
            assert!(bootstrap.contains(&format!("{name} = function")));
            assert!(
                !metadata["docs"]
                    .as_str()
                    .expect("command documentation")
                    .is_empty()
            );
        }
        assert!(!bootstrap.contains("task_id:"));
    }
}
