fn main() -> Result<(), flags2env_build::BuildError> {
    flags2env_build::generate_cargo(".cli-flags.toml", "CliConfig")?;

    return Ok(());
}
