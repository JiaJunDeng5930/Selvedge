# Using Selvedge

## Conversations and shared work

Type `/side` in a Task message to open a side conversation, optionally followed
by a question. It starts from the parent's captured conversation while the
parent continues. Closing the side keeps its Task; the explicit return action
sends only its new content back to the parent.

Conversation search finds user and assistant messages, with optional Project
and Work filters. Selecting a result opens the original message. Agents use
`search_history` with the same filters and history positions. Type `@` in a
message to select an available skill and insert its exact `SKILL.md` reference.

Works group Tasks and task graphs independently of Projects. A graph connects
ordinary Task outputs to inputs; it does not introduce another scheduler.
Interactive interfaces in `selvedge-ui` Markdown fences and a Work's persistent
**共享 UI** page use the same bounded declarative language. A Task can inspect
that page with `read_work_ui` and change it with revision-checked
`apply_work_ui_patch`. See the [interactive interface guide](../theories/Interaction/Interactive/README.md).

Paste, drop or select images in a message or board card. Stored images accompany
the message to a supported ChatGPT account model. `read_image` reads a local
image under the Task's workspace and sandbox permissions; subsequent requests
and restart reuse its content-addressed snapshot. Other model backends report
unsupported image input explicitly. The independent
[ChatGPT plugin](../plugins/selvedge-chatgpt/README.md) exposes explicitly shared
Projects through Secure MCP Tunnel, with grants separate from ordinary Tasks.

## Workspaces and projects

Each task freezes its own workspace: zero or more canonical directory roots and,
when roots exist, one primary root used as the Bash working directory. Sandbox
settings and approval policy are separate contract fields. A restricted Bash
process can write workspace roots under `workspace-write`, or no roots under
`read-only`; other paths are read-only. It also gets a private temporary directory.
The service home is protected, so keep it separate from project code directories.
macOS uses Seatbelt; Linux requires bubblewrap and seccomp support. Unavailable
isolation fails closed, rather than falling back to an ordinary host shell.

`create_project`, `update_project`, `read_project`, `list_projects` and
`delete_project` are native commands. Task creation/fork accepts a `settings`
object with `project_id`, `workspace`, `sandbox` and `approval`.

When the primary workspace has a Git commit, the New task dialog lets you choose
the current workspace, a local Git worktree, or Tencent Cloud CVM.
A project's `create_worktree` preference initializes the local choice. Creating
a Task with a local choice remembers that preference for the Project; choosing
a cloud environment does not change it. The programmatic local entry is
`create_worktree_task`; `create_workspace_task` additionally accepts the typed
`backend` name `local` or `tencent_cvm`. Both use the existing task startup and
archive lifecycle.
Managed checkouts live under `<service home>/worktrees`, start at detached HEAD,
and include tracked edits and untracked files that Git does not ignore.
The service home must be outside the source Git repository so its private state
cannot be copied into a task checkout.
Archiving their task moves the checkout into `worktrees/archived`, retaining its
files. `read_worktree` and `list_worktrees` expose the associated paths and any
physical-operation failure; `retry_worktree_archive` retries a failed archive.
Forked tasks can share the checkout. Archive those tasks before archiving the
task that owns it.
Git commands that write shared repository metadata continue to follow the task's
sandbox and approval settings.

Approval policy has three modes. **Full Access** runs Bash without isolation.
**Ask for Approval** keeps ordinary commands sandboxed and shows an exact-command
permission request in the conversation when the agent requests an exception.
**Approval for Me** sends that request to a separate, tool-free model invocation;
it does not create a task. Set `reviewer_profile` to a configured model profile,
or omit it to prefer the same ChatGPT account connection's advertised
`codex-auto-review` model, including its hidden catalog entry. Other profiles and
connections that do not advertise this model use the task's profile; account
discovery reports that fallback. Explicit reviewer choices and existing task
settings are preserved. The offline echo profile cannot approve.

An agent requests an exception with `sandbox_permissions: "require_escalated"`
and a concrete `justification` before executing the command. The Web UI shows
the complete command, reason, working directory and requested scope, with
**Approve once** and **Deny** buttons for human review. Approval permits only that
invocation outside filesystem and network isolation; it never changes the task's
saved settings.
Cancellation, malformed model replies and interrupted reviews grant no access.
A failed sandbox command is not retried automatically with broader permissions.

The New task and Fork forms accept a `settings` JSON object. `{}` uses the normal
defaults or parent context. For example, `{"project_id": 0}` selects project 0's
workspace for a new task; `{"workspace": {"roots": []}}` explicitly selects no
workspace roots. The same fields are available through the CLI and command API.


### Cloud task workspaces

Configure a CVM image, network and SSH key in the service configuration:

