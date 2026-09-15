use flags2env::BundledFlags2Env;

const CONTRACT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/.cli-flags.toml");

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let parser = BundledFlags2Env::new();
    parser.audit_config(Some(CONTRACT))?;
    let argv = ["consumer", "--port", "4111"].map(String::from);
    let parsed = parser.parse_structured(&argv, Some(CONTRACT))?;
    assert!(parsed.errors.is_empty());
    assert!(parsed.unknown_options.is_empty());
    assert!(parsed.extras.is_empty());
    assert_eq!(
        parsed.provided_flags.get("CONSUMER_PORT"),
        Some(&"4111".into())
    );
    println!("flags2env git consumer executed with CONSUMER_PORT=4111");
    Ok(())
}
