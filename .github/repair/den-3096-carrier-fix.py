#!/usr/bin/env python3
"""Make the main carrier defer waiver parsing to the exact-source post-step."""

from pathlib import Path

path = Path(".github/repair/den-3096.py")
text = path.read_text(encoding="utf-8")
start_marker = '''text = replace_once(
    text,
    """    def is_waived'''
end_marker = '''    "comment-only waiver parser",
)
'''
start = text.find(start_marker)
if start < 0:
    raise SystemExit("carrier fix could not find the waiver replacement start")
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit("carrier fix could not find the waiver replacement end")
end += len(end_marker)
if text.find(start_marker, end) >= 0:
    raise SystemExit("carrier fix found more than one waiver replacement block")
text = (
    text[:start]
    + "# Waiver parsing is patched from the exact live source by den-3096-post.py.\n"
    + text[end:]
)
path.write_text(text, encoding="utf-8")
print("DEN-3096 main carrier now defers waiver parsing to the post-step")
