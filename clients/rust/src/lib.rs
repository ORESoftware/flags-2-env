pub mod bundled;
pub use bundled::BundledFlags2Env;

use libloading::{Library, Symbol};
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

type ParseFn = unsafe extern "C" fn(*const c_char, *const c_char) -> *mut c_char;
type ParseDefaultFn = unsafe extern "C" fn(*const c_char) -> *mut c_char;
type ParseProcessFn = unsafe extern "C" fn(*const c_char) -> *mut c_char;
type ParseProcessDefaultFn = unsafe extern "C" fn() -> *mut c_char;
type FreeFn = unsafe extern "C" fn(*mut c_char);

/// Structured parse result: each channel is returned separately instead of
/// packed into env keys, so nothing can be shadowed by real environment
/// variables. `flags` is the same map `parse` returns.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct StructuredParse {
    pub flags: HashMap<String, String>,
    pub command: String,
    pub subcommands: Vec<String>,
    pub extras: Vec<String>,
    pub unknown_options: Vec<String>,
    pub errors: Vec<String>,
}

/// The `[commands.*]` path selected by argv, independent of the env map.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ResolvedCommands {
    pub path: Vec<String>,
    pub label: String,
}

fn json_string_vec(value: Option<&serde_json::Value>) -> Vec<String> {
    value
        .and_then(|value| value.as_array())
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
        .and_then(|value| value.as_object())
        .map(|object| {
            object
                .iter()
                .filter_map(|(key, item)| item.as_str().map(|text| (key.clone(), text.to_string())))
                .collect()
        })
        .unwrap_or_default()
}

/// Dynamically loaded flags2env backend.
///
/// Prefer [`BundledFlags2Env`] for self-contained CLI/server binaries and
/// minimal containers. Keep this type for callers that intentionally select a
/// separately installed shared library at runtime.
pub struct Flags2Env {
    library: Library,
}

impl Flags2Env {
    pub unsafe fn load(path: Option<&str>) -> Result<Self, libloading::Error> {
        Ok(Self {
            library: Library::new(path.unwrap_or(default_library_name()))?,
        })
    }

    pub fn parse(&self, argv: &[String], config_path: Option<&str>) -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
        let argv_json = CString::new(serde_json::to_string(argv)?)?;

        unsafe {
            let free: Symbol<FreeFn> = self.library.get(b"f2e_free")?;
            let result = if let Some(config_path) = config_path {
                let config_path = CString::new(config_path)?;
                let parse: Symbol<ParseFn> = self.library.get(b"f2e_parse_json_argv_from_file")?;
                parse(config_path.as_ptr(), argv_json.as_ptr())
            } else {
                let parse: Symbol<ParseDefaultFn> = self.library.get(b"f2e_parse_json_argv")?;
                parse(argv_json.as_ptr())
            };
            if result.is_null() {
                return Ok(HashMap::new());
            }
            let raw = CStr::from_ptr(result).to_string_lossy().to_string();
            free(result);
            Ok(serde_json::from_str(&raw)?)
        }
    }

    pub fn parse_process(&self, config_path: Option<&str>) -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
        unsafe {
            let free: Symbol<FreeFn> = self.library.get(b"f2e_free")?;
            let result = if let Some(config_path) = config_path {
                let config_path = CString::new(config_path)?;
                let parse: Symbol<ParseProcessFn> = self.library.get(b"f2e_parse_process_from_file")?;
                parse(config_path.as_ptr())
            } else {
                let parse: Symbol<ParseProcessDefaultFn> = self.library.get(b"f2e_parse_process")?;
                parse()
            };
            if result.is_null() {
                return Ok(HashMap::new());
            }
            let raw = CStr::from_ptr(result).to_string_lossy().to_string();
            free(result);
            Ok(serde_json::from_str(&raw)?)
        }
    }

    fn call_json_argv(
        &self,
        symbol: &[u8],
        symbol_from_file: &[u8],
        argv: &[String],
        config_path: Option<&str>,
    ) -> Result<Option<String>, Box<dyn std::error::Error>> {
        let argv_json = CString::new(serde_json::to_string(argv)?)?;
        unsafe {
            let free: Symbol<FreeFn> = self.library.get(b"f2e_free")?;
            let result = if let Some(config_path) = config_path {
                let config_path = CString::new(config_path)?;
                let call: Symbol<ParseFn> = self.library.get(symbol_from_file)?;
                call(config_path.as_ptr(), argv_json.as_ptr())
            } else {
                let call: Symbol<ParseDefaultFn> = self.library.get(symbol)?;
                call(argv_json.as_ptr())
            };
            if result.is_null() {
                return Ok(None);
            }
            let raw = CStr::from_ptr(result).to_string_lossy().to_string();
            free(result);
            Ok(Some(raw))
        }
    }

    /// Structured parse: `{flags, command, subcommands, extras,
    /// unknown_options, errors}` as separate channels (dashdash-style).
    /// Extras are the operand tokens: positionals after the last matched
    /// command (including tokens after a bare `--`); with no command matched,
    /// every positional except argv\[0\].
    pub fn parse_structured(
        &self,
        argv: &[String],
        config_path: Option<&str>,
    ) -> Result<StructuredParse, Box<dyn std::error::Error>> {
        let raw = self
            .call_json_argv(
                b"f2e_parse_structured_json_argv",
                b"f2e_parse_structured_json_argv_from_file",
                argv,
                config_path,
            )?
            .ok_or("flags2env could not parse argv; check the config path")?;
        let report: serde_json::Value = serde_json::from_str(&raw)?;
        Ok(StructuredParse {
            flags: json_string_map(report.get("flags")),
            command: report
                .get("command")
                .and_then(|value| value.as_str())
                .unwrap_or_default()
                .to_string(),
            subcommands: json_string_vec(report.get("subcommands")),
            extras: json_string_vec(report.get("extras")),
            unknown_options: json_string_vec(report.get("unknownOptions")),
            errors: json_string_vec(report.get("errors")),
        })
    }

    /// Resolves just the `[commands.*]` path selected by argv.
    pub fn resolve_commands(
        &self,
        argv: &[String],
        config_path: Option<&str>,
    ) -> Result<ResolvedCommands, Box<dyn std::error::Error>> {
        let raw = self
            .call_json_argv(
                b"f2e_resolve_commands_json_argv",
                b"f2e_resolve_commands_json_argv_from_file",
                argv,
                config_path,
            )?
            .ok_or("flags2env could not resolve commands; check the config path")?;
        let report: serde_json::Value = serde_json::from_str(&raw)?;
        Ok(ResolvedCommands {
            path: json_string_vec(report.get("path")),
            label: report
                .get("label")
                .and_then(|value| value.as_str())
                .unwrap_or_default()
                .to_string(),
        })
    }

    pub fn apply(&self, env_map: &mut HashMap<String, String>, argv: &[String]) -> Result<(), Box<dyn std::error::Error>> {
        env_map.extend(self.parse(argv, None)?);
        Ok(())
    }

    pub fn apply_process(&self, env_map: &mut HashMap<String, String>) -> Result<(), Box<dyn std::error::Error>> {
        env_map.extend(self.parse_process(None)?);
        Ok(())
    }
}

fn default_library_name() -> &'static str {
    if cfg!(target_os = "macos") {
        "libflags2env.dylib"
    } else if cfg!(target_os = "windows") {
        "flags2env.dll"
    } else {
        "libflags2env.so"
    }
}
