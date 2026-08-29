//! Immutable environment snapshots for flags-2-env consumers.
//!
//! Process environment and argv are copied at the application boundary.
//! CLI overrides merge into an ordinary map. This module never writes
//! `std::env`.

use std::collections::BTreeMap;

use crate::Flags2Env;

/// Deterministic environment snapshot. Prefer this over mutating process env.
pub type EnvMap = BTreeMap<String, String>;

/// Pure merge: later override entries win over the initial map.
pub fn get_env_map(
    initial: EnvMap,
    overrides: impl IntoIterator<Item = (String, String)>,
) -> EnvMap {
    overrides
        .into_iter()
        .fold(initial, |mut env, (key, value)| {
            env.insert(key, value);
            env
        })
}

/// Return a trimmed non-empty value from an environment snapshot.
pub fn env_value<'a>(env: &'a EnvMap, key: &str) -> Option<&'a str> {
    env.get(key)
        .map(String::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

/// Copy the process environment. Impure boundary helper.
pub fn process_env_map() -> EnvMap {
    std::env::vars().collect()
}

/// Copy process arguments. Impure boundary helper.
pub fn process_argv() -> Vec<String> {
    std::env::args().collect()
}

/// Parse argv through the dynamically loaded flags2env library.
///
/// Does not write the process environment. Prefer [`BundledFlags2Env`] in
/// binaries that statically link the parser, then pass the resulting flags
/// into [`get_env_map`].
pub fn cli_overrides(argv: &[String]) -> Result<EnvMap, String> {
    let parser = unsafe { Flags2Env::load(None) }
        .map_err(|error| format!("flags-2-env unavailable: {error}"))?;
    parser
        .parse(argv, None)
        .map(|overrides| overrides.into_iter().collect())
        .map_err(|error| format!("invalid CLI flags: {error}"))
}

/// Merge argv overrides into a copied environment without process mutation.
///
/// Load or parse failures keep `initial`, matching the historical fallback
/// that left process env unchanged on error.
pub fn env_map_from_argv(initial: EnvMap, argv: &[String]) -> EnvMap {
    match cli_overrides(argv) {
        Ok(overrides) => get_env_map(initial, overrides),
        Err(_) => initial,
    }
}

/// Build the application environment: process env + CLI overrides.
pub fn current_env_map() -> EnvMap {
    env_map_from_argv(process_env_map(), &process_argv())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cli_values_override_environment_values() {
        let initial = EnvMap::from([
            ("PORT".into(), "3000".into()),
            ("HOST".into(), "localhost".into()),
        ]);
        let overrides = EnvMap::from([("PORT".into(), "8080".into())]);
        let env = get_env_map(initial, overrides);

        assert_eq!(env.get("PORT").map(String::as_str), Some("8080"));
        assert_eq!(env.get("HOST").map(String::as_str), Some("localhost"));
    }

    #[test]
    fn empty_override_still_wins() {
        let initial = EnvMap::from([("RUST_LOG".into(), "info".into())]);
        let env = get_env_map(initial, [("RUST_LOG".into(), String::new())]);
        assert_eq!(env.get("RUST_LOG").map(String::as_str), Some(""));
        assert_eq!(env_value(&env, "RUST_LOG"), None);
    }

    #[test]
    fn merge_does_not_mutate_process_environment() {
        let before = std::env::var_os("FLAGS2ENV_ENV_MAP_PROBE");
        let env = get_env_map(
            EnvMap::from([("FLAGS2ENV_ENV_MAP_PROBE".into(), "base".into())]),
            [("FLAGS2ENV_ENV_MAP_PROBE".into(), "override".into())],
        );
        assert_eq!(
            env.get("FLAGS2ENV_ENV_MAP_PROBE").map(String::as_str),
            Some("override")
        );
        assert_eq!(std::env::var_os("FLAGS2ENV_ENV_MAP_PROBE"), before);
    }

    #[test]
    fn source_does_not_write_process_environment() {
        const SRC: &str = include_str!("env_map.rs");
        let production = SRC.split("#[cfg(test)]").next().unwrap_or(SRC);
        assert!(!production.contains("set_var"));
    }
}
