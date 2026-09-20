#!/bin/sh
set -eu

SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail(){ echo "ores-lint hook contract: $*" >&2; exit 1; }

new_repo(){
  repo="$TMP/$1"
  git init -q "$repo"
  mkdir -p "$repo/.ores-lint"
  cp "$SOURCE_ROOT/.ores-lint/install-git-hooks.sh" "$repo/.ores-lint/install-git-hooks.sh"
  cat > "$repo/.ores-lint/lint.sh" <<'LINT'
#!/bin/sh
set -eu
printf '%s\n' ran > .ores-lint/lint-ran
LINT
  chmod +x "$repo/.ores-lint/lint.sh"
  printf '%s\n' "$repo"
}

repo=$(new_repo default)
(cd "$repo" && sh .ores-lint/install-git-hooks.sh >/dev/null)
hook="$(git -C "$repo" rev-parse --absolute-git-dir)/hooks/pre-push"
[ -x "$hook" ] || fail 'default hook missing'
(cd "$repo" && "$hook")
[ -f "$repo/.ores-lint/lint-ran" ] || fail 'default hook did not run lint'

repo=$(new_repo relative)
git -C "$repo" config core.hooksPath .githooks
(cd "$repo" && sh .ores-lint/install-git-hooks.sh >/dev/null)
[ -x "$repo/.githooks/pre-push" ] || fail 'relative hooksPath ignored'
test "$(git -C "$repo" config --get core.hooksPath)" = .githooks

repo=$(new_repo absolute)
absolute="$TMP/absolute-hooks"
git -C "$repo" config core.hooksPath "$absolute"
(cd "$repo" && sh .ores-lint/install-git-hooks.sh >/dev/null)
[ -x "$absolute/pre-push" ] || fail 'absolute hooksPath ignored'

repo=$(new_repo tilde)
home="$TMP/home"; mkdir -p "$home"
git -C "$repo" config core.hooksPath '~/custom-hooks'
(cd "$repo" && HOME="$home" sh .ores-lint/install-git-hooks.sh >/dev/null)
[ -x "$home/custom-hooks/pre-push" ] || fail 'literal tilde hooksPath ignored'

repo=$(new_repo conflict)
git -C "$repo" config core.hooksPath .githooks
mkdir -p "$repo/.githooks"
printf '%s\n' '#!/bin/sh' 'echo keep-me' > "$repo/.githooks/pre-push"
chmod +x "$repo/.githooks/pre-push"
if (cd "$repo" && sh .ores-lint/install-git-hooks.sh) >"$TMP/conflict.out" 2>&1; then
  fail 'unrelated hook was accepted'
fi
grep -Fq 'refusing to clobber' "$TMP/conflict.out" || fail 'conflict refusal missing'
grep -Fq 'keep-me' "$repo/.githooks/pre-push" || fail 'existing hook was modified'

printf '%s\n' 'ores-lint hook contract: PASS'
