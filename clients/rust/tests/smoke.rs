use flags2env::{CoercionError, Flags2Env};
use serde::Deserialize;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

struct CwdGuard(PathBuf);

impl Drop for CwdGuard {
    fn drop(&mut self) {
        let _ = env::set_current_dir(&self.0);
    }
}

#[allow(non_snake_case)]
#[derive(Debug, Deserialize)]
struct GeneratedConfig {
    PORT: i64,
    DEBUG: bool,
    COLOR: bool,
}

#[test]
fn parse_finds_parent_config() {
    let original = env::current_dir().unwrap();
    let _cwd_guard = CwdGuard(original);
    let library = compile_test_library();
    let config_root = create_config_tree();

    let sdk = unsafe { Flags2Env::load(Some(library.to_str().unwrap())).unwrap() };
    env::set_current_dir(config_root.join("nested/deeper")).unwrap();
    let parsed = sdk
        .parse(
            &[
                "app".into(),
                "--debug=t".into(),
                "--port".into(),
                "8181".into(),
            ],
            None,
        )
        .unwrap();

    assert_eq!(parsed.get("DEBUG"), Some(&"true".to_string()));
    assert_eq!(parsed.get("PORT"), Some(&"8181".to_string()));
    assert_eq!(parsed.get("COLOR"), Some(&"true".to_string()));

    let config_path = config_root.join(".cli-flags.toml");
    let explicit = sdk
        .parse(
            &["app".into(), "--debug=f".into()],
            Some(config_path.to_str().unwrap()),
        )
        .unwrap();
    assert_eq!(explicit.get("DEBUG"), Some(&"false".to_string()));
    assert_eq!(explicit.get("PORT"), Some(&"3000".to_string()));

    let mut combined = HashMap::from([
        ("PORT".to_string(), "env".to_string()),
        ("KEEP".to_string(), "1".to_string()),
    ]);
    sdk.apply(
        &mut combined,
        &["app".into(), "--port".into(), "8181".into()],
    )
    .unwrap();
    assert_eq!(combined.get("PORT"), Some(&"8181".to_string()));
    assert_eq!(combined.get("KEEP"), Some(&"1".to_string()));
    assert_eq!(combined.get("COLOR"), Some(&"true".to_string()));
}

#[test]
fn parse_structured_returns_separate_channels() {
    let library = compile_test_library();
    let config_root = create_subcommand_config();
    let config_path = config_root.join(".cli-flags.toml");
    let config = config_path.to_str().unwrap();

    let sdk = unsafe { Flags2Env::load(Some(library.to_str().unwrap())).unwrap() };

    let argv: Vec<String> = ["gitish", "remote", "add", "-f", "abc", "efg"]
        .iter()
        .map(|value| value.to_string())
        .collect();
    let structured = sdk.parse_structured(&argv, Some(config)).unwrap();
    assert_eq!(structured.command, "remote add");
    assert_eq!(
        structured.subcommands,
        vec!["remote".to_string(), "add".to_string()]
    );
    assert_eq!(
        structured.extras,
        vec!["abc".to_string(), "efg".to_string()]
    );
    assert_eq!(
        structured.flags.get("GITISH_REMOTE_ADD_FETCH"),
        Some(&"true".to_string())
    );
    assert_eq!(
        structured.provided_flags.get("GITISH_REMOTE_ADD_FETCH"),
        Some(&"true".to_string())
    );
    assert!(!structured.provided_flags.contains_key("GITISH_VERBOSE"));
    assert!(structured.unknown_options.is_empty());
    assert!(structured.errors.is_empty());

    let dashed: Vec<String> = ["gitish", "remote", "add", "--", "xyz", "-q"]
        .iter()
        .map(|value| value.to_string())
        .collect();
    let dashed_result = sdk.parse_structured(&dashed, Some(config)).unwrap();
    assert_eq!(
        dashed_result.extras,
        vec!["xyz".to_string(), "-q".to_string()]
    );

    let resolved = sdk.resolve_commands(&argv, Some(config)).unwrap();
    assert_eq!(resolved.path, vec!["remote".to_string(), "add".to_string()]);
    assert_eq!(resolved.label, "remote add");
}

