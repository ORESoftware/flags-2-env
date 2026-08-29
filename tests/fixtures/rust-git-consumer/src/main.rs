use flags2env::BundledFlags2Env;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let parser = BundledFlags2Env::new();
    parser.audit_config(Some(".cli-flags.toml"))?;
    let argv = ["consumer", "--port", "4111"].map(String::from);
    let parsed = parser.parse_structured(&argv, Some(".cli-flags.toml"))?;
    assert!(parsed.errors.is_empty());
    assert!(parsed.unknown_options.is_empty());
    assert_eq!(
        parsed.provided_flags.get("CONSUMER_PORT"),
        Some(&"4111".into())
    );
    println!("flags2env git consumer executed with CONSUMER_PORT=4111");
    Ok(())
}
