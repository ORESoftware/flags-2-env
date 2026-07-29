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
}
