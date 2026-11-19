#!/bin/sh
set -eu

installer=$(CDPATH= cd -P "$(dirname "$0")/../scripts" && pwd -P)/install-posix.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' 0

profile="$fixtures/space [brackets]"
sh "$installer" "$profile"
test -f "$profile/skills/rigorous-advisor/SKILL.md"
test -f "$profile/skills/rigorous-advisor/references/evaluation-rubric.md"
test ! -e "$profile/skills/rigorous-advisor/references/redteam-cases.md"
if sh "$installer" "$profile"; then exit 1; fi

(cd "$fixtures" && sh "$installer" '-relative')
test -f "$fixtures/-relative/skills/rigorous-advisor/SKILL.md"

fake_commands="$fixtures/fake-commands"
mkdir "$fake_commands"
real_cp=$(command -v cp)
export RIGOROUS_ADVISOR_REAL_CP="$real_cp"
cat > "$fake_commands/cp" <<'SH'
#!/bin/sh
case "$1" in *evaluation-rubric.md) exit 71 ;; esac
exec "$RIGOROUS_ADVISOR_REAL_CP" "$@"
SH
chmod +x "$fake_commands/cp"

failed_profile="$fixtures/failed"
if PATH="$fake_commands:$PATH" sh "$installer" "$failed_profile"; then exit 1; fi
test ! -e "$failed_profile/skills/rigorous-advisor"
test ! -e "$failed_profile/.rigorous-advisor-install.lock.d"
sh "$installer" "$failed_profile"
test -f "$failed_profile/skills/rigorous-advisor/references/evaluation-rubric.md"

printf '%s\n' 'POSIX installer regression tests passed.'
