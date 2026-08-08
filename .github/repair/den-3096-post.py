#!/usr/bin/env python3
"""Exact-source compatibility and waiver corrections for DEN-3096.

Keep the established libc null-contract check byte-for-byte, layer inferred
local-helper preconditions beside it, and replace the live raw-source waiver
scanner only after the main exact-blob repair has installed comment lexing.
All carrier files are deleted before the resulting product commit is pushed.
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

old_waiver = '''    def is_waived(self, line, rule):
        needle = "borrow-check: allow(%s)" % rule
        for idx in (line - 1, line - 2):
            if 0 <= idx < len(self.source_lines):
                text = self.source_lines[idx]
                if needle in text and "--" in text.split(needle, 1)[1]:
                    return True
        return False
'''
new_waiver = r'''    def is_waived(self, line, rule):
        # Inspect the flagged line and immediately preceding line, but only
        # inside lexed C comments. String literals and empty justifications are
        # never waiver authority.
        pattern = re.compile(
            r"(?:^|\s)borrow-check:\s*allow\(\s*%s\s*\)\s*--\s*(\S(?:.*\S)?)\s*$"
            % re.escape(rule))
        for idx in (line - 1, line - 2):
            if 0 <= idx < len(self.comment_lines):
                match = pattern.search(self.comment_lines[idx])
                if match is not None and match.group(1).strip():
                    return True
        return False
'''
if text.count(old_waiver) != 1:
    raise SystemExit("expected exactly one live raw-source waiver method")
text = text.replace(old_waiver, new_waiver, 1)

path.write_text(text, encoding="utf-8")
print("DEN-3096 libc contracts and comment-only waivers preserved")