```json
{
  "cloud": {
    "backend": "tencent_cvm",
    "tencent_cvm": {
      "region": "ap-shanghai",
      "zone": "ap-shanghai-2",
      "image_id": "img-example",
      "instance_type": "S5.LARGE8",
      "vpc_id": "vpc-example",
      "subnet_id": "subnet-example",
      "security_group_ids": ["sg-example"],
      "key_id": "skey-example",
      "ssh_private_key": "/absolute/path/to/cvm-key",
      "spot_max_price": "0.5"
    }
  }
}
```

Set `TENCENTCLOUD_SECRET_ID` and `TENCENTCLOUD_SECRET_KEY` in the service
environment; `TENCENTCLOUD_TOKEN` is optional. Credentials do not belong in the
configuration object. Optional settings are `ssh_user` (default `root`),
`ssh_port` (22), `address_type` (`public` or `private`),
`internet_max_bandwidth_out` (5), `startup_timeout_ms` (600000), and a custom
`api_endpoint`. The service host must be able to reach the selected SSH address.

The selected project needs a GitHub remote and a pushed commit. Commit
`.selvedge/env.sh` with the project's installation steps. Cloud startup clones
the committed revision, runs this script, and then binds the task to the ready
environment. Git, Bash, setsid and SSH access must be available in the image; the
setup script must leave Python 3 available for file observations. Private repositories
use `GITHUB_TOKEN` from the service environment through an ephemeral clone
credential helper; it is removed before the setup script runs.

Cloud Bash uses Full Access. Bash, process sessions, file observations and image
reads use the task's bound environment; local MCP servers remain host services.
The model receives an environment notice describing that distinction. Forked
tasks share the same bound resource. Archiving a child does not destroy its
owner's instance, and an instance cannot be recycled while another task uses it.

To use voice with a cloud task, create the task first, then start voice in its
conversation.

Failed setup reclaims its allocation and retains the setup log under
`<service home>/cloud-workspaces/<journal namespace>/task-<id>.log`. If reclamation
fails, the task retains the failure and resource association;
`retry_worktree_archive` retries cleanup. Restart recovery reconciles the
persisted allocation receipt with the same task resource.
Archiving the owning task recycles its cloud instance after active IO has settled.

## Use it on a project

The service launch directory supplies the default workspace for a new task that
does not select a project or explicit roots. It is not a shared task directory
or a permission boundary. For example, after building this checkout:

```bash
cd /absolute/path/to/project
bun /absolute/path/to/Selvedge/host/cli.mjs --home /absolute/path/to/task-home server
```

The journal records each task's canonical roots and execution settings. Restarting
from a different directory cannot reinterpret existing tasks' relative paths;
only new unprojected tasks use the new launch default. Tasks can select different
workspaces in the same service. A task fork does not create a Git worktree or copy
files. Bash uses its task's sandbox unless Full Access or a one-operation grant
explicitly permits unrestricted execution. Keep the service home separate from
project code. MCP servers and plugins are trusted host components; the Bash
sandbox does not isolate those extension processes.

Use `bash` for reading, writing, editing, searching, scripts and tests; there is no
second set of file tools. Independent calls from one reply run concurrently. Put
dependent commands in one shell invocation. Each operation owns a committed
ticket, separate from the task's model/control phase. Partial results or new input
can resume the model while siblings continue. Quiet operations do not poll the
model. `read` exposes their operation IDs; `phase: idle` alone does not mean all
external work has completed—also check that `operations` is empty.

`bash` has no runtime deadline unless `timeout_ms` is specified. Start development
servers with their ordinary foreground command; no background or server mode is
needed. Bash announces its `operation_id` while it continues running, and the
model can call `read_process` or `write_process` from the same task. Completion
arrives automatically. `cancel_operation` stops the selected process, and closing
the service stops its running processes.

The default `mode: "pipe"` keeps stdout and stderr separate and accepts ordinary
stdin. For a terminal application, start Bash with `mode: "pty"`; optional `cols`
and `rows` set its initial terminal size. PTY output combines stdout and stderr.
Use `write_process` with `operation_id` and `input` to send text, including terminal
key sequences such as `"\u0003"` for Ctrl-C. In pipe mode, `eof: true` closes stdin
after any supplied input. In PTY mode, set `cols` and `rows` together to resize the
terminal, and send `"\u0004"` for the terminal's Ctrl-D key instead of closing stdin.

`read_process` takes `operation_id` and an optional decimal-string `cursor`
(default `"0"`). It returns available output immediately, with `status`,
`start_cursor` and `next_cursor`; pass `next_cursor` into the next read to obtain
only newer output. The bounded buffer retains the newest content. If earlier
content was discarded, `omitted_characters` and an explicit omission marker
identify the gap. Each task can access only its own process sessions. Completed
sessions remain readable until 64 newer completions replace them; service
restart clears these physical sessions without relaunching their commands.

