use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::{ResolvedCommands, StructuredParse};

unsafe extern "C" {
    fn f2e_parse_json_argv(argv_json: *const c_char) -> *mut c_char;
    fn f2e_parse_json_argv_from_file(
        config_path: *const c_char,
        argv_json: *const c_char,
    ) -> *mut c_char;
    fn f2e_parse_process() -> *mut c_char;
    fn f2e_parse_process_from_file(config_path: *const c_char) -> *mut c_char;
    fn f2e_parse_structured_json_argv(argv_json: *const c_char) -> *mut c_char;
    fn f2e_parse_structured_json_argv_from_file(
        config_path: *const c_char,
        argv_json: *const c_char,
    ) -> *mut c_char;
    fn f2e_resolve_commands_json_argv(argv_json: *const c_char) -> *mut c_char;
    fn f2e_resolve_commands_json_argv_from_file(
        config_path: *const c_char,
        argv_json: *const c_char,
    ) -> *mut c_char;
    fn f2e_audit_config_status() -> i32;
    fn f2e_audit_config_status_from_file(config_path: *const c_char) -> i32;
    fn f2e_free(value: *mut c_char);
}

/// A statically linked flags2env parser.
///
/// This backend compiles the vendored C parser through the crate's build script,
/// so release binaries and minimal containers do not need an external
/// `libflags2env` shared library. Use [`crate::Flags2Env`] only when runtime
/// loading or an explicitly selected shared library is required.
#[derive(Debug, Default, Clone, Copy)]
pub struct BundledFlags2Env;

impl BundledFlags2Env {
    pub const fn new() -> Self {
        Self
    }

    pub fn parse(
        &self,
        argv: &[String],
        config_path: Option<&str>,
    ) -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
        let raw = call_json_argv(
            argv,
            config_path,
            f2e_parse_json_argv,
            f2e_parse_json_argv_from_file,
        )?
        .unwrap_or_else(|| "{}".to_string());
        Ok(serde_json::from_str(&raw)?)
    }

    pub fn parse_process(
        &self,
        config_path: Option<&str>,
    ) -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
        let result = if let Some(config_path) = config_path {
            let config_path = CString::new(config_path)?;
            // SAFETY: the CString lives through the call and the C API returns
            // either NULL or a heap string released by f2e_free.
            unsafe { f2e_parse_process_from_file(config_path.as_ptr()) }
        } else {
            // SAFETY: the C API takes no arguments and returns an owned string.
            unsafe { f2e_parse_process() }
        };
        let raw = take_owned_string(result).unwrap_or_else(|| "{}".to_string());
        Ok(serde_json::from_str(&raw)?)
    }

    pub fn parse_structured(
        &self,
        argv: &[String],
        config_path: Option<&str>,
    ) -> Result<StructuredParse, Box<dyn std::error::Error>> {
        let raw = call_json_argv(
            argv,
            config_path,
            f2e_parse_structured_json_argv,
            f2e_parse_structured_json_argv_from_file,
        )?
        .ok_or("flags2env could not parse argv; check the config path")?;
        let report: serde_json::Value = serde_json::from_str(&raw)?;
        Ok(StructuredParse {
            flags: json_string_map(report.get("flags")),
            command: report
                .get("command")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default()
                .to_string(),
            subcommands: json_string_vec(report.get("subcommands")),
            extras: json_string_vec(report.get("extras")),
            unknown_options: json_string_vec(report.get("unknownOptions")),
            errors: json_string_vec(report.get("errors")),
        })
    }

    pub fn resolve_commands(
        &self,
        argv: &[String],
        config_path: Option<&str>,
    ) -> Result<ResolvedCommands, Box<dyn std::error::Error>> {
        let raw = call_json_argv(
            argv,
            config_path,
            f2e_resolve_commands_json_argv,
            f2e_resolve_commands_json_argv_from_file,
        )?
        .ok_or("flags2env could not resolve commands; check the config path")?;
        let report: serde_json::Value = serde_json::from_str(&raw)?;
        Ok(ResolvedCommands {
            path: json_string_vec(report.get("path")),
            label: report
                .get("label")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default()
                .to_string(),
        })
    }

    pub fn audit_config(
        &self,
        config_path: Option<&str>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let status = if let Some(config_path) = config_path {
            let config_path = CString::new(config_path)?;
            // SAFETY: the CString is valid for the duration of the call.
            unsafe { f2e_audit_config_status_from_file(config_path.as_ptr()) }
        } else {
            // SAFETY: the C API takes no arguments.
            unsafe { f2e_audit_config_status() }
        };
        if status == 0 {
            Ok(())
        } else {
            Err(format!("flags2env config audit failed with status {status}").into())
        }
    }

    pub fn apply(
        &self,
        env_map: &mut HashMap<String, String>,
        argv: &[String],
    ) -> Result<(), Box<dyn std::error::Error>> {
        env_map.extend(self.parse(argv, None)?);
        Ok(())
    }

    pub fn apply_process(
        &self,
        env_map: &mut HashMap<String, String>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        env_map.extend(self.parse_process(None)?);
        Ok(())
    }
}

