//! Executable parser-dispatch specification used by unit tests and Kani.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct OptionDecision {
    pub(crate) apply_known: bool,
    pub(crate) report_unknown: bool,
}

/// Model the option-dispatch rules implemented by the native parser.
///
/// `scanning` becomes false after `--`. A known option may be applied only
/// while scanning. An unknown option is reported only in strict mode.
///
/// @var scanning: Bool
/// @var known: Bool
/// @var allowUnknown: Bool
/// @var applyKnown: Bool
/// @var reportUnknown: Bool
/// @assume applyKnown == (scanning && known)
/// @assume reportUnknown == (scanning && !known && !allowUnknown)
/// @ensures !(applyKnown && reportUnknown)
pub(crate) const fn option_decision(
    scanning: bool,
    known: bool,
    allow_unknown: bool,
) -> OptionDecision {
    OptionDecision {
        apply_known: scanning && known,
        report_unknown: scanning && !known && !allow_unknown,
    }
}

/// Model the absorbing option-scanning transition caused by `--`.
///
/// @var scanning: Bool
/// @var endOfOptions: Bool
/// @var scanningAfter: Bool
/// @assume scanningAfter == (scanning && !endOfOptions)
/// @ensures !scanning || !endOfOptions || !scanningAfter
pub(crate) const fn scanning_after(scanning: bool, end_of_options: bool) -> bool {
    scanning && !end_of_options
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct CoercionDecision {
    pub(crate) emit_value: bool,
    pub(crate) report_error: bool,
}

/// Model whether the native coercion loop emits a declared value or reports
/// its conversion error. Inactive command-scoped defaults must remain absent.
///
/// @var supplied: Bool
/// @var hasDefault: Bool
/// @var commandScoped: Bool
/// @var commandActive: Bool
/// @var valueValid: Bool
/// @var attempted: Bool
/// @assume attempted == (supplied || (hasDefault && (!commandScoped || commandActive)))
/// @ensures !(emitValue && reportError)
pub(crate) const fn coercion_decision(
    supplied: bool,
    has_default: bool,
    command_scoped: bool,
    command_active: bool,
    value_valid: bool,
) -> CoercionDecision {
    let attempted = supplied || (has_default && (!command_scoped || command_active));
    CoercionDecision {
        emit_value: attempted && value_valid,
        report_error: attempted && !value_valid,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_and_unknown_effects_are_exclusive() {
        for scanning in [false, true] {
            for known in [false, true] {
                for allow_unknown in [false, true] {
                    let decision = option_decision(scanning, known, allow_unknown);
                    assert!(!(decision.apply_known && decision.report_unknown));
                }
            }
        }
    }

    #[test]
    fn end_of_options_is_absorbing() {
        assert!(!scanning_after(false, false));
        assert!(!scanning_after(false, true));
        assert!(!scanning_after(true, true));
        assert!(scanning_after(true, false));
    }

    #[test]
    fn coercion_effects_are_exclusive_and_scoped_defaults_stay_inactive() {
        for supplied in [false, true] {
            for has_default in [false, true] {
                for command_scoped in [false, true] {
                    for command_active in [false, true] {
                        for value_valid in [false, true] {
                            let decision = coercion_decision(
                                supplied,
                                has_default,
                                command_scoped,
                                command_active,
                                value_valid,
                            );
                            assert!(!(decision.emit_value && decision.report_error));
                        }
                    }
                }
            }
        }

        let inactive_default = coercion_decision(false, true, true, false, true);
        assert!(!inactive_default.emit_value);
        assert!(!inactive_default.report_error);
    }
}

#[cfg(kani)]
mod proofs {
    use super::*;

    #[kani::proof]
    fn known_and_unknown_effects_are_exclusive() {
        let scanning: bool = kani::any();
        let known: bool = kani::any();
        let allow_unknown: bool = kani::any();
        let decision = option_decision(scanning, known, allow_unknown);

        assert!(!(decision.apply_known && decision.report_unknown));
    }

    #[kani::proof]
    fn stopped_scanning_has_no_option_effects() {
        let known: bool = kani::any();
        let allow_unknown: bool = kani::any();
        let decision = option_decision(false, known, allow_unknown);

        assert!(!decision.apply_known);
        assert!(!decision.report_unknown);
    }

    #[kani::proof]
    fn permissive_mode_never_reports_unknown_options() {
        let scanning: bool = kani::any();
        let decision = option_decision(scanning, false, true);

        assert!(!decision.report_unknown);
    }

    #[kani::proof]
    fn end_of_options_stops_scanning() {
        let scanning: bool = kani::any();

        assert!(!scanning_after(scanning, true));
    }

    #[kani::proof]
    fn coercion_never_emits_and_reports_an_error() {
        let decision = coercion_decision(
            kani::any(),
            kani::any(),
            kani::any(),
            kani::any(),
            kani::any(),
        );

        assert!(!(decision.emit_value && decision.report_error));
    }

    #[kani::proof]
    fn inactive_command_default_is_not_materialized() {
        let value_valid: bool = kani::any();
        let decision = coercion_decision(false, true, true, false, value_valid);

        assert!(!decision.emit_value);
        assert!(!decision.report_error);
    }
}
