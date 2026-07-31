from pathlib import Path

path = Path("tests/run.sh")
text = path.read_text(encoding="utf-8")
old = "  *'Command: tool [COMMAND] [OPTIONS]'*'| ws '*'| ws remote '*'| ws remote add '*'| ws remote add tag '*)"
new = "  *'Command: tool [COMMAND] [OPTIONS]'*'| ws, workspace '*'| ws remote, remotes '*'| ws remote add, create '*'| ws remote add tag, annotate '*)"
if text.count(old) != 1:
    raise RuntimeError("deep-help expectation anchor changed")
path.write_text(text.replace(old, new), encoding="utf-8")
