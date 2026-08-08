#!/usr/bin/env python3
"""Align the one-shot carrier with the exact live waiver method signature."""

from pathlib import Path

path = Path(".github/repair/den-3096.py")
text = path.read_text(encoding="utf-8")

old = '''    """    def is_waived(self, rule, line):
        needle = \\"borrow-check: allow(%s)\\" % rule
        # line is 1-based; inspect flagged line and immediately preceding line
        for idx in (line - 1, line - 2):
            if 0 <= idx < len(self.source_lines):
                text = self.source_lines[idx]
                if needle in text:
                    suffix = text[text.index(needle) + len(needle):]
                    if \\"--\\" in suffix:
                        return True
        return False
""",
'''
new = '''    """    def is_waived(self, line, rule):
        needle = \\"borrow-check: allow(%s)\\" % rule
        for idx in (line - 1, line - 2):
            if 0 <= idx < len(self.source_lines):
                text = self.source_lines[idx]
                if needle in text and \\"--\\" in text.split(needle, 1)[1]:
                    return True
        return False
""",
'''
if text.count(old) != 1:
    raise SystemExit(
        "carrier fix expected exactly one stale waiver source block, found %d"
        % text.count(old)
    )
text = text.replace(old, new, 1)

old_signature = "r'''    def is_waived(self, rule, line):"
new_signature = "r'''    def is_waived(self, line, rule):"
if text.count(old_signature) != 1:
    raise SystemExit(
        "carrier fix expected exactly one stale waiver replacement signature, found %d"
        % text.count(old_signature)
    )
text = text.replace(old_signature, new_signature, 1)
path.write_text(text, encoding="utf-8")
print("DEN-3096 carrier aligned to live waiver signature")
