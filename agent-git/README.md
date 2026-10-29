# agent-git kit

Gives the sandbox agent its own git identity and rewrites `github.com` /
`gitlab.com` remotes from SSH to HTTPS, so commits are authored consistently
and pushes/pulls work over the proxy without any SSH key management.

## How it works

Two `setup.startup` steps, both idempotent (safe to re-run on every sandbox
restart — see [pitfalls #2](https://github.com/docker/sbx-kits-contrib/blob/main/skills/kit-author/topics/pitfalls.md) in sbx-kits-contrib):

1. **Agent identity** — sets `user.name` / `user.email` globally to a fixed
   bot identity, so commits made by the agent are attributed consistently
   rather than inheriting whatever the base image happens to have configured.
2. **SSH-to-HTTPS rewriting** — adds `url.insteadOf` rules so any
   `git@github.com:` / `ssh://git@github.com/` (and the `gitlab.com`
   equivalents) remote is transparently rewritten to `https://`. This kit
   does no key management itself; it exists purely so remotes resolve to a
   transport the sandbox proxy can authenticate.

This kit doesn't declare `permissions.network` — it only edits git config, it
doesn't fetch anything itself.

## Authentication

HTTPS auth is handled elsewhere, not by this kit:

- **github.com** — if the host has a global sbx GitHub secret configured
  (`sbx secret set -g github`), `GH_TOKEN` is available as a proxy-managed
  sentinel for both `gh` and git HTTPS operations automatically.
- **gitlab.com** — pair with the [`gitlab`](../gitlab/) or
  [`gitlab-api`](../gitlab-api/) kit for token auth, or
  [`gitlab-ssh`](../gitlab-ssh/) if you'd rather forward the host's SSH
  agent instead of rewriting to HTTPS for GitLab specifically.

Without one of those, the HTTPS rewrite still happens, but pushes/pulls will
fail auth the same way they would from any unauthenticated HTTPS clone.

## Usage

```console
sbx kit add <sandbox-name> /path/to/sbx-kits/agent-git/
```

Or pass it at creation time:

```console
sbx run --kit /path/to/sbx-kits/agent-git/ claude
```

## Changing the bot identity

The name/email are hardcoded in `spec.yaml`'s first `setup.startup` command.
Edit them directly if you want commits attributed to a different identity.

## Iterating on the kit

```console
sbx kit validate ./agent-git/
sbx kit inspect ./agent-git/
```
