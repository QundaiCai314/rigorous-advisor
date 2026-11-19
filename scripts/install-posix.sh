#!/bin/sh
set -eu

source_root=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd -P)
profile=${1:-${CODEX_HOME:-$HOME/.codex}}
case "$profile" in /*) ;; *) profile="$(pwd -P)/$profile" ;; esac

mkdir -p "$profile"
profile=$(CDPATH= cd -P "$profile" && pwd -P)
skills="$profile/skills"
target="$skills/rigorous-advisor"
lock="$profile/.rigorous-advisor-install.lock.d"
stage=

if ! mkdir "$lock"; then
    printf '%s\n' "Cannot acquire installer lock: $lock" >&2
    exit 1
fi

cleanup() {
    if [ -n "$stage" ]; then rm -rf "$stage"; fi
    rmdir "$lock"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -L "$skills" ]; then
    printf '%s\n' "The skills directory is a symbolic link: $skills" >&2
    exit 1
fi
if [ -e "$target" ] || [ -L "$target" ]; then
    printf '%s\n' "Existing installation at $target" >&2
    exit 1
fi

mkdir -p "$skills"
stage=$(mktemp -d "$skills/.rigorous-advisor-stage.XXXXXXXX")
mkdir -p "$stage/payload/references"
for file in SKILL.md references/evaluation-rubric.md; do
    cp "$source_root/$file" "$stage/payload/$file"
    if ! cmp -s "$source_root/$file" "$stage/payload/$file"; then
        printf '%s\n' "Copy verification failed: $file" >&2
        exit 1
    fi
done
if [ -e "$target" ] || [ -L "$target" ]; then
    printf '%s\n' "An installation appeared at $target" >&2
    exit 1
fi
mv "$stage/payload" "$target"
printf '%s\n' "Installed rigorous-advisor at $target"
