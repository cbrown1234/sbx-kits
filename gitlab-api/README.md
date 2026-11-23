# gitlab-api kit

Installs `glab` and sets up git over HTTPS, so the agent can open merge
requests and push to gitlab.com from inside a sandbox.

## How auth works

Auth comes from an sbx **custom secret** on the host. The sandbox only ever
sees the placeholder `proxy-managed` in `$GITLAB_TOKEN`. On requests to
`gitlab.com` the proxy swaps the placeholder for your real token wherever it
appears:

- in the `PRIVATE-TOKEN` or `Authorization: Bearer` header that glab and the
  API use, and
- in the Basic password git sends. GitLab's git endpoints accept only Basic
  auth, so the kit sets a git credential helper that sends `oauth2` and the
  placeholder.

The kit doesn't declare a `credential@1` entry. A kit credential rewrites one
header in one format per service, which can't cover both the API and git on
the same host. This is tracked in
[docker/sbx-releases#596](https://github.com/docker/sbx-releases/issues/596)
(GitLab's case was [#552](https://github.com/docker/sbx-releases/issues/552)).
Other GitLab users report the same custom-secret workaround there.

> **TODO:** once #596 lands, move auth to a kit credential, or to upstream
> [`docker.io/sbx/gitlab`](https://github.com/docker/sbx-kits-contrib/tree/v3/gitlab)
> plus just this kit's credential helper. Re-check with
> [`probe-auth.sh`](./probe-auth.sh) first.

## Setup

1. Create a GitLab personal access token with `api` scope
   (User Settings → Access Tokens on gitlab.com or your instance).

2. Store it as a custom secret for gitlab.com:

   ```console
   sbx secret set-custom -g \
     --host gitlab.com \
     --env GITLAB_TOKEN \
     --placeholder proxy-managed \
     --value glpat-xxxxxxxxxxxxxxxxxxxx
   ```

   A custom secret applies to every sandbox, running ones included. Use
   `--sandbox <name>` in place of `-g` to limit it to one sandbox.

## Usage

```console
sbx kit add <sandbox-name> /path/to/sbx-kits/gitlab-api/
```

Or pass it at creation time:

```console
sbx run --kit /path/to/sbx-kits/gitlab-api/ claude
```

Inside the sandbox:

```console
glab mr create --fill
```

## Pairing with gitlab-ssh

This kit only opens port 443 to `gitlab.com`. If you also need `git push` /
`git pull` over SSH, add the upstream
[`gitlab-ssh`](https://github.com/docker/sbx-kits-contrib/tree/v3/gitlab-ssh)
kit alongside this one (the local copy was removed, see
[MIGRATION.md](../MIGRATION.md)):

```console
sbx run \
  --kit /path/to/sbx-kits/gitlab-api/ \
  --kit "docker.io/sbx/gitlab-ssh:latest" \
  claude
```

## Self-hosted GitLab

In `gitlab-api.yaml`, replace `gitlab.com` with your instance's hostname in
the `network-policy@1` runtime allow list, the `glab config set -g host`
command and the git credential-helper URL. Use the same hostname in the `--host` flag when
running `sbx secret set-custom`.

Leave the install-phase allow entry and the release URLs in the glab install
hook on `gitlab.com`. glab is only published there, so changing them breaks
the install and sandbox creation fails.

## If the install command fails

All traffic stays on `gitlab.com` (the Package Registry API is also there).
If something is blocked, check the log and re-apply:

```console
sbx policy log <sandbox-name>
sbx kit add <sandbox-name> /path/to/sbx-kits/gitlab-api/
```

## Checking auth

[`probe-auth.sh`](./probe-auth.sh) runs inside a sandbox and prints only HTTP
status codes. It never writes. It shows which auth headers the proxy swaps the
placeholder into, and whether git over HTTPS authenticates:

```console
sbx exec <sandbox-name> -- bash gitlab-api/probe-auth.sh
```

Run it from a sandbox whose workspace is this repo. `sbx policy log` then
shows whether gitlab.com traffic was intercepted (`forward`) or passed
through untouched (`forward-bypass`, so nothing was swapped in).

> **TO CHECK:** on sbx v0.54.0 (stable), the upstream `gitlab` kit's own
> credential was never injected: a `gitlab` service secret was stored and its
> binding approved, but gitlab.com showed `forward-bypass`. Upstream says v3
> needs an sbx release candidate or nightly. Re-run the probe on one before
> relying on kit credentials.

## Iterating on the kit

v3 kits need an `sbx` release candidate or nightly. `sbx kit validate`
doesn't accept v3 source kits; building the descriptor is what validates it.

```console
(cd gitlab-api && docker buildx build . -f gitlab-api.yaml --output type=cacheonly)
sbx kit inspect ./gitlab-api/
```
