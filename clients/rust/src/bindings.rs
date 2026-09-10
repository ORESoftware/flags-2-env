//! Fail-closed binding of domain configuration declarations to a final flags-2-env snapshot.
//!
//! Domain packages remain responsible for parsing and semantically validating their own
//! configuration files (for example `.ores-chat.toml` or `.auth-shared.toml`). After admission,
//! they can pass symbolic field -> environment-key declarations here. This module never parses
//! argv, reads process environment, reads TOML, or mutates `std::env`; it only resolves against
//! the immutable [`EnvMap`](crate::EnvMap) supplied by the caller.

use std::{collections::BTreeMap, fmt};

use crate::{env_value, EnvMap};

/// Redacted error returned while binding admitted domain configuration to RuntimeConfig.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BindingError {
    /// A symbolic configuration field name is empty or unsafe for diagnostics.
    InvalidField,
    /// An admitted declaration references a malformed environment-key name.
    InvalidEnvKey { field: String },
    /// Two semantic fields reference the same environment key.
    DuplicateEnvKey { field: String },
    /// The final flags-2-env snapshot has no non-empty value for a declared field.
    MissingValue { field: String },
}

impl BindingError {
    /// Stable code suitable for startup diagnostics and fleet audit findings.
    #[must_use]
    pub const fn code(&self) -> &'static str {
        match self {
            Self::InvalidField => "invalid-field",
            Self::InvalidEnvKey { .. } => "invalid-env-key",
            Self::DuplicateEnvKey { .. } => "duplicate-env-key",
            Self::MissingValue { .. } => "missing-value",
        }
    }
}

impl fmt::Display for BindingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidField => formatter.write_str("domain config binding field is invalid"),
            Self::InvalidEnvKey { field } => write!(
                formatter,
                "domain config binding for {field} has an invalid environment key"
            ),
            Self::DuplicateEnvKey { field } => write!(
                formatter,
                "domain config binding for {field} reuses an environment key"
            ),
            Self::MissingValue { field } => write!(
                formatter,
                "domain config binding for {field} is missing from RuntimeConfig"
            ),
        }
    }
}

impl std::error::Error for BindingError {}

/// Resolve symbolic domain-config fields against an immutable flags-2-env environment snapshot.
///
/// `declarations` must come from a domain configuration document that has already passed that
/// domain's independent TypeSpec/JSON Schema admission. Environment-key names must use the
/// portable `^[A-Z_][A-Z0-9_]*$` grammar. A single environment key cannot silently control two
/// semantic fields, and empty/missing values fail closed.
///
/// Returned values are keyed by symbolic field name so downstream typed adapters never need to
/// re-read process environment or re-run argv parsing.
///
/// # Errors
/// Returns a redacted [`BindingError`]. Runtime values are never included in diagnostics.
pub fn resolve_bindings(
    env: &EnvMap,
    declarations: &BTreeMap<String, String>,
) -> Result<BTreeMap<String, String>, BindingError> {
    let mut resolved = BTreeMap::new();
    let mut owners = BTreeMap::<&str, &str>::new();

    for (field, env_key) in declarations {
        if !valid_field(field) {
            return Err(BindingError::InvalidField);
        }
        if !valid_env_key(env_key) {
            return Err(BindingError::InvalidEnvKey {
                field: field.clone(),
            });
        }
        if owners.insert(env_key.as_str(), field.as_str()).is_some() {
            return Err(BindingError::DuplicateEnvKey {
                field: field.clone(),
            });
        }
        let value = env_value(env, env_key)
            .ok_or_else(|| BindingError::MissingValue {
                field: field.clone(),
            })?
            .to_owned();
        resolved.insert(field.clone(), value);
    }

    Ok(resolved)
}

fn valid_field(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value.bytes().all(|byte| {
            byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-')
        })
}

fn valid_env_key(value: &str) -> bool {
    let Some(first) = value.bytes().next() else {
        return false;
    };
    (first.is_ascii_uppercase() || first == b'_')
        && value
            .bytes()
            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'_')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn declarations() -> BTreeMap<String, String> {
        BTreeMap::from([
            ("auth.authority".to_string(), "SHARED_AUTH_URL".to_string()),
            ("auth.callback".to_string(), "AUTH_CALLBACK_URL".to_string()),
        ])
    }

    #[test]
    fn resolves_only_declared_values_from_final_snapshot() {
        let env = EnvMap::from([
            (
                "SHARED_AUTH_URL".to_string(),
                "https://auth.example.test".to_string(),
            ),
            (
                "AUTH_CALLBACK_URL".to_string(),
                "https://app.example.test/callback".to_string(),
            ),
            (
                "UNRELATED_SECRET".to_string(),
                "must-not-leak".to_string(),
            ),
        ]);
        let resolved = resolve_bindings(&env, &declarations()).unwrap();
        assert_eq!(resolved.len(), 2);
        assert_eq!(resolved["auth.authority"], "https://auth.example.test");
        assert!(!resolved.values().any(|value| value == "must-not-leak"));
    }

    #[test]
    fn missing_or_empty_runtime_values_fail_closed() {
        let mut env = EnvMap::from([(
            "SHARED_AUTH_URL".to_string(),
            "https://auth.example.test".to_string(),
        )]);
        assert_eq!(
            resolve_bindings(&env, &declarations()),
            Err(BindingError::MissingValue {
                field: "auth.callback".to_string(),
            })
        );
        env.insert("AUTH_CALLBACK_URL".to_string(), "  ".to_string());
        assert!(matches!(
            resolve_bindings(&env, &declarations()),
            Err(BindingError::MissingValue { .. })
        ));
    }

    #[test]
    fn malformed_and_reused_env_keys_are_rejected() {
        let env = EnvMap::from([("GOOD_KEY".to_string(), "value".to_string())]);
        let malformed = BTreeMap::from([("feature.url".to_string(), "bad-key".to_string())]);
        assert!(matches!(
            resolve_bindings(&env, &malformed),
            Err(BindingError::InvalidEnvKey { .. })
        ));

        let duplicate = BTreeMap::from([
            ("feature.one".to_string(), "GOOD_KEY".to_string()),
            ("feature.two".to_string(), "GOOD_KEY".to_string()),
        ]);
        assert!(matches!(
            resolve_bindings(&env, &duplicate),
            Err(BindingError::DuplicateEnvKey { .. })
        ));
    }

    #[test]
    fn failures_never_reflect_runtime_values() {
        let marker = "synthetic-secret-never-reflect";
        let env = EnvMap::from([("SHARED_AUTH_URL".to_string(), marker.to_string())]);
        let error = resolve_bindings(&env, &declarations()).unwrap_err();
        let rendered = format!("{error:?} {error}");
        assert!(!rendered.contains(marker));
    }
}