fn call_json_argv(
    argv: &[String],
    config_path: Option<&str>,
    call: unsafe extern "C" fn(*const c_char) -> *mut c_char,
    call_from_file: unsafe extern "C" fn(*const c_char, *const c_char) -> *mut c_char,
) -> Result<Option<String>, Box<dyn std::error::Error>> {
    let argv_json = CString::new(serde_json::to_string(argv)?)?;
    let result = if let Some(config_path) = config_path {
        let config_path = CString::new(config_path)?;
        // SAFETY: both CStrings remain alive through the call.
        unsafe { call_from_file(config_path.as_ptr(), argv_json.as_ptr()) }
    } else {
        // SAFETY: argv_json is a valid NUL-terminated JSON string.
        unsafe { call(argv_json.as_ptr()) }
    };
    Ok(take_owned_string(result))
}

fn take_owned_string(value: *mut c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    // SAFETY: flags2env returns a NUL-terminated heap string and requires
    // f2e_free to release it exactly once.
    let text = unsafe { CStr::from_ptr(value) }
        .to_string_lossy()
        .into_owned();
    unsafe { f2e_free(value) };
    Some(text)
}

fn json_string_vec(value: Option<&serde_json::Value>) -> Vec<String> {
    value
        .and_then(serde_json::Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default()
}

fn json_string_map(value: Option<&serde_json::Value>) -> HashMap<String, String> {
    value
        .and_then(serde_json::Value::as_object)
        .map(|object| {
            object
                .iter()
                .filter_map(|(key, item)| {
                    item.as_str()
                        .map(|text| (key.clone(), text.to_string()))
                })
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    fn config() -> tempfile::TempDir {
        let dir = tempfile::tempdir().expect("temporary directory");
        fs::write(
            dir.path().join(".cli-flags.toml"),
            r#"
[parse]
allow_unknown = false
unknown_options_env = "UNKNOWN_OPTIONS"
errors_env = "PARSE_ERRORS"

[flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"
default = 3000

[commands.serve]
env = "COMMAND_SERVE"

[commands.serve.flags.bind]
env = "BIND_ADDR"
aliases = ["bind"]
type = "string"
default = "127.0.0.1:8080"
"#,
        )
        .expect("write config");
        dir
    }

    #[test]
    fn bundled_parser_applies_flags_and_scoped_defaults() {
        let dir = config();
        let path = dir.path().join(".cli-flags.toml");
        let argv = vec![
            "app".to_string(),
            "serve".to_string(),
            "--port=4100".to_string(),
        ];
        let parsed = BundledFlags2Env::new()
            .parse(&argv, path.to_str())
            .expect("parse flags");
        assert_eq!(parsed.get("PORT").map(String::as_str), Some("4100"));
        assert_eq!(
            parsed.get("BIND_ADDR").map(String::as_str),
            Some("127.0.0.1:8080")
        );
        assert_eq!(
            parsed.get("COMMAND_SERVE").map(String::as_str),
            Some("true")
        );
    }

    #[test]
    fn bundled_parser_reports_unknown_options_structurally() {
        let dir = config();
        let path = dir.path().join(".cli-flags.toml");
        let argv = vec!["app".to_string(), "--not-declared".to_string()];
        let parsed = BundledFlags2Env::new()
            .parse_structured(&argv, path.to_str())
            .expect("structured parse");
        assert_eq!(parsed.unknown_options, ["--not-declared"]);
    }

    #[test]
    fn bundled_parser_audits_explicit_config() {
        let dir = config();
        let path = dir.path().join(".cli-flags.toml");
        BundledFlags2Env::new()
            .audit_config(path.to_str())
            .expect("valid config");
    }
}
