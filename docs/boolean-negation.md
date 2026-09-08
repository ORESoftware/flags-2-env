# Boolean negation

Use `--no-json` as the portable, documented spelling for disabling a declared boolean. Git and many other CLIs use the `--no-` convention. A boolean declared with `default = "true"` can be disabled explicitly.

The shared C parser also accepts `'--!json'` and `'--json!'`. Quote bang forms in interactive shells such as Bash, where history expansion may otherwise run before the program receives argv. The quotes are shell syntax, not part of the flag. Completions continue to recommend the portable `--no-` form.

All three spellings assign false; they are not toggles. Repeating a negation stays false. Later argv assignments win: `--no-json --json` enables JSON, while `--json '--!json'` disables it. These assignments use the normal configured source precedence; an explicit order-of-preference policy is not bypassed.

Negation resolves only a declared boolean in the active scope. It does not create flags, disable strings or integers, cross command scopes, rewrite argument values, or reinterpret anything after `--`. Exact declared aliases retain precedence over synthesized negation. Mixed/doubled bangs are rejected as unknown.

Bang aliases do not take an attached value: `--!json=true` and `--json!=false` report parse errors without assigning the flag. Use `--json=false` for an explicit value. The historical `--no-` behavior is preserved. A separated word after a negation remains a positional rather than being silently consumed.

Disabling a requires_tty boolean remains valid without a terminal. Strict applications must check the parser's unknown-option and error channels; retaining a configured default alongside an error is not successful admission.

The implementation lives in the common parser, so clients using the native C core inherit it without a CLI-specific argv rewriting layer. Consumers pinned to older commits must update their immutable dependency and rerun their own tests before claiming support.

References: https://git-scm.com/docs/gitcli and https://www.gnu.org/software/bash/manual/html_node/History-Interaction.html .
