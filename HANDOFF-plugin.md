# Handoff: package claude-statusline as a Claude Code plugin

Lives on the `feat/plugin` branch. Delete it in the commit that finishes the work.

## Goal

Let Claude Code users install the status line from inside Claude Code
(`/plugin marketplace add rinman24/claude-statusline`, `/plugin install`, then a
setup command) without chezmoi, curl or a clone. The curl/clone `install.sh`
path and Rich's chezmoi external must keep working unchanged.

Rich's rule: do this only once the repo is stable, meaning a few releases
without changes to the layout or behavior.

## Where things stand (2026-10-08)

- `v1.0.0` is released. The repo root has `statusline.sh`, `install.sh`,
  `tests/statusline-harness.py`, `tests/test-install.sh`, and a CI workflow
  covering macOS (bash 3.2), Ubuntu, Debian-slim and Alpine.
- `install.sh` copies the script to `~/.claude/statusline.sh` and sets only
  `statusLine` in `~/.claude/settings.json` with `jq`. Run from a checkout
  (`sh <dir>/install.sh`), it installs that checkout's `statusline.sh`, so it
  already works when run as `${CLAUDE_PLUGIN_ROOT}/install.sh`.
- Rich's machines get the script from dotfiles: `.chezmoiexternal.toml` pins a
  tag, and `private_dot_claude/modify_settings.json` sets `statusLine` to
  `~/.claude/statusline.sh` on every `chezmoi apply`.
- The per-machine toggles `~/.claude/statusline-size` (`small`/`medium`) and
  `~/.claude/statusline-track` (`dots`) are unmanaged on purpose.

## What the platform allows (checked 2026-10-08, Claude Code 2.1.286)

Sources: https://code.claude.com/docs/en/plugins/manifest-reference,
.../plugins/marketplace-reference, .../plugins/install,
.../plugins/components, https://code.claude.com/docs/en/statusline

- **A plugin cannot set `statusLine`.** A plugin's `settings.json`, or the
  `settings` field in its manifest, honors only `agent` and
  `subagentStatusLine`; other keys are dropped at load. So a setup step has to
  write `statusLine` into the user's `~/.claude/settings.json`.
