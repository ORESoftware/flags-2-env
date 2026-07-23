mod cli_config;

use cli_config::CliStuff;

fn main() {
    let payload = r#"{
        "PORT": 4242,
        "RATIO": 0.25,
        "DEBUG": true,
        "NAME": "matrix",
        "ITEMS": [1, "two"],
        "LABELS": {"region": "test"},
        "PAYLOAD": {"enabled": true},
        "UNTYPED": "123"
    }"#;

    let config: CliStuff = serde_json::from_str(payload).expect("generated Rust type should deserialize");
    assert_eq!(config.PORT, 4242);
    assert_eq!(config.NAME.as_deref(), Some("matrix"));
    assert_eq!(config.UNTYPED, "123");
    assert_eq!(config.LABELS["region"], "test");

    println!("rust generated interface passed");
}
