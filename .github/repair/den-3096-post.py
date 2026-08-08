#!/usr/bin/env python3
"""Compatibility correction for the one-shot DEN-3096 repair.

Keep the established libc null-contract check byte-for-byte and layer inferred
local-helper preconditions beside it.  Both carrier scripts are deleted before
the resulting product commit is pushed.
"""

from pathlib import Path

path = Path("tools/borrow-checker/borrow_check.py")
text = path.read_text(encoding="utf-8")

old_map = '''    def nonnull_map(self):
        if self._nonnull_map is None:
            result = {
                name: set(indices)
                for name, indices in self.contracts.null_strict.items()
            }
            for summary in self.summaries.values():
                if summary.nonnull_params:
                    result.setdefault(summary.name, set()).update(
                        summary.nonnull_params)
            self._nonnull_map = result
        return self._nonnull_map
'''
new_map = '''    def nonnull_map(self):
        if self._nonnull_map is None:
            result = {}
            for summary in self.summaries.values():
                if summary.nonnull_params:
                    result.setdefault(summary.name, set()).update(
                        summary.nonnull_params)
            self._nonnull_map = result
        return self._nonnull_map
'''
if text.count(old_map) != 1:
    raise SystemExit("expected exactly one combined null-contract map")
text = text.replace(old_map, new_map, 1)

needle = '''                elif state == UNKNOWN:
                    self.report(loc, "possible-invalid-free",
                                "'%s' has unknown provenance when passed to %s"
                                % (arg_name, name))

        if name in self.summaries and self.summaries[name].returns_owned:
'''
replacement = '''                elif state == UNKNOWN:
                    self.report(loc, "possible-invalid-free",
                                "'%s' has unknown provenance when passed to %s"
                                % (arg_name, name))

            if name in self.contracts.null_strict and \\
                    idx in self.contracts.null_strict[name] and \\
                    state in (MAYBE_NULL, NULLPTR):
                self.report(loc, "null-deref",
                            "'%s' may be NULL when passed to %s; check "
                            "the allocation first" % (arg_name, name))

        if name in self.summaries and self.summaries[name].returns_owned:
'''
if text.count(needle) != 1:
    raise SystemExit("expected exactly one call-contract insertion point")
text = text.replace(needle, replacement, 1)
path.write_text(text, encoding="utf-8")
print("DEN-3096 libc null-contract compatibility preserved")
