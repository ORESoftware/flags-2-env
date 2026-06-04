use flags2env::Flags2Env;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

struct CwdGuard(PathBuf);

impl Drop for CwdGuard {
    fn drop(&mut self) {
        let _ = env::set_current_dir(&self.0);
    }
}

#[test]
fn parse_finds_parent_config() {
    let original = env::current_dir().unwrap();
    let _cwd_guard = CwdGuard(original);
    let library = compile_test_library();
    let config_root = create_config_tree();

    let sdk = unsafe { Flags2Env::load(Some(library.to_str().unwrap())).unwrap() };
    env::set_current_dir(config_root.join("nested/deeper")).unwrap();
    let parsed = sdk.parse(&["app".into(), "--debug=t".into(), "--port".into(), "8181".into()], None).unwrap();

    assert_eq!(parsed.get("DEBUG"), Some(&"true".to_string()));
    assert_eq!(parsed.get("PORT"), Some(&"8181".to_string()));
    assert_eq!(parsed.get("COLOR"), Some(&"true".to_string()));

    let config_path = config_root.join(".cli-flags.toml");
    let explicit = sdk.parse(&["app".into(), "--debug=f".into()], Some(config_path.to_str().unwrap())).unwrap();
    assert_eq!(explicit.get("DEBUG"), Some(&"false".to_string()));
    assert_eq!(explicit.get("PORT"), Some(&"3000".to_string()));

    let mut combined = HashMap::from([
        ("PORT".to_string(), "env".to_string()),
        ("KEEP".to_string(), "1".to_string()),
    ]);
    sdk.apply(&mut combined, &["app".into(), "--port".into(), "8181".into()]).unwrap();
    assert_eq!(combined.get("PORT"), Some(&"8181".to_string()));
    assert_eq!(combined.get("KEEP"), Some(&"1".to_string()));
    assert_eq!(combined.get("COLOR"), Some(&"true".to_string()));
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

    let status = command.status().expect("failed to start C compiler for Rust smoke test");
    assert!(status.success(), "failed to compile native/parser.c for Rust smoke test");
    output
}

fn create_config_tree() -> PathBuf {
    let root = temp_dir("config");
    fs::create_dir_all(root.join("nested/deeper")).unwrap();
    fs::write(root.join(".cli-flags.toml"), r#"[flags.port]
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
"#).unwrap();
    root
}

fn temp_dir(label: &str) -> PathBuf {
    let path = env::temp_dir().join(format!("flags2env-rust-{label}-{}", std::process::id()));
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
