# Migrating to the v3 kits

The kits in this repo now use the v3 kit descriptor
([sandbox-kit-spec v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md)).
Each kit is a single `<kit>/<kit>.yaml` file in place of v2's `spec.yaml`, so
point `--kit` and `sbxenv.yaml` `source:` at the same directories as before.
This guide covers what behaves differently for users and which kits were
removed.

## SSH agent forwarding is no longer automatic

v2 sbx forwarded your host's SSH agent into every sandbox. In v3 a sandbox
gets no agent unless a kit requests one with `ssh-agent@1`. In this repo
`clone-repo` does that, limited to logins to its git host. Upstream
`docker.io/sbx/gitlab-ssh` does too.

Forwarding is still switched on and off globally on the host with an `sbx`
setting (default `true`). Upstream's end-to-end tests set it for their v3 SSH
kits:

```console
sbx settings get ssh.agentForwardingEnabled
sbx settings set ssh.agentForwardingEnabled false   # then: sbx daemon restart
```

Make sure your key is loaded (`ssh-add -l`) before creating a sandbox that
needs it.

## Removed: `gitlab-ssh`

Use the upstream kit, published as `docker.io/sbx/gitlab-ssh`:

```console
sbx run --kit "docker.io/sbx/gitlab-ssh:latest" claude
```

Differences from the local kit:

- **Creating the sandbox fails if your host has no SSH agent.** Upstream's
  `ssh-agent@1` request is required. The local one was optional. It also makes
  the request required for anything composed with it, including `clone-repo`.
- **gitlab.com's host keys are pinned** into `known_hosts`, so there's no
  host-key prompt on the first connection.
- **gitlab.com is allowed on every port**, not only `:22`.
- **Self-managed instances** use `--kit-arg host=…` and
  `--kit-arg "hostKey=ssh-ed25519 …"`. You no longer edit the descriptor.
- **The base image needs `openssh-client`** (it declares
  `requires: ["deb/openssh-client"]`).

## Removed: `network-policy-repro`

This was a reproduction for a v2 `sbx kit add` bug, not a kit to use. It has
no replacement.

## Removed: `gitlab`

It was `gitlab-api` plus SSH access to gitlab.com. Use `gitlab-api` with
upstream `gitlab-ssh` (see the differences above):

```console
sbx run \
  --kit /path/to/sbx-kits/gitlab-api/ \
  --kit "docker.io/sbx/gitlab-ssh:latest" \
  claude
```

## `gitlab-api`

Auth now comes only from a custom secret. The kit no longer declares a
`gitlab` credential, because a kit credential can't cover both the API and
git over HTTPS on one host
([docker/sbx-releases#596](https://github.com/docker/sbx-releases/issues/596)).
If you followed the v2 README you already have the secret:

```console
sbx secret set-custom -g --host gitlab.com --env GITLAB_TOKEN \
  --placeholder proxy-managed --value glpat-…
```

A `gitlab` service secret (`sbx secret set gitlab`) does nothing for this kit.

The git credential helper no longer calls glab: it hands git the placeholder
from `GITLAB_TOKEN` directly.

It's still here for now, because it authenticates git over HTTPS to
gitlab.com as well as glab. Upstream doesn't support that yet. The
upstream [`gitlab`](https://github.com/docker/sbx-kits-contrib/tree/v3/gitlab)
kit does the rest better: glab ships pinned in the kit image, and
self-managed instances are args.

To move to upstream:

1. Swap `gitlab-api` for upstream `gitlab` + `gitlab-ssh`:

   ```console
   sbx run \
     --kit "docker.io/sbx/gitlab:latest" \
     --kit "docker.io/sbx/gitlab-ssh:latest" \
     claude
   ```

2. Store the token with `sbx secret set gitlab`. Upstream binds the `gitlab`
   service, so `sbx secret set-custom --host` is no longer needed. For a
   self-managed instance, use `--kit-arg host=…` and `--kit-arg service=…`.
3. Use SSH for GitLab git operations. Upstream injects the token only for
   API traffic, so `git push` over HTTPS isn't authenticated. That means
   `agent-git`'s `git@gitlab.com:` → HTTPS rewrite works against you here:
   with upstream's kits, GitLab remotes need to stay on SSH.

> **TO CHECK:** on sbx v0.54.0 even upstream `gitlab`'s own credential wasn't
> injected for gitlab.com. Its README says v3 needs an sbx release candidate
> or nightly, so test there before switching. Until #596 lands, keeping the
> custom secret is the only setup that authenticates both glab and git.

## `clone-repo`: `host` is required

v2 let `host` default to empty when a paired kit already allowed the git host.
v3 rejects an empty host in a network rule, so set `host` every time. It must
be a lowercase DNS name (no IP address or port). Repeating a host another kit
already allows is harmless.

When `agent-git` is in the same sandbox, `clone-repo` now runs after it, so
its SSH-to-HTTPS rewrite applies to the clone.

## `agent-git`: identity is configurable

The commit identity is now set with args, with generic defaults:

| Arg     | Default                 |
| ------- | ----------------------- |
| `name`  | `Sandbox Agent`         |
| `email` | `agent@sandbox.invalid` |

Pass `--kit-arg name=…` and `--kit-arg email=…` (or `args:` in `sbxenv.yaml`)
to use your bot account. The v2 kit hard-coded a personal address.
