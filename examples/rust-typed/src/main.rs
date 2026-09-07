#[allow(non_snake_case, dead_code)]
mod generated {
    include!(concat!(env!("OUT_DIR"), "/cli_config.rs"));
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let parser = flags2env::BundledFlags2Env::new();
    let config = concat!(env!("CARGO_MANIFEST_DIR"), "/.cli-flags.toml");
    let args = std::env::args().collect::<Vec<_>>();
    let parsed = parser.parse_structured(&args, Some(config))?;
    if !parsed.errors.is_empty() || !parsed.unknown_options.is_empty() {
        return Err("invalid CLI input".into());
    }
    let typed: generated::CliConfig = parser.coerce(&parsed.flags, Some(config))?;
    // This field access intentionally fails to compile when the declaration is
    // renamed. There is no independently maintained Rust default or field map.
    println!("{:?}", typed.JSON_ENABLED);
    Ok(())
}
