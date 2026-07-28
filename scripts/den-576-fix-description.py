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


def table_column(output: str, headers: set[str]) -> str:
''',
    '''def normalized(value: str) -> str:
    value = ANSI_ESCAPE.sub(" ", value)
    value = BOX_DRAWING.sub(" ", value)
    value = value.replace("|", " ").replace("\\r", " ")
    return re.sub(r"\\s+", " ", value).strip()


def semantic_tokens(value: str) -> list[str]:
    # Terminal renderers may vary spacing around punctuation when columns wrap
    # (for example `sql | json`, `machine-readable`, or `CI/AI`). Keep the
    # exact normalized substring as the strongest check, then compare ordered
    # semantic tokens within the already-isolated description column.
    return [
        token.casefold()
        for token in re.findall(r"[A-Za-z0-9]+", normalized(value))
    ]


def description_matches(expected: str, rendered_column: str) -> bool:
    exact = normalized(expected)
    if exact in rendered_column:
        return True
    expected_tokens = semantic_tokens(expected)
    if not expected_tokens:
        return True
    rendered_tokens = iter(semantic_tokens(rendered_column))
    return all(
        any(candidate == token for candidate in rendered_tokens)
        for token in expected_tokens
    )


def table_column(output: str, headers: set[str]) -> str:
''',
)

replace_once(
    "scripts/verify-shell-contract.py",
    '''                if description and normalized(description) not in description_column:
                    raise RuntimeError(
                        f"{label} --help omitted description {description!r}:\\n{output}"
                    )
''',
    '''                if description and not description_matches(
                    description, description_column
                ):
                    raise RuntimeError(
                        f"{label} --help omitted description {description!r}; "
                        f"rendered description column was {description_column!r}:\\n{output}"
                    )
''',
)

replace_once(
    "tests/test_shell_contract_verifier.py",
    '''    def test_command_basename_normalizes_paths_and_rejects_metacharacters(self) -> None:
''',
    '''    def test_description_matching_tolerates_terminal_punctuation_spacing(self) -> None:
        expected = (
            "Output format for diff: sql | json "
            "(machine-readable change plan for CI/AI review)."
        )
        rendered = (
            "Output format for diff: sql  json machine readable change plan "
            "for CI / AI review"
        )
        self.assertTrue(MODULE.description_matches(expected, rendered))
        self.assertFalse(MODULE.description_matches(expected, "Output format only"))

    def test_command_basename_normalizes_paths_and_rejects_metacharacters(self) -> None:
''',
)

print("DEN-576 description verifier fix applied")
