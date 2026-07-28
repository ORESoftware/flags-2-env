#!/usr/bin/env python3
"""Apply the narrow DEN-576 terminal-description verifier fix exactly once."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    content = target.read_text(encoding="utf-8")
    count = content.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one replacement target, found {count}")
    target.write_text(content.replace(old, new, 1), encoding="utf-8")


replace_once(
    "scripts/verify-shell-contract.py",
    '''def normalized(value: str) -> str:
    value = ANSI_ESCAPE.sub(" ", value)
    value = BOX_DRAWING.sub(" ", value)
    value = value.replace("|", " ").replace("\\r", " ")
    return re.sub(r"\\s+", " ", value).strip()


def visible_flags(config: dict, command: str) -> list[tuple[str, dict]]:
''',
    '''def normalized(value: str) -> str:
    value = ANSI_ESCAPE.sub(" ", value)
    value = BOX_DRAWING.sub(" ", value)
    value = value.replace("|", " ").replace("\\r", " ")
    return re.sub(r"\\s+", " ", value).strip()


def semantic_tokens(value: str) -> list[str]:
    # Terminal table renderers may add/remove spacing around punctuation when
    # columns wrap (for example `sql | json` or `CI/AI`). Compare the ordered
    # semantic tokens inside the extracted description column while retaining
    # the exact normalized substring as the first, strongest check.
    return [token.casefold() for token in re.findall(r"[A-Za-z0-9]+", normalized(value))]


def description_matches(expected: str, rendered_column: str) -> bool:
    exact = normalized(expected)
    if exact in rendered_column:
        return True
    expected_tokens = semantic_tokens(expected)
    if not expected_tokens:
        return True
    rendered = iter(semantic_tokens(rendered_column))
    return all(any(candidate == token for candidate in rendered) for token in expected_tokens)


def visible_flags(config: dict, command: str) -> list[tuple[str, dict]]:
''',
)

replace_once(
    "scripts/verify-shell-contract.py",
    '''            description = spec.get("help", "")
            if description and normalized(description) not in description_column:
                raise Failure(
                    f"flags2env shell contract: {command} --help omitted description "
                    f"{description!r}:\\n{output}"
                )
''',
    '''            description = spec.get("help", "")
            if description and not description_matches(description, description_column):
                raise Failure(
                    f"flags2env shell contract: {command} --help omitted description "
                    f"{description!r}; rendered description column was "
                    f"{description_column!r}:\\n{output}"
                )
''',
)

replace_once(
    "tests/test_shell_contract_verifier.py",
    '''from verify_shell_contract import aliases_for, option_tokens, table_column
''',
    '''from verify_shell_contract import (
    aliases_for,
    description_matches,
    option_tokens,
    table_column,
)
''',
)

replace_once(
    "tests/test_shell_contract_verifier.py",
    '''    def test_duplicate_aliases_are_rejected(self):
''',
    '''    def test_description_matching_tolerates_terminal_punctuation_spacing(self):
        expected = (
            "Output format for diff: sql | json "
            "(machine-readable change plan for CI/AI review)."
        )
        rendered = (
            "Output format for diff: sql  json machine readable change plan "
            "for CI / AI review"
        )
        self.assertTrue(description_matches(expected, rendered))
        self.assertFalse(description_matches(expected, "Output format only"))

    def test_duplicate_aliases_are_rejected(self):
''',
)

print("DEN-576 description verifier fix applied")