`max_output_length` bounds retained Unicode characters per stream (default 40,000,
maximum 65,536), excluding the omission marker. The combined `read_process` output
has one buffer of the same size; the tool result byte budget can reduce these
limits. Previews keep the newest output;
metadata reports raw byte counts and omitted character counts. Truncated streams
carry private artifact paths, SHA-256 revisions and explicit retention limits.
An artifact capped at 8 MiB is a retained prefix, not the complete output. Inspect
it through Bash. Nonzero exits, deadlines and cancellation are tool errors, and
shell descendants are terminated when the shell exits.
The executable catalog and `limits` in `describe` are authoritative.

Initial instructions and guidance enter task history with their source identity
and revision. Before model and summary requests, the service refreshes configured
instructions, service-home guidance, and guidance across all workspace roots.
Discovery includes each root's Git ancestor chain and its nested directories.
Without a Git ancestor, discovery starts at the selected root. Place guidance in
`AGENTS.md`, or use `AGENTS.override.md` to replace that directory's usual file.
Each source carries its actual path and applicable directory, so module guidance
applies to that module's subtree. The executable definitions in
[context definitions](../theories/Kernel/Context.v) own source selection and precedence.

Put reusable skills in `<service home>/skills/<name>/SKILL.md` or
`<service home>/.agents/skills/<name>/SKILL.md`. Project skills are discovered in
`.agents/skills/` and `.claude/skills/` at ancestor and nested directories, with
their applicable directory recorded. Same-name skills retain separate paths.
For explicit entries, set `skills` in the service home's `config.json` to an array
of `SKILL.md` paths; relative paths resolve from the service home. A path already
configured explicitly is not repeated by automatic discovery.

The model receives skill names, descriptions and paths, and reads a relevant
skill's body through ordinary Bash. Skill bodies and referenced materials do not
become tracked context; body-only changes do not add metadata updates. Directory
discovery is bounded, skips dependency/build directories, and does not follow
symbolic links. A failed or incomplete discovery preserves its previous accepted
collection. Accepted changes append verified patches; confirmed removals append
withdrawals. Forks inherit the baseline and patches. Workspace and sandbox
contracts stay frozen.

These controls also appear in the browser from the native model.

```bash
bun host/cli.mjs steer --task-id 0 --message 'Prioritize this instruction.'
bun host/cli.mjs cancel_operation --task-id 0 --operation-id 12
```

`compact` starts context compaction without starting another assistant turn. A
supplied summary requires no provider call and also works on stopped or frozen
idle tasks:

```bash
bun host/cli.mjs compact --task-id 0
bun host/cli.mjs interrupt --task-id 0
bun host/cli.mjs compact --task-id 0 --summary 'Completed work, verified results, unresolved problems, and next steps.'
bun host/cli.mjs send --task-id 0 --message 'Continue from the replacement context.'
```

Original task history remains readable. Later requests use a compatible complete
replacement window followed by messages committed after its captured source.
When a new endpoint cannot consume native opaque content, portable rebuilding
uses the readable original records. The
[compaction definitions](../theories/Features/Compaction.v) and shared
[context selection](../theories/Kernel/ContextSelection.v) own those rules.

## Model and tool configuration

The default home is `~/.selvedge`. `bun host/cli.mjs init` creates its
`config.json` without overwriting an existing file. `--home PATH` and `--config
FILE` select explicit locations; both options also work with `bun run start ...`.
Configuration is read at server startup.

To use an eligible ChatGPT Plus or Pro plan, sign in with the official
[Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source)
flow. No model configuration or API key is required:

```bash
bun host/cli.mjs login
bun host/cli.mjs models
```

Open the displayed authorization URL in your browser and complete **Continue with
ChatGPT**. The browser returns to a temporary `127.0.0.1` callback on this host.
Login loads account models into the native selector and refreshes an already-running
server. Use `models --refresh` to fetch a fresh catalog. Use a reasoning level
advertised by the selected model.

The separate [ChatGPT Web backend](chatgpt-web.md) uses
`provider: "chatgpt-web"`, a model such as `chatgpt-web/high`, and the API
application token in `CHATGPT_WEB_TOKEN`. Its default endpoint is
`http://127.0.0.1:8787/v1/responses`. It retains explicit request/response receipts,
supports ordinary task and tool calls through the same model interface, and
requires the API service's `full` mode for caller tools. It is not an OAuth/Codex
or OpenAI Responses endpoint; those profiles remain separate.

