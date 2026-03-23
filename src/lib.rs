pub fn app_name() -> &'static str {
    env!("CARGO_PKG_NAME")
}

pub fn startup_message() -> String {
    format!("{} is ready.", app_name())
}

#[cfg(test)]
mod tests {
    use super::{app_name, startup_message};

    #[test]
    fn startup_message_mentions_project_name() {
        assert!(startup_message().contains(app_name()));
    }
}
