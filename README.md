# Version check manifest

Not part of any Tebex package — this is the file *you* host, not something that ships with a resource.

## What this is

Every Cobra resource now checks its own `fxmanifest.lua` `version` against one shared JSON file on boot, and prints a console message if a newer version is available:

```
[cobra-mdt-police] A new version is available: 1.3.0 (you are running 1.2.0). Update from your Tebex account.
```

`versions.json` in this folder is that shared file, pre-filled with every resource's current version. All 23 resources read the exact same URL — you only maintain one file.

## One-time setup

This machine has no `git`/`gh` CLI installed, so I can't create the repo or push for you — do this part yourself (five minutes):

1. **Create the repo**: on github.com, "New repository" → name it anything (e.g. `cobra-versions`) → **Public** (has to be, for `raw.githubusercontent.com` to serve the file without auth — see the note below on why this repo is public and not private) → Create.
2. **Upload this folder's `versions.json`** to it (drag-and-drop on the GitHub web UI works fine, or `git init` + `git add` + `git commit` + `git push` from this folder if you'd rather use git locally). `sync-versions.ps1` and this `README.md` don't need to go in the repo — only `versions.json` is actually read by anything.
3. **Get its raw URL**: on the file's GitHub page, click "Raw", copy the address bar. It looks like `https://raw.githubusercontent.com/<your-username>/<your-repo>/<branch>/versions.json`.
4. **Replace the placeholder** in every resource's `config.lua`:
   ```lua
   Config.VersionCheck = {
       enabled = true,
       manifestUrl = 'https://raw.githubusercontent.com/YOUR-GITHUB-USERNAME/YOUR-REPO/main/versions.json',
   }
   ```
   It's the exact same string in all 23 resources, so a single find-and-replace across the whole `tebex/` folder for `YOUR-GITHUB-USERNAME/YOUR-REPO` does every one at once.
5. Until step 4 is done, the check is a harmless no-op everywhere (it detects the placeholder and skips itself — no errors, no failed requests).

**Why public, not private**: a private repo's raw file requires an auth token to fetch, which would mean shipping a real GitHub credential inside every one of these 23 Tebex products — extractable by any buyer who opens the Lua file. `versions.json` only ever holds version numbers, nothing sensitive, so there's no actual reason to keep it private.

## Ongoing use — keeping versions.json in sync

`sync-versions.ps1` in this folder is the "automatically update the JSON" half of this setup. It reads every resource's `version '...'` straight out of its own `fxmanifest.lua` and rewrites `versions.json` to match — so the manifest can never drift out of sync with what's actually shipped, and you (or I) never hand-edit JSON.

Whenever a resource's version gets bumped:
```powershell
./sync-versions.ps1
```
It prints exactly what changed (or "already up to date" if nothing did), then you just need to `git add versions.json && git commit -m "..." && git push` (or drag the updated file onto the GitHub web UI again) to actually publish it.

Going forward in this workspace: whenever I bump a resource's version for you, I'll re-run this script as part of that same change, so `versions.json` is always ready to push — I just can't run the `git push` itself without git/gh available here. If you install `git` (and optionally authenticate `gh`) in this environment, tell me and I can take over the commit-and-push step too, closing the loop completely.

## Notes

- `enabled = false` (or leaving `manifestUrl` blank) turns the check off for that one resource if you ever want to.
- The check never blocks boot and fails completely silently on any network error, malformed JSON, or missing manifest entry — it's a courtesy heads-up only, never a hard dependency.
- Comparison is real major.minor.patch numeric (not string comparison), so `1.10.0` correctly ranks above `1.9.0`.