#[test]
fn dynamic_coerce_returns_typed_config_and_structured_errors() {
    let library = compile_test_library();
    let config_root = create_config_tree();
    let config_path = config_root.join(".cli-flags.toml");
    let config = config_path.to_str().unwrap();
    let sdk = unsafe { Flags2Env::load(Some(library.to_str().unwrap())).unwrap() };

    let defaults_only = sdk.parse_structured(&["app".into()], Some(config)).unwrap();
    let mut environment = HashMap::from([("PORT".to_string(), "9191".to_string())]);
    environment.extend(defaults_only.provided_flags);
    let env_typed: GeneratedConfig = sdk.coerce(&environment, Some(config)).unwrap();
    assert_eq!(env_typed.PORT, 9191);

    let parsed = sdk
        .parse_structured(
            &[
                "app".into(),
                "--debug=t".into(),
                "--port".into(),
                "8181".into(),
            ],
            Some(config),
        )
        .unwrap();
    let mut combined = HashMap::from([("PORT".to_string(), "9191".to_string())]);
    combined.extend(parsed.provided_flags);
    let typed: GeneratedConfig = sdk.coerce(&combined, Some(config)).unwrap();

    assert_eq!(typed.PORT, 8181);
    assert!(typed.DEBUG);
    assert!(typed.COLOR);

    let invalid = HashMap::from([
        ("PORT".to_string(), "not-an-integer".to_string()),
        ("DEBUG".to_string(), "maybe".to_string()),
    ]);
    let error = sdk
        .coerce::<GeneratedConfig, _>(&invalid, Some(config))
        .expect_err("invalid values must fail");
    let messages = error.validation_errors().expect("schema validation errors");

    assert!(matches!(&error, CoercionError::Validation { .. }));
    assert_eq!(messages.len(), 2);
    for key in ["PORT", "DEBUG"] {
        assert!(
            messages.iter().any(|message| message.contains(key)),
            "missing validation message for {key}: {messages:?}"
        );
    }
}

fn create_subcommand_config() -> PathBuf {
    let root = temp_dir("subcommands");
    fs::write(
        root.join(".cli-flags.toml"),
        r#"[flags.verbose]
env = "GITISH_VERBOSE"
aliases = ["verbose"]
type = "bool"

[commands.remote]
help = "Manage remotes."

[commands.remote.commands.add]
help = "Add a remote."

[commands.remote.commands.add.flags.fetch]
env = "GITISH_REMOTE_ADD_FETCH"
aliases = ["fetch"]
short = "f"
type = "bool"
"#,
    )
    .unwrap();
    root
}

fn compile_test_library() -> PathBuf {
    let out_dir = temp_dir("native");
    let output = out_dir.join(default_library_name());
    let compiler = env::var("CC").unwrap_or_else(|_| "cc".to_string());
    let mut command = Command::new(compiler);

    command.args(["-std=c99", "-O2", "-fPIC"]);
    if cfg!(target_os = "macos") {
        command.args(["-dynamiclib", "-Wl,-install_name,@rpath/libflags2env.dylib"]);
    } else {
        command.arg("-shared");
    }
    command.args(["native/parser.c", "-o"]);
    command.arg(&output);

    let status = command
        .status()
        .expect("failed to start C compiler for Rust smoke test");
    assert!(
        status.success(),
        "failed to compile native/parser.c for Rust smoke test"
    );
    output
}

fn create_config_tree() -> PathBuf {
    let root = temp_dir("config");
    fs::create_dir_all(root.join("nested/deeper")).unwrap();
    fs::write(
        root.join(".cli-flags.toml"),
        r#"[flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"
default = 3000

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
type = "bool"
default = "false"
true_aliases = ["t"]
false_aliases = ["f"]

[flags.color]
env = "COLOR"
aliases = ["color"]
type = "bool"
default = "true"
"#,
    )
    .unwrap();
    root
}

fn temp_dir(label: &str) -> PathBuf {
    let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let path = env::temp_dir().join(format!(
        "flags2env-rust-{label}-{}-{sequence}",
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&path);
    fs::create_dir_all(&path).unwrap();
    path
}

fn default_library_name() -> &'static str {
    if cfg!(target_os = "macos") {
        "libflags2env.dylib"
    } else if cfg!(target_os = "windows") {
        "flags2env.dll"
    } else {
        "libflags2env.so"
    }
}

#[test]
fn doctor_binding_returns_a_report_and_a_status() {
    // Deliberately does not chdir: doctor resolves .env against the process
    // working directory, and these tests share one process, so changing it
    // would break whichever sibling test happened to run alongside. The
    // finding logic is covered by the C suite (tests/doctor-findings); what is
    // worth proving here is the binding — that the symbols resolve, the owned
    // string comes back intact, and the status maps the way the CLI does.
    let directory = tempfile::tempdir().expect("temp dir");
    let config = directory.path().join(".cli-flags.toml");
    std::fs::write(
        &config,
        "[env]\nfiles = [\"absent.env\"]\n\n[flags.kept]\nenv = \"SMOKE_KEPT\"\naliases = [\"kept\"]\ntype = \"string\"\n",
    )
    .expect("config");

    let parser = flags2env::BundledFlags2Env::new();
    let report = parser
        .doctor(config.to_str().expect("utf-8 path"))
        .expect("doctor runs");

    assert!(report.contains("\"ok\""), "{report}");
    assert!(
        report.contains("listed in env.files but was not readable"),
        "{report}"
    );
    // A missing file is a warning, not an error, so the gate still passes.
    assert!(
        parser
            .doctor_status(config.to_str().expect("utf-8 path"))
            .is_ok(),
        "{report}"
    );
}
