# claude-code-rc-shim kit

A Docker Sandboxes mixin kit that makes **Claude Code Remote Control (RC)**
work correctly inside an sbx sandbox.

## The problem

Inside a sandbox, sbx's forward proxy rewrites the `Authorization` header
unconditionally to inject your Anthropic credential. This is correct for
normal inference, but RC's **worker / work-lease / transcript** planes use
**per-session scoped tokens** — not the OAuth token — so the rewrite clobbers
them and the RC worker fails to register (`401` / `403` /
`worker_register_failed`).

See [cbrown1234/sbx-claude-code-rc-shim](https://github.com/cbrown1234/sbx-claude-code-rc-shim)
for the full explanation and upstream issue reference.

## Vendored source

The shim's scripts (`setup.sh`, `run.sh`, `rc-claude.sh`, `addon.py`) live in
this kit's [`files/home/scoped-token-shim/`](files/home/scoped-token-shim/),
copied verbatim to `~/scoped-token-shim/` when the kit is applied — no
runtime `git clone` from GitHub, so `github.com` isn't in this kit's network
caps.

They were vendored via `git subtree` from
[cbrown1234/sbx-claude-code-rc-shim@df47e06](https://github.com/cbrown1234/sbx-claude-code-rc-shim/commit/df47e06)
(`main`). To pull in upstream fixes later:

```console
git subtree pull --prefix=claude-code-rc-shim/files/home/scoped-token-shim \
  https://github.com/cbrown1234/sbx-claude-code-rc-shim.git main --squash
```

## What this kit does

The install command runs the vendored `setup.sh`, which:

1. Installs `mitmproxy` (isolated, via `uv tool install --python 3.12`)
2. Generates mitmproxy's CA cert (brief headless run)
3. Appends the CA to `/etc/ssl/certs/ca-certificates.crt` so node, python,
   and curl all trust the shim's TLS interception

Install also symlinks `rc-claude.sh` onto `PATH` as `rc-claude`, and a
`commands.startup` hook (`background: true`) launches `run.sh` on every
sandbox boot — the shim daemon is already listening on `127.0.0.1:8080`
before you ever need it, so there's no separate "start the shim" step.

No credentials are declared — the shim works entirely at the network layer.

## Usage

After the kit is applied, inside the sandbox:

```console
# 1. Launch Claude Code routed through the shim (already running via startup hook)
rc-claude

# 2. Inside Claude Code, start a remote-control session
/remote-control
```

`rc-claude` (a symlink to `rc-claude.sh`) checks that the shim is reachable
before launching and sets both upper- and lower-case proxy env vars
(node/undici prefers the lowercase names which sbx pre-sets to the gateway;
without overriding both, the shim is bypassed silently). If it reports the
shim isn't reachable, check `~/scoped-token-shim/run.log` for why the
startup hook's `run.sh` failed to come up.

## Applying the kit

```console
# Apply to an already-running sandbox
sbx kit add <sandbox-name> /path/to/sbx-kits/claude-code-rc-shim/

# Or pass it at creation time
sbx run --kit /path/to/sbx-kits/claude-code-rc-shim/ claude
```

## If the install command fails

The kit allows `pypi.org` and `files.pythonhosted.org` (for `uv tool install
mitmproxy`). If any request is blocked, check the log:

```console
sbx policy log <sandbox-name>
```

Then re-apply the kit after adding any missing domain:

```console
sbx kit add <sandbox-name> /path/to/sbx-kits/claude-code-rc-shim/
```

## Configuration

The shim is configurable via environment variables — see the
[upstream README](https://github.com/cbrown1234/sbx-claude-code-rc-shim#configuration-env-vars)
for the full list. The most useful ones:

| var | default | meaning |
|---|---|---|
| `SHIM_DEBUG` | unset | `1` → log routing decisions to `shim.log` |
| `SHIM_STRIP_MSG_TIMESTAMP` | `1` | `0` → keep the server-injected "Message sent at …" reminder |
| `SHIM_LISTEN_PORT` | `8080` | port the shim listens on |

Since `run.sh` is now launched by the kit's `commands.startup` hook (already
running by the time you get a shell), exporting these in your own shell
comes too late to affect it. Set them persistently before boot instead —
either add them to `/etc/sandbox-persistent.sh` yourself, or add an
`environment.variables` block to this kit's `spec.yaml`.

## Iterating on the kit

```console
sbx kit validate ./claude-code-rc-shim/
sbx kit inspect ./claude-code-rc-shim/
```
