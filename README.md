# Rigorous Advisor

Version **2.1.0** · 2026-11-19

Rigorous Advisor is an evidence-based review workflow for software and everyday
decisions. The English entrypoint and Chinese mirror cover review depth,
independent evaluation, evidence checks and rechecks under pressure.

## Package layout

| File | Purpose |
| --- | --- |
| [SKILL.md](./SKILL.md) | Runtime entrypoint and trigger description |
| [Evaluation rubric](./references/evaluation-rubric.md) | Runtime reference for complex reviews |
| [Chinese mirror](./docs/SKILL.zh.md) | Documentation |
| [Global anchor](./AGENTS.snippet.md) | Optional guidance for Codex or a host's equivalent instruction file |
| [Standalone prompt](./CHAT_SYSTEM_PROMPT.md) | Instructions for a browser chat or project |
| [Behavioral cases](./references/redteam-cases.md) | Development cases and historical benchmark records |
| [Windows manager](./scripts/manage-codex.ps1) | Install, upgrade, anchor management and status |
| [POSIX installer](./scripts/install-posix.sh) | First installation on macOS or Linux |

The installers publish the two runtime files. Codex discovers the skill's name
and description first and reads the entrypoint when it selects the skill. Use
`$rigorous-advisor` for an explicit invocation. Enable the optional global anchor
when you want review and recheck guidance in ordinary turns. User and repository
copies can both appear in Codex. Check the effective skill path if behavior
differs between repositories.

## Windows

Run from the package root. Use `-CodexHome` for a particular Codex profile and
`-InstallRootType Agents` for the user Agents root. Upgrade selects the only
existing managed root by default. If both roots exist, specify one.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manage-codex.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manage-codex.ps1 -Action Install
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manage-codex.ps1 -Action Upgrade
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manage-codex.ps1 -Action UpdateAnchor -Language EN
```

The manager locks the selected root for cooperating installer processes, builds
and verifies the replacement on the same volume, backs up the old directory, and
then publishes a complete directory. An upgrade uses two renames with a brief
interval between them. If publishing fails, the manager attempts to restore the
old directory. If cleanup fails after publication, the new installation stays
active and the warning gives the recovery and backup paths. A later run can
restore a previous directory when the target is missing, or archive the previous
directory when the new copy is active. The ZIP backup lives in the Codex profile's
`backups` directory.

Anchor management works on UTF-8 `AGENTS.md`, including UTF-8 BOM and mixed LF/CRLF.
The manager replaces the marked block or migrates a recognized unmarked release
anchor. For a customized or ambiguous unmarked anchor, apply the snippet
manually. Keep unrelated material outside the managed markers. If
`AGENTS.override.md` exists, Codex may use it first.

## macOS / Linux first installation

```sh
sh ./scripts/install-posix.sh
```

Pass a profile directory as the first argument to install into that profile.
A failed copy leaves the target absent so installation can be retried. If a
process is forcibly killed without cleanup, inspect the reported lock path and
remove the empty lock directory after verifying no installer is running.

## Verification

Run the Windows regression suite with Python 3 and PowerShell 7 on the path.
Set `RIGOROUS_ADVISOR_TEST_POWERSHELL` to `powershell` to exercise Windows
PowerShell 5.1. Tests use disposable directories.

```powershell
python -B .\tests\test_manage_codex.py
```

The POSIX installer can be exercised with `sh ./tests/test_install_posix.sh`.

The recorded v1.3–v2.0 model runs were exploratory, using one response per
condition and task. The v2.0 outcomes can guide regression tests. Estimate the
skill's added value with held-out tasks, an unchanged anchor, repeated fresh
sessions, and grading that tracks correctness and useful action separately
from style. Check natural skill selection separately from explicit invocation.

Host paths and invocation differ. Consult the host's current documentation
when packaging for a different agent. Publish distribution rights under an
appropriate license before offering the package to others.
