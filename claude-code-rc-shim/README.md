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

`commands.install` (runs once, before any session can attach) patches
`/usr/local/lib/sandbox/start-agent` — the sandbox's own agent launcher,
documented in its generated comment as a supported edit-as-root
customization point — to wait briefly (bounded, ~6s) for the shim to
actually be listening on `127.0.0.1:8080` before exporting `HTTP(S)_PROXY`
(upper- and lower-case) and launching `claude`. This is the one guaranteed
choke point every `claude` launch passes through, so a plain `claude` is
routed through the shim automatically, with no `rc-claude` wrapper needed.
If the shim isn't up within the wait, it fails open — `claude` launches
through the sandbox's normal proxy instead of a dead one, so that session
just won't have RC until the shim catches up (see `spec.yaml`'s
`description` for why: the shim is killed on every sandbox auto-stop and
has to actually come back up, so *some* bounded wait is unavoidable, but
it should never hang indefinitely or leave `claude` pointed at nothing).

A `commands.startup` hook (`background: true`, reruns on every sandbox
boot) runs the vendored `setup.sh`, symlinks `rc-claude.sh` onto `PATH` as
`rc-claude`, and starts `run.sh` in the background. `setup.sh`:

1. Installs `mitmproxy` (isolated, via `uv tool install --python 3.12`)
2. Generates mitmproxy's CA cert (brief headless run)
3. Appends the CA to `/etc/ssl/certs/ca-certificates.crt` so node, python,
   and curl all trust the shim's TLS interception

No credentials are declared — the shim works entirely at the network layer.

See `spec.yaml`'s own `description` for the full history of designs this
kit went through to route plain `claude` through the shim: a container-
level env override (broke another kit's install step), then a readiness-
poll snippet sourced via `BASH_ENV` (closed the first race but couldn't
survive sbx's auto-stop/restart cycle, since its readiness state couldn't
carry over between separate `claude` launches), and now the start-agent
patch described above.

## Usage

After the kit is applied, inside the sandbox:

```console
# 1. Launch Claude Code as normal -- already routed through the shim
claude

# 2. Inside Claude Code, start a remote-control session
/remote-control
```

`rc-claude` remains available as a manual fallback: it waits for the shim
to become reachable before launching, and exits with a clear error if it
never comes up (check `~/scoped-token-shim/run.log` for why).

## Applying the kit

This kit declares a `commands.startup` hook, which `sbx kit add`'s
recreate flow doesn't support yet (it refuses with a clear error). Pass it
at creation time instead:

```console
sbx create --kit /path/to/sbx-kits/claude-code-rc-shim/ claude .
```

## If the startup hook fails

The kit allows `pypi.org` and `files.pythonhosted.org` (for `uv tool install
mitmproxy`). If any request is blocked, check the log:

```console
sbx policy log <sandbox-name>
```

Then fix `spec.yaml` (or the caps) and recreate the sandbox:

```console
sbx rm <sandbox-name>
sbx create --kit /path/to/sbx-kits/claude-code-rc-shim/ claude .
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
comes too late to affect it. Add them to the `commands.startup` script in
this kit's `spec.yaml`, before `run.sh` starts.

## Iterating on the kit

```console
sbx kit validate ./claude-code-rc-shim/
sbx kit inspect ./claude-code-rc-shim/
```
