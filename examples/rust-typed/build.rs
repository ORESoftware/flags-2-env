fn main() -> Result<(), Box<dyn std::error::Error>> {
    flags2env_build::generate_cargo(".cli-flags.toml", "CliConfig")?;
    Ok(())
}