- **`${CLAUDE_PLUGIN_ROOT}` changes on every plugin update** ("don't write
  state there"). It is resolved in hook commands and skill/command bodies, and
  exported to hook processes. It is *not* documented as expanding inside a
  user's `statusLine.command`, so assume it doesn't. Never point `statusLine`
  at the plugin root.
- **`${CLAUDE_PLUGIN_DATA}`** is `~/.claude/plugins/data/<id>/`, with `<id>`
  being `plugin@marketplace` with non-alphanumerics turned into `-`. It
  persists across updates and is exported to hook processes.
- **The repo root can be both the marketplace and the plugin.**
  `.claude-plugin/marketplace.json` lists one plugin with `"source": "./"`, and
  `.claude-plugin/plugin.json` sits at the root. Only `name` is required in
  `plugin.json`. `marketplace.json` requires `name`, `owner.name` and
  `plugins`.
- **Slash commands:** `skills/<name>/SKILL.md` is the current format;
  `commands/<name>.md` still works. A body can tell Claude to run
  `sh "${CLAUDE_PLUGIN_ROOT}/install.sh"`.
- **Hooks:** a plugin can ship `hooks/hooks.json` (same shape as the `hooks`
  key in settings), including `SessionStart`.
- **No uninstall or disable hook exists.** Removing the plugin leaves whatever
  setup wrote to `settings.json` in place.
- **Updates:** third-party marketplaces don't auto-update by default. Users run
  `claude plugin marketplace update <mkt>` and `claude plugin update
  <plugin>@<mkt>`, or use the `/plugin` Installed tab. The manifest `version`
  pins users; raising it releases the update.
- **Scriptable install:** `claude plugin marketplace add rinman24/claude-statusline`
  then `claude plugin install <plugin>@<mkt>`.
- **`subagentStatusLine` is native to plugins.** It renders a custom body for
  each subagent row in the agent panel below the prompt. Input on stdin: the base
  hook fields, `columns`, and `tasks[]` (`id`, `name?`, `agentType`, `status`,
  `description`, `label`, `startTime`, `model?`, `effort?`,
  `contextWindowSize?`, `tokenCount`, `tokenSamples` with up to 16 readings).
  Output: one JSON line per row, `{"id": "...", "content": "<ANSI text>"}`; an
  omitted id keeps the default row, and empty content hides the row. The same
  trust, `disableAllHooks` and `allowManagedHooksOnly` gates as `statusLine`
  apply.
- **Organization settings can hide it.** If managed settings set
  `allowManagedHooksOnly`, a user's custom `statusLine` silently disappears.
  This matters for GenShift teammates; mention it in the troubleshooting docs.
- **Mods are out of scope.** `$.ui.status(text)` pins one plain line, and an
  `AbovePrompt` band would mean rewriting the script in TSX, drawn above the
  prompt rather than in the status line slot.

## Upstream precedent

AwesomeZun/CC-statusline ships exactly this pattern:
- `.claude-plugin/marketplace.json` with one plugin, `"source": "./"`,
  `category: "tools"`, and `version` repeated in both manifests.
- `commands/statusline-setup.md`, which asks for a size with AskUserQuestion
  and never installs without one. It runs
  `bash "${CLAUDE_PLUGIN_ROOT}/install.sh" <size>`, then confirms that
  `statusLine` was written and tells the user to restart.
- Its `install.sh` copies the renderer to `~/.claude/awesome-statusline.*` and
  backs up `settings.json` before writing.
- Its command also handles auto mode refusing to run third-party code: it
  falls back to asking the user to run `! bash install.sh <size>` themselves.

## Proposed design

1. **Manifests.**
   - `.claude-plugin/plugin.json`: `name`, `version`, `description`, `author`
     (Rich Inman, PhD), `homepage`, `license: MIT`, `keywords`.
   - `.claude-plugin/marketplace.json`: one plugin, `"source": "./"`.
   - Pick the marketplace and plugin names (see open questions).
2. **`skills/statusline-setup/SKILL.md`** (or `commands/` if skills turn out to
   behave differently for user-invoked commands).
   - Ask for small or medium unless `$ARGUMENTS` names one. Ask whether to use
     the ⣿ track only if the user mentions dots or font problems.
   - Read the current `statusLine` and ask before replacing someone else's.
   - Run `install.sh`, verify the result, and say whether a restart is needed.
   - Write the size choice to `~/.claude/statusline-size`. That keeps it a
     per-machine toggle, not a setting.
   - Add an `uninstall` argument that restores the previous `statusLine` (see
     5).
3. **Where the installed script lives** (decision for Rich, see open
   questions):
   - **a. `~/.claude/statusline.sh`** (today's path). Simple, but on chezmoi
     machines it collides with the dotfiles external, and nothing refreshes it
     after a plugin update unless a hook copies it.
   - **b. `${CLAUDE_PLUGIN_DATA}/statusline.sh`** (recommended). It's stable
     across updates and doesn't collide with chezmoi. A `SessionStart` hook
     re-copies `${CLAUDE_PLUGIN_ROOT}/statusline.sh` there when they differ,
     so plugin updates reach the status line without re-running setup.
     `statusLine.command` must then be the absolute expanded path, which is
     fine because `settings.json` is per-machine anyway. `install.sh` would
     need a destination override (e.g. `CLAUDE_STATUSLINE_DEST`), plus tests.
4. **Chezmoi machines.** `modify_settings.json` re-points `statusLine` at
   `~/.claude/statusline.sh` on every apply, so on Rich's machines the plugin
   and chezmoi would fight over that key. The simplest rule is that Rich's
   machines keep chezmoi and don't install the plugin. Write that down in the
   README.
5. **Uninstall.** Since there's no uninstall hook:
   - Have `install.sh` save the replaced `statusLine` value (e.g. to
     `${CLAUDE_PLUGIN_DATA}/previous-statusline.json`, or
     `~/.claude/statusline-previous.json` for curl installs).
   - Add `install.sh --uninstall`, which restores that value or deletes the
     key.
   - Have the README say to run `/statusline-setup uninstall` before
     `/plugin uninstall`.
   - Check what happens to `${CLAUDE_PLUGIN_DATA}` on uninstall. If it's
     deleted, a leftover `statusLine` pointing there renders blank, which is
     harmless but confusing.
6. **Versioning.**
   - `plugin.json` `version`, `marketplace.json` `version` and the git tag
     must match. Add a CI check that fails when they drift.
   - Plugin work is a minor bump (`v1.1.0`). Bump dotfiles'
     `.chezmoiexternal.toml` only if `statusline.sh` itself changed.
7. **CI.**
   - Validate both manifests with `jq`.
   - Run `claude plugin validate .` if it works in CI without auth (install
     `@anthropic-ai/claude-code` with npm).
   - Extend `tests/test-install.sh` for the destination override, the saved
     previous value and `--uninstall`.
8. **Phase 2, optional: `subagent-statusline.sh`.** A Mocha renderer for
   subagent rows, shipped through the plugin's own `settings.json`
   `subagentStatusLine`, so it needs no setup at all. Each row could show the
   name, the model, a context bar from `tokenCount / contextWindowSize` in the
   same gradient, a sparkline from `tokenSamples`, and the status. It needs its
   own harness cases.
9. **Docs.**
   - README: an "Install as a Claude Code plugin" section, the chezmoi caveat,
     uninstall order, and the `allowManagedHooksOnly` note.
   - Move the plugin-specific troubleshooting (auto mode declining the
     install, restart, workspace trust) into the skill body as well, since the
     README isn't loaded when the skill runs.

## Verify before building

- Whether `${CLAUDE_PLUGIN_ROOT}` expands inside a `subagentStatusLine.command`
  set in the plugin's own `settings.json`. It has to, for phase 2.
- Whether a `statusLine` change written to `settings.json` mid-session takes
  effect without a restart. Settings may hot-reload in current builds.
- What `claude plugin uninstall` does to `~/.claude/plugins/data/<id>/`.
- Whether marketplace or plugin names starting with `claude-` are reserved or
  rejected as impersonating official marketplaces.
- Whether `claude plugin validate` runs in CI without logging in.
- How auto mode and permission prompts treat the setup skill running
  `install.sh`. Upstream had to add a "run it yourself with `!`" fallback.
- Whether a `SessionStart` hook's file copy finishes before the first status
  line render. If not, the first refresh may show the old script, which is
  harmless.

## Open questions for Rich

1. Marketplace and plugin name: keep `claude-statusline` for both (if allowed),
   or something like `rinman24` for the marketplace, which leaves room for
   future plugins?
2. Install location: (a) `~/.claude/statusline.sh` or (b) the plugin data
   directory with a `SessionStart` sync? The recommendation is (b).
3. Chezmoi machines: confirm they stay on chezmoi and skip the plugin.
4. Should the setup ask for the track (░ or ⣿), or only the size?
5. Include phase 2 (subagent rows) in the first plugin release, or ship it
   later?
6. Windows: out of scope? Upstream ships PowerShell; this script needs bash
   and `jq`.

## Definition of done

- `/plugin marketplace add rinman24/claude-statusline`, `/plugin install`, and
  `/statusline-setup small` give a working status line on a clean macOS
  machine and a clean Linux devcontainer.
- A plugin update reaches the rendered status line without re-running setup
  (if option b).
- `/statusline-setup uninstall` restores the previous `statusLine`.
- The curl install and the chezmoi external behave exactly as before.
- CI is green, with manifest and version checks, and a release is tagged.
- This file is deleted.

## Process

- Use conventional commits without a scope (`feat: ...`, `test: ...`), ending
  with the Co-Authored-By trailer.
- Commit or push only when Rich asks, and open a PR into `main`.
- Rich reviews behavior in rounds. Preview ANSI output in a separate terminal
  tab, because `!` output shows raw escape codes.
