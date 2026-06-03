use flags2env::Flags2Env;
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

    env::set_current_dir(original).unwrap();
    assert_eq!(parsed.get("DEBUG"), Some(&"true".to_string()));
    assert_eq!(parsed.get("PORT"), Some(&"8181".to_string()));
    assert_eq!(parsed.get("COLOR"), Some(&"true".to_string()));
}
