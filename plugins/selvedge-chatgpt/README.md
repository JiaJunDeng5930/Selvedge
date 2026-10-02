# Selvedge ChatGPT plugin

This independent stdio MCP package exposes explicitly shared local projects
through the official [OpenAI Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels).
It calls Selvedge's authenticated loopback API. It does not execute files itself
or receive the service's admin token.

## Configure a connection

Use Node.js 26 or later. Run `npm ci` and `npm run build` in the Selvedge repository.
Start Selvedge, create the projects to share through its UI or `create_project`,
and obtain their IDs with `list_projects`. Run `node host/cli.mjs describe` for
the current command fields.

Generate a dedicated credential in the service's environment:

```bash
export SELVEDGE_PLUGIN_TOKEN="$(node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('base64url'))")"
```

Add this field to the current Selvedge `config.json`, preserving other settings.
Its default location is `~/.selvedge-bend/config.json`; `--home` and `--config`
select other locations. Replace project ID `0` with the actual projects to share.
Use distinct credentials for different connection IDs.

```json
{
  "chatgpt_plugin": {
    "connections": {
      "0": {
        "token_env": "SELVEDGE_PLUGIN_TOKEN",
        "project_ids": [0],
        "sandbox": { "mode": "workspace-write", "network_access": false }
      }
    }
  }
}
```

Restart Selvedge with that environment. Keep its home directory separate from
project roots. Configuration is applied at startup; edit it and restart to change
or revoke a connection. Preserve the credential securely between restarts;
rotation also requires updating the MCP process's settings.

Set these variables for the local MCP process, using the service's actual
loopback origin if its port differs:

```bash
export SELVEDGE_URL=http://127.0.0.1:7421
export SELVEDGE_CONNECTION_ID=0
export SELVEDGE_CONNECTION_TOKEN="$SELVEDGE_PLUGIN_TOKEN"
```

Never place credentials in the plugin manifest or Git. The plugin refuses remote
origins, redirects and HTTP proxies. Grants belong to the connection across
conversations. Tools cannot override Workspace roots, impersonate connections,
invoke administrative commands or request permission escalation.

## Connect hosted ChatGPT

Download `tunnel-client` from [Platform tunnel settings](https://platform.openai.com/settings/organization/tunnels)
or the latest [official release](https://github.com/openai/tunnel-client/releases/latest),
and put it on `PATH`. Create or select a tunnel associated with the intended
ChatGPT workspace. The app creator and runtime-key principal need Tunnels
Read + Use. Obtain a runtime API key and set `CONTROL_PLANE_API_KEY` for the tunnel
process. Selvedge's ChatGPT account login is not this key.

Run from the repository, substituting a real tunnel ID:

```bash
node plugins/selvedge-chatgpt/bin/tunnel.mjs init --profile selvedge --tunnel-id tunnel_REPLACE_WITH_REAL_ID
node plugins/selvedge-chatgpt/bin/tunnel.mjs doctor --profile selvedge
node plugins/selvedge-chatgpt/bin/tunnel.mjs run --profile selvedge
```

Keep Selvedge and `tunnel-client run` running with the connection environment.
In ChatGPT developer mode, open **Plugins**, create a connection, choose **Tunnel**,
and select the tunnel or enter its ID. If it is missing, check the workspace
association and the app creator's Tunnels permissions. Do not expose Selvedge's
HTTP server publicly.

Copy the registered connection's `plugin_asdk_app_...` technical ID from the
browser URL. To bundle that connection with the skill, create a deployment package
in a new directory:

```bash
node plugins/selvedge-chatgpt/bin/setup.mjs package plugin_asdk_app_REPLACE_WITH_REAL_ID /absolute/path/to/selvedge-chatgpt-package
```

The generated package binds the real ID through `.app.json` and
`extensions.com.openai.apps`. It omits the local `mcp.json` to avoid offering a
second tool route. Install through a supported local marketplace or workspace
flow in the [OpenAI packaging guide](https://developers.openai.com/plugins/build/plugins).
Registered IDs are deployment data, not source-code placeholders.

## Install in a local client

The plugin has its own dependency lockfile and can be installed independently of
the Selvedge repository. In the copied plugin directory, run
`npm ci --workspaces=false` before starting its stdio server.

The source package's `mcp.json` declares a local stdio server for compatible
clients. It does not connect hosted ChatGPT by itself. An installed client supplies
`PLUGIN_ROOT` and `PLUGIN_DATA`; initialize its actual plugin data directory with
the connection environment above:

```bash
node plugins/selvedge-chatgpt/bin/setup.mjs connection /absolute/path/to/plugin-data
```

This creates `connection.json` with mode `0600` and refuses to overwrite it.
For rotation, remove it, recreate it with the new settings and restart the MCP
process. The server rejects symlinks, foreign-owned files and group/world-readable
files. The manifest references the private file without embedding credentials.
Direct stdio/Tunnel launches use the environment unless `SELVEDGE_CONNECTION_FILE`
explicitly selects a private file.

## Filesystem behavior

Acceptance captures the selected project's current Workspace and primary working
directory. The connection's sandbox mode controls writes and its network setting
controls network use. `read-only` disallows project writes; `workspace-write`
permits them. Both require isolation.

Reads cover these Workspace roots, private temporary files and explicit OS runtime
paths. Unshared project files, symlink escapes and the service home are denied.
Ordinary Selvedge task read permissions are unchanged. Dependencies outside these
roots need an explicit addition to the project's Workspace; that also shares the
added directory.

## Verify

In a new ChatGPT chat, list shared projects, check that private projects are absent,
read the selected project's guidance, execute an authorized small command, query
its receipt and inspect the actual local file. Retry identical arguments with the
same request ID and confirm no second execution. Open another chat on the same
connection and read that receipt. Check rejection for an unshared project and for
the connection after revocation and service restart. The bundled skill explains
retry, cancellation and physically uncertain outcomes.

`npm run test:chatgpt-plugin` checks local MCP/HTTP/native journal/real-shell
boundaries and independent proof mutations. `npm run test:locality` checks feature
extension and replacement. OS tests need Seatbelt on macOS or bubblewrap/seccomp
on Linux and must run outside another restrictive sandbox. These fixtures do not
establish a live commercial ChatGPT or Tunnel connection.
