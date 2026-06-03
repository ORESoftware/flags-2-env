use flags2env::Flags2Env;
use std::collections::HashMap;
use std::env;

#[test]
fn parse_finds_parent_config() {
    let original = env::current_dir().unwrap();
    let library = if cfg!(target_os = "macos") {
        "../../build/libflags2env.dylib"
    } else if cfg!(target_os = "windows") {
        "../../build/flags2env.dll"
    } else {
        "../../build/libflags2env.so"
    };
    let sdk = unsafe { Flags2Env::load(Some(library)).unwrap() };
    env::set_current_dir("../../tests/fixtures/nested/deeper").unwrap();
    let parsed = sdk.parse(&["app".into(), "--debug=t".into(), "--port".into(), "8181".into()], None).unwrap();

    assert_eq!(parsed.get("DEBUG"), Some(&"true".to_string()));
    assert_eq!(parsed.get("PORT"), Some(&"8181".to_string()));
    assert_eq!(parsed.get("COLOR"), Some(&"true".to_string()));

    let explicit = sdk.parse(&["app".into(), "--debug=f".into()], Some("../../.cli-flags.toml")).unwrap();
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

    env::set_current_dir(original).unwrap();
}
