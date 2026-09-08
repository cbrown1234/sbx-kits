# clone-repo kit

Clones a remote Git repository into the sandbox workspace on startup,
instead of bind-mounting a directory from the host. Meant for a
workspace-less `sbx create` — no `PATH` argument, so nothing from the host
filesystem is ever exposed to the sandbox, only the repo you name.

## How it works

`setup.startup` runs `git clone <repo> $HOME/workspace` (skipped if that
directory is already a git checkout, so it's safe across sandbox restarts),
then checks out `ref` if one was given. There's no bind-mounted workspace
path to clone into for a workspace-less sandbox, so the target is a fixed
directory under the agent user's home rather than anything host-supplied.

## Args

| Name   | Required | Description                                                        |
| ------ | -------- | ------------------------------------------------------------------- |
| `repo` | yes      | Git URL to clone (`https://` or `git@` — anything `git clone` takes) |
| `host` | no       | Hostname to allow egress to — set it to the host in `repo`           |
| `ref`  | no       | Branch, tag, or commit to check out after cloning                    |

`host` exists because the kit's own network allowlist is built from it
(`permissions.network.allow: [${{ kit.args.host }}]`) — declare it
separately rather than parsing it out of `repo`.

Leave `host` unset if a paired kit (`agent-git`, `gitlab-api`, `gitlab-ssh`)
already opens egress to that host — an unset `host` adds no allow rule at
all, rather than an empty one, so nothing is opened twice. Set it whenever
`repo` points somewhere those kits don't cover (a self-hosted Git server, for
example), or the clone will fail against the default-deny network policy.

## Usage

```console
sbx create claude \
  --kit /path/to/sbx-kits/clone-repo/ \
  --kit-arg repo=https://github.com/you/your-repo.git \
  --kit-arg host=github.com \
  --kit-arg ref=main
```

Note there's no `PATH` argument to `sbx create` — that's what skips the
workspace bind mount.

Or declaratively, in an `sbxenv.yaml`:

```yaml
schemaVersion: "1"
name: my-project
agent: claude
kits:
  - source: /path/to/sbx-kits/clone-repo/
    args:
      repo: https://github.com/you/your-repo.git
      host: github.com
      ref: main
```

No `workspace:` key, for the same reason there's no `PATH` above — declaring
one would bind-mount a host directory, which defeats the point of this kit.
Run it with `sbx env run`.

## Auth for private repos

This kit only clones and opens network egress to `host`; it does not wire up
credentials. Pair it with:

- [`agent-git`](../agent-git/) for GitHub/GitLab HTTPS token auth (rewrites
  SSH remotes to HTTPS too, so a `git@` URL in `repo` still works)
- [`gitlab-ssh`](../gitlab-ssh/) if you'd rather clone over SSH from
  gitlab.com

## vs. `sbx create --clone`

`sbx create --clone` clones the *host's local checkout* (bind-mounted
read-only, then cloned in-container) so the agent's commits can be fetched
back to the host afterwards. This kit is for the opposite case: there is no
local checkout at all, and you want the sandbox to start from a remote URL
directly. Commits stay in the sandbox until you `git push` them somewhere —
there's no git-daemon round-trip back to the host.
