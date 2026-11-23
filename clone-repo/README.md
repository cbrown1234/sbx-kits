# clone-repo kit

Clones a remote Git repository into the sandbox workspace on startup,
instead of bind-mounting a directory from the host. Meant for a
workspace-less `sbx create` — no `PATH` argument, so nothing from the host
filesystem is ever exposed to the sandbox, only the repo you name.

## How it works

A `lifecycle@1` startup hook runs `git clone <repo> $HOME/workspace` (skipped if that
directory is already a git checkout, so it's safe across sandbox restarts),
then checks out `ref` if one was given. There's no bind-mounted workspace
path to clone into for a workspace-less sandbox, so the target is a fixed
directory under the agent user's home rather than anything host-supplied.

## Args

| Name   | Required | Description                                                        |
| ------ | -------- | ------------------------------------------------------------------- |
| `repo` | yes      | Git URL to clone (`https://` or `git@` — anything `git clone` takes) |
| `host` | yes      | Hostname to allow egress to — set it to the host in `repo`           |
| `ref`  | no       | Branch, tag, or commit to check out after cloning                    |

`host` exists because the kit's own runtime network allow list is built from
it (`network-policy@1` → `runtime.allow: [<host>]`) — declare it separately
rather than parsing it out of `repo`.
It must be a lowercase DNS name (no IP address), because it's also the server
the kit's SSH agent grant is limited to.

`host` is required. In the v2 kit it could be left unset when a paired kit
(`agent-git`, `gitlab-api`) already opened egress to that host,
but v3 rejects an empty host in a network-policy entry. Setting it to a host a
paired kit already allows is harmless: allow lists from every kit in the
composition are unioned and deduplicated.

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

- [`agent-git`](../agent-git/) for GitHub/GitLab HTTPS token auth. This kit
  declares `integrates: ["agent-git"]`, so when both are loaded agent-git's
  startup hooks run first: its SSH-to-HTTPS rewrite applies to the clone,
  and a `git@github.com:` or `git@gitlab.com:` `repo` is cloned over HTTPS.
- upstream [`docker.io/sbx/gitlab-ssh`](https://github.com/docker/sbx-kits-contrib/tree/v3/gitlab-ssh)
  if you'd rather clone over SSH from gitlab.com. Its agent request is
  required, so creating the sandbox fails if your host has no SSH agent.

For `git@` URLs this kit requests your host's SSH agent itself
(`ssh-agent@1`, limited to logins to `host`), so the clone can authenticate
with your keys. The request is optional, and HTTPS clones don't use it.

## vs. `sbx create --clone`

`sbx create --clone` clones the *host's local checkout* (bind-mounted
read-only, then cloned in-container) so the agent's commits can be fetched
back to the host afterwards. This kit is for the opposite case: there is no
local checkout at all, and you want the sandbox to start from a remote URL
directly. Commits stay in the sandbox until you `git push` them somewhere —
there's no git-daemon round-trip back to the host.
