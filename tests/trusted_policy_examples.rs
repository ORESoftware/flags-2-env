const RUST_README: &str = include_str!("../clients/rust/README.md");
const GIT_CONSUMER: &str = include_str!("fixtures/rust-git-consumer/src/main.rs");
const POLICY_DOC: &str = include_str!("../docs/trusted-policy-paths.md");

#[test]
fn rust_docs_do_not_teach_cwd_owned_contracts() {
    assert!(!RUST_README.contains("audit_config(Some(\".cli-flags.toml\"))"));
    assert!(!RUST_README.contains("parse_structured(&argv, Some(\".cli-flags.toml\"))"));
    assert!(RUST_README.contains("CARGO_MANIFEST_DIR"));
    assert!(RUST_README.contains("current_exe()"));
}

#[test]
fn rust_docs_do_not_teach_value_bearing_error_logging() {
    assert!(!RUST_README.contains("unknown={:?}"));
    assert!(!RUST_README.contains("errors={:?}"));
    assert!(RUST_README.contains("parsed.unknown_options.len()"));
    assert!(RUST_README.contains("parsed.errors.len()"));
    assert!(RUST_README.contains("parsed.extras.len()"));
}

#[test]
fn git_consumer_fixture_is_source_owned_and_positionals_fail_closed() {
    assert!(GIT_CONSUMER.contains("CARGO_MANIFEST_DIR"));
    assert!(!GIT_CONSUMER.contains("Some(\".cli-flags.toml\")"));
    assert!(GIT_CONSUMER.contains("parsed.extras.is_empty()"));
}

#[test]
fn canonical_policy_doc_requires_absolute_or_executable_owned_resolution() {
    assert!(POLICY_DOC.contains("absolute path"));
    assert!(POLICY_DOC.contains("current_exe()"));
    assert!(POLICY_DOC.contains("fail closed"));
    assert!(POLICY_DOC.contains("/usr/local/share/example/.cli-flags.toml"));
}