Optional `chatgpt` connection settings are `endpoint`, `issuer`, `auth_file`, and
`timeout_ms`; their defaults target OpenAI. `chatgpt: false` disables default
account discovery. `login PROFILE` selects a configured ChatGPT connection.
Profiles needing distinct registrations must use distinct `auth_file` paths.
Credentials from the former Codex-derived login format are rejected: run `login`
again and remove any configured `client_id` or ChatGPT `backend-api` endpoint from
`config.json`.

Manage app access and shared plan usage in
[ChatGPT usage settings](https://chatgpt.com/settings/usage). Sign-in does not grant
access to ChatGPT conversations. See [ADR 0027](adr/0027-official-chatgpt-sign-in.md)
for the account integration choices.

A Responses API profile uses `provider: "responses"`, `model`, and optionally
`endpoint` and `api_key_env` (default `OPENAI_API_KEY`). A stdio MCP entry under
`mcp` uses its server name as the key and `command`, `args`, optional `cwd`, and
optional string-valued `env` as its process settings. Unknown fields are rejected;
[host/config.mjs](../host/config.mjs) is the configuration parser.

Automatic context compaction has an independent top-level `compaction` setting.
The defaults start background work at 65% and block a later model request at 90%
of its effective window. Account model discovery supplies a window only when the
catalog advertises `context_window`; `effective_context_window_percent` is applied
when present. Other profiles need an explicit target budget, for example:

```json
"compaction": {
  "enabled": true,
  "background_percent": 65,
  "blocking_percent": 90,
  "idle_lead_ms": 60000,
  "targets": [
    {
      "profile": "coding",
      "window_tokens": 131072,
      "output_reserve_tokens": 8192,
      "cache_ttl_ms": null,
      "method": "auto"
    }
  ]
}
```

Use an existing profile key and the window supported by that connection.
`method: "auto"` prefers supported native compaction and uses the client summary
method for reconstruction; `"summary"` selects the client method. Compaction
targets use the `responses` or `chatgpt` provider. The offline `echo` profile and
the separate `chatgpt-web` continuation protocol cannot be compaction targets.
Responses connections without a token-counting route use an explicitly recorded
UTF-8 upper bound for readable inputs. Budgets must leave the summary method's
minimum input and output room. An omitted output reserve is the smaller
of 8192 tokens and one eighth of the target window. Thresholds must satisfy
`1 <= background_percent < blocking_percent < 100`.

`enabled: false` disables automatic triggers while retaining manual compaction
budgets. A `null` cache lifetime disables the idle cost trigger. Set
`cache_ttl_ms` only from the connection's known cache policy, with a value greater
than `idle_lead_ms`; it is an estimate for scheduling cost, not an expiry date for
history or compaction output. No account cache lifetime is assumed. Configuration
is checked at startup and the resolved policy is passed into the native feature;
`compactionSettings(config)` in `host/config.mjs` returns that same resolved policy.

Each task retains its selected model identity and complete tool definitions.
Later MCP catalog notifications change availability without rewriting that
contract. Forked tasks inherit the contract and message prefix, with explicit
branch results and fresh task identities.

## Speech input and voice conversations

Choose **Sign in for voice** to authorize the composer's dictation and live voice
controls. Selvedge opens ChatGPT's authorization page and manages this login,
credential storage and refresh itself. It follows Codex's ChatGPT OAuth flow and
calls the audio services directly. The public Sign in with ChatGPT connection
used for Responses has a separate permission scope and does not enable audio.

Select the ChatGPT audio connection independently of the Task's model profile.
The browser requests microphone access when recording starts; serve remote
browser clients over HTTPS, or use the local loopback server.

Finish dictation to insert the transcript into its original draft, then send it
through the ordinary composer. Cancel discards the recording. If the draft was
edited while transcription was pending, the recognized text remains available
for explicit insertion instead of replacing the new text.

Start voice in an existing Task or directly from the new Task form. A new voice
conversation creates an ordinary idle Task with the selected execution settings;
actual delegated work starts it. Spoken conversation appears in the same history
as task work. Microphone mute, playback mute and stopping voice have separate
controls. Stopping voice leaves accepted task work running, and its committed
history remains available after restart. API-key and ChatGPT Web profiles do not
provide the ChatGPT audio connection.


## Persistence

Back up the service home, including its journal, attachments and retained provider
receipts. The journal commits admitted inputs and decisions before dispatching
external effects. Restart checks its hash chain and replays those decisions with
the current kernel; incompatible formats or decisions fail explicitly. An ordinary
source update does not itself require a new home. The replacement does not read
Bend-format journals; see [migration behavior](migration.md).

Recovery cannot undo completed external effects or make arbitrary Bash edits
transactional. Concurrent commands and editors need their own revision checks,
locking or atomic replacement when a project requires those guarantees.
