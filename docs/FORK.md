# How this fork works

Heretek-AI/ProxmoxVE is a fork of
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE).
It carries upstream's full catalogue plus the Heretek scripts, a frontend and
these docs.

## The one rule

**Never edit a file that upstream also has.** Every upstream file stays
byte-identical to upstream, and everything Heretek lives in files upstream
doesn't have. Then merging upstream can't conflict, and the sync runs
unattended.

`heretek-pr-checks.yml` fails any pull request that breaks this rule. The only
exception is `.github/dependabot.yml`, which stays deleted so Dependabot doesn't
rewrite upstream's workflows here.

If a Heretek change seems to need an upstream file, find a Heretek-owned place
for it instead:

| Want to change | Do this instead |
| --- | --- |
| The repository README | Edit `.github/README.md`. GitHub shows it in place of the root README. |
| A workflow | Add a `heretek-*.yml` workflow. |
| `misc/*.func` or engine behaviour | Set an environment variable that `community-scripts/core` reads, or propose the change upstream. |
| `.gitignore` | Add a `.gitignore` inside the Heretek folder, like `frontend/.gitignore`. |
| An upstream script with a bug | Report it upstream and wait for the fix to arrive through a sync. |

## What Heretek owns

- `ct/<app>.sh` and `install/<app>-install.sh` for each Heretek script. These
  are the ct scripts whose `COMMUNITY_SCRIPTS_URL` defaults to this repository.
- `vm/<app>-vm.sh` for a Heretek app that also ships as a VM. Its
  `COMMUNITY_SCRIPTS_URL` defaults to this repository too, and it installs the
  app by running `install/<app>-install.sh` inside the image through
  `community-scripts/core`'s `pve/vm-app.func`, so the VM and the LXC install
  the same thing. `vm/re-agent-vm.sh` is the example to copy.
- `frontend/`: the website, deployed to GitHub Pages.
- `docs/`: this file, guides, and images (`docs/images`).
- `.github/README.md` and the `.github/workflows/heretek-*.yml` workflows.

## Adding a script

1. Copy an existing Heretek pair, such as `ct/ztnet.sh` and
   `install/ztnet-install.sh`.
2. Keep the first three lines of the ct script as they are. The first sets
   `COMMUNITY_SCRIPTS_URL` to this repository, so install scripts and
   `/usr/bin/update` come from here. The next two load the engine from
   `community-scripts/core`, exactly as upstream scripts do.
3. Add `frontend/public/json/<app>.json` so the script shows up on the site.
4. For a VM variant, add `vm/<app>-vm.sh` and its own
   `frontend/public/json/<app>-vm.json` (one JSON per script, `type: "vm"`).
5. Open a pull request. ShellCheck runs on the scripts you changed.

Heretek apps don't show an ASCII banner, because core only serves banners for
its own catalogue. That's expected.

## Workflows

| Workflow | What it does |
| --- | --- |
| `heretek-upstream-sync.yml` | Daily: merges upstream main into an `upstream-sync` branch and opens a pull request, or opens an issue if it conflicts. |
| `heretek-upstream-workflows.yml` | Disables every workflow that isn't `heretek-*`. Upstream's workflows target upstream's infrastructure (PocketBase, self-hosted runners). |
| `heretek-pr-checks.yml` | Upstream-file guard and ShellCheck on pull requests. |
| `heretek-frontend.yml` | Builds the frontend and deploys it to GitHub Pages. |
| `heretek-sync-standalone.yml` | Copies the Heretek scripts to Heretek-AI/Heretek-ProxmoxVE. |
| `heretek-close-discussion.yml` | Closes a discussion that a merged commit references. |

Merge upstream sync pull requests with **Create a merge commit**. Squashing or
rebasing drops upstream's history, and the next sync then conflicts on
everything.

## Secrets

| Secret | Used by | Needs |
| --- | --- | --- |
| `PAT_WORKFLOW` | `heretek-upstream-sync.yml` | Fine-grained token for this repository: Contents, Pull requests, Issues and Workflows set to read and write. `GITHUB_TOKEN` can't push upstream's workflow changes, and pull requests it opens don't trigger CI. |
| `PAT_STANDALONE` | `heretek-sync-standalone.yml` | Fine-grained token for Heretek-AI/Heretek-ProxmoxVE: Contents set to read and write. |

## Syncing by hand

```bash
git remote add upstream https://github.com/community-scripts/ProxmoxVE.git
git fetch upstream main
git checkout -b upstream-sync origin/main
git merge upstream/main
```

A conflict means a Heretek change touched an upstream file. Take upstream's
version (`git checkout --theirs <file>`) and move the Heretek change into a
Heretek-owned file.
