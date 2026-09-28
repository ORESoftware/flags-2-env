#![allow(clippy::needless_return)]

use flags2env::{BundledFlags2Env, Flags2EnvError, StructuredParse};
use std::error::Error;

fn assert_send_sync_static<T: Error + Send + Sync + 'static>() {}

#[allow(dead_code)]
fn boxed_error_consumer(
    parser: &BundledFlags2Env,
    argv: &[String],
    config: &str,
) -> Result<StructuredParse, Box<dyn Error + Send + Sync + 'static>> {
    parser.audit_config(Some(config))?;
    let parsed = parser.parse_structured(argv, Some(config))?;
    let _commands = parser.resolve_commands(argv, Some(config))?;
    return Ok(parsed);
}

#[test]
fn public_parser_error_is_thread_safe_and_box_convertible() {
    assert_send_sync_static::<Flags2EnvError>();
    return;
}
