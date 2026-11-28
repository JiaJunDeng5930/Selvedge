# Using Selvedge

## Conversations and shared work

Type `/side` in a Task message to open a side conversation, optionally followed
by a question. It starts from the parent's captured conversation while the
parent continues. Closing the side keeps its Task; the explicit return action
sends only its new content back to the parent.

Conversation search finds current titles and user and assistant messages, with
optional Project and Work filters. A title result opens the conversation.
A message result opens the original message and highlights the matching text
when it appears in the rendered message. Running Tasks can use
`search_history` with the same filters and history positions. Set
`include_titles` to include title matches. Type `@`
in a message to select an available skill and insert its exact `SKILL.md` reference.

Use **对话范围** above the conversation list to show **全部对话** or a named Work
(工作组). A Work has its own conversation list, task graphs and shared interface.
Projects independently organize conversations and provide default directories and
instructions. Click a project name to see its configuration and conversations, or
use its plus button to start a conversation there. A graph connects ordinary Task
outputs to inputs.
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

## Workflow instances

Open **任务图** and choose **创建工作流** in the desired Work. Use the
form to add nodes and connect them, or open **高级选项** to edit the JSON
definition. A definition lists `nodes` and `connections`. Each node has a `key` and a `kind` of
`entrance`, `exit`, or `task`. A Task node names either `task_id` or a
configured `profile` and `creation` policy. Use `once` to keep one Task
conversation per instance, or `each` for a fresh conversation per delivery.

Each connection names its `key`, `source`, and `target`. Messages forward
unchanged by default. A connection also accepts the existing output, literal
and concatenation expressions. A Task with several outgoing connections
receives each connection's `description` and calls
`choose_workflow_connection` before its final answer. An entrance can send
the same message down multiple paths. Every path must reach an exit before
the instance completes.

Use **启动工作流** to choose an entrance and enter the message, or choose a
workflow and entrance in a ticket's details and then start its instance.
The active nodes show one dot per instance, with the same color on each of
its active nodes. Open the instance from a dot, the workflow, or the ticket.
Instance details link to its Tasks and let you expand each exit result
or inspect blocked paths. A ticket follows its current instance and completes
automatically when that instance succeeds. Direct starts and ticket starts
create separate instances, and editing the definition affects later starts.

The terminal exposes the same operations through `create_workflow`,
`update_workflow`, `start_workflow`, `list_workflows`,
`read_workflow_instance`, `configure_ticket_workflow` and
`start_ticket_workflow`.

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
object with `project_id`, `workspace`, `sandbox`, `approval`, and
`realtime_context`.

Above the new conversation input, select the project, choose its Workspace,
and optionally turn on Temporary worktree. A project supplies its configured
machine and directories. To use a different paired machine, choose its
directories there. The switch becomes available when the selected host or
receiver primary belongs to a Git repository with a commit. Selecting Tencent
Cloud CVM turns the switch off. The cloud machine provisions its own checkout.
A project's `create_worktree` preference initializes the local choice. Enabling
the default, or changing its primary workspace while enabled, requires a Git
repository with an initial commit on the selected machine. The Project editor
and the public Project commands use the same verification.
Starting a conversation with a local worktree remembers it as the Project default
when the verified primary is also the Project primary. The programmatic local entry is
`create_worktree_task`; `create_workspace_task` additionally accepts the typed
`backend` name `local` or `tencent_cvm`. Both use the existing task startup and
archive lifecycle.
Managed checkouts live under `<service home>/worktrees` on the selected machine,
start at detached HEAD,
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
settings are preserved. An explicitly configured offline echo profile cannot
approve.

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

`spot_max_price` is an hourly bid in the Tencent Cloud account's billing
currency. Set `TENCENTCLOUD_SECRET_ID` and `TENCENTCLOUD_SECRET_KEY` in the service
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
reads use the task's bound environment. MCP tools use their configured servers.
The model receives an environment notice describing that distinction. Forked
tasks share the same bound resource. Archiving a child does not destroy its
owner's instance, and an instance cannot be recycled while another task uses it.

To use voice with a cloud task, create the task first, then start voice in its
conversation.

Failed setup reclaims its allocation. Setup output is written under
`<service home>/cloud-workspaces/<journal namespace>/task-<id>.log`; a log write
failure is reported through service diagnostics without blocking preparation
or cleanup. If reclamation fails, the task retains the failure and resource association;
`retry_worktree_archive` retries cleanup. Restart recovery reconciles the
persisted allocation receipt with the same task resource.
Archiving the owning task recycles its cloud instance after active IO has settled.

### Shared execution environments

A task can use the workspace of a second Selvedge installation over an
authenticated TLS WebSocket. In the working-directory settings of a new task
or a Project, choose the directory machine and add or browse directories on
that machine. A task can inherit its Project's configured workspace. The task,
conversation, model call and existing Bash
approval flow stay with the task service. Bash, terminal I/O and reads of the
workspace use the receiver's filesystem and sandbox. MCP services use their
configured host.

Create a private token file on the receiver and copy it privately to the task
machine. Use a TLS certificate valid for the receiver's address and listen on
an interface reachable from the task machine.

```sh
(umask 077; openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\n' > /path/to/execution-token)
bun host/cli.mjs --home /path/to/receiver-home receive-execution \
  --host 192.168.1.10 --port 4443 --cert-file /path/to/receiver.pem \
  --key-file /path/to/receiver-key.pem --token-file /path/to/execution-token
```

The receiver trusts the paired task service to send execution parameters
produced by the regular Selvedge task workflow. An approved escalation or
Full Access runs with the receiver process's OS identity. Choose that identity
and its readable files accordingly. The receiver home stores durable operation
receipts, including retained results, and should be private.

On the task machine, open **设置 → 任务 → 远程执行连接** and add the receiver.
Enter a machine name, its WSS address and the local token file path. Set a
local CA file path when the receiver uses a private CA, then click **添加**.
Restart the task service to apply changes to the connections. You can also set
the connection in `config.json`.

```json
{
  "format": "selvedge-rocq-config-1",
  "execution_environments": [
    {
      "id": "build-machine",
      "url": "wss://192.168.1.10:4443/execution",
      "token_file": "/path/on/task-machine/execution-token",
      "ca_file": "/path/on/task-machine/receiver-ca.pem"
    }
  ]
}
```

Keep the environment ID stable for the same receiver. CLI and API callers can
select it with `settings.workspace.environment` and supply paths on the
receiver, for example
`--settings '{"workspace":{"roots":["/path/on/receiver/project"],"environment":"build-machine"}}'`.
The workspace stays bound if its receiver disconnects. A repeated operation
ID retrieves the original result. If a receiver restarts before recording a
result, Selvedge reports that the operation may already have run.

#### Share an MCP server

Use the regular Selvedge service on the receiver machine to share a server from
its existing `mcp` configuration. For example, on a Mac already running the
`cua` MCP server, add this entry to the Mac service's `config.json`.

```json
{
  "execution_receiver": {
    "host": "192.168.1.10",
    "port": 4443,
    "cert_file": "/path/to/receiver.pem",
    "key_file": "/path/to/receiver-key.pem",
    "token_file": "/path/to/execution-token",
    "mcp_servers": ["cua"]
  }
}
```

If a standalone `receive-execution` command already owns this port, stop it
before restarting the regular service with the same endpoint, files and token.
Set `receipt_home` to the standalone receiver's previous `--home` if it differs
from the Mac service home. This keeps the existing execution receipts. The
integrated receiver serves both Bash and the local MCP servers in its
`mcp_servers` list. You can add a server to that list with
`bun host/cli.mjs mcp export --server cua`, then restart the Mac service.

On the task machine, add or reuse the remote execution connection. These
commands discover and import a server from the connection named `mac`.

```sh
bun host/cli.mjs mcp list --environment mac
bun host/cli.mjs mcp import --environment mac --server cua --name mac_cua
```

Restart the task service to apply the import. New tasks can discover and call
the imported server regardless of their workspace. The Mac service uses the
same MCP process for local and remote callers. Its MCP credentials and process
permissions apply to both. A receiver that disconnects withdraws its live tools
until reconnect and rediscovery. Existing tasks retain their tool definitions
and target. Update both installations before configuring shared MCP.

## Use it on a project

The service launch directory supplies the default workspace for a new task that
does not select a project or explicit roots. It is not a shared task directory
or a permission boundary. For example, after building this checkout:

```bash
cd /absolute/path/to/project
bun /absolute/path/to/Selvedge/host/cli.mjs --home /absolute/path/to/task-home server
```

Each stored task retains its canonical roots and execution settings. Restarting
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
carry private artifact paths and explicit retention limits.
An artifact capped at 8 MiB retains the latest raw output bytes. Inspect
it through Bash. Nonzero exits, deadlines and cancellation are tool errors, and
shell descendants are terminated when the shell exits.
The executable catalog and `limits` in `describe` are authoritative.

Initial instructions and guidance enter task history with their source identity
and revision. Before model and summary requests, the service refreshes configured
instructions, service-home guidance, and guidance across all workspace roots.
Discovery includes each root's Git ancestor chain and its nested directories.
The service discovers new rules when it starts working on a new user message.
Later model calls for that message reread the rules already found. A changed
workspace or a missing known rule refreshes the corresponding discovery.
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

Before a Responses model request, Selvedge appends the selected realtime
readings to the end of the model input. The default sources are
`current_time` (UTC) and `task_elapsed_time` (milliseconds since task creation).
Set `"realtime_context": ["current_time"]` in task settings to select just the
clock, or use an empty array to disable both sources. The readings are sampled
only during model dispatch and are absent from task history and compaction.
[ChatGPT Web v1](chatgpt-web.md) skips the readings because its continuation
protocol stores input messages in the remote conversation.

Compaction includes the current history-derived model input, including tracked
context introductions and updates. After compaction, the model receives the
latest complete tracked context at the captured position, the replacement
summary, messages committed after that position, and finally the current
realtime readings. The original task history remains readable. A provider
that cannot consume a native opaque replacement rebuilds from readable
records. The
[compaction definitions](../theories/Features/Compaction.v) and shared
[context selection](../theories/Kernel/ContextSelection.v) own those rules.

## Model and tool configuration

The default home is `~/.selvedge`. `bun host/cli.mjs init` creates its
`config.json` without overwriting an existing file. `--home PATH` and `--config
FILE` select explicit locations; both options also work with `bun run start ...`.
In the local web interface, open **Settings** and select a category to see the
current settings. Edit the value in its row, then choose **Apply configuration
change**. Structured settings open a JSON editor in the same row. **Reset
configuration item** removes an optional override. Configuration read at startup
takes effect on the next successful start. Context sources that already reread
configuration continue to do so.

One ChatGPT sign-in authorizes account models, dictation, and live voice. In the
web interface, choose **Sign in with ChatGPT** under **Settings → Models →
ChatGPT model access** or in the composer's voice menu.

- **Device code** works when Selvedge runs on a remote host. Enable device code
  login in your ChatGPT security settings or workspace permissions. Open the
  ChatGPT link, enter the one-time code shown in Selvedge, and return to the
  page after approving. The code expires in 15 minutes.
- **Browser callback** opens the ChatGPT authorization page and completes through
  a temporary loopback listener on the host running Selvedge.

The CLI uses the browser callback flow:

```bash
bun host/cli.mjs login
bun host/cli.mjs models
```

The browser callback uses `127.0.0.1:1455`
or `127.0.0.1:1457` when the first port is busy. For a service on a remote host,
forward the port in the login URL to the same port on that host with SSH before
completing authorization. Login refreshes the running service's model catalog.
Use `models --refresh` to fetch a fresh catalog and select a reasoning level
advertised by the selected model.

The separate [ChatGPT Web backend](chatgpt-web.md) uses
`provider: "chatgpt-web"`, a model such as `chatgpt-web/high`, and the API
application token in `CHATGPT_WEB_TOKEN`. Its default endpoint is
`http://127.0.0.1:8787/v1/responses`. It retains explicit request/response receipts,
supports ordinary task and tool calls through the same model interface, and
requires the API service's `full` mode for caller tools. It is not an OAuth/Codex
or OpenAI Responses endpoint; those profiles remain separate.

Optional `chatgpt` connection settings are `endpoint`, `issuer`, `auth_file`, and
`timeout_ms`. Account models use the Codex Responses endpoint by default.
`chatgpt: false` disables default account discovery. `login PROFILE` selects an
explicitly configured ChatGPT account. Distinct accounts use distinct `auth_file`
paths. After upgrading from separate model and voice authorizations, run `login`
again to establish the shared credential. Remove explicit public Responses
endpoint overrides on account profiles to select the current Codex endpoint.

Manage app access and shared plan usage in
[ChatGPT usage settings](https://chatgpt.com/settings/usage). Sign-in does not grant
access to ChatGPT conversations. The [backend requirements](../requirements/Backends.v)
explain the account identity and credential lifetimes.

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
targets use the `responses` or `chatgpt` provider. An explicitly configured
offline `echo` profile and the separate `chatgpt-web` continuation protocol
cannot be compaction targets.
Responses connections without a token-counting route use an explicitly recorded
UTF-8 upper bound for readable inputs. ChatGPT account connections estimate
the request size locally for scheduling and use the Codex response stream for
native compaction. Budgets must leave the summary method's
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

### Task monitoring and waiting

A task can pass `monitor: true` to `create_task` or `fork_task` to monitor each
new task from its first reply. The option defaults to false. To follow an
existing task, call `monitor_task` with its `task_id`.

New commentary and final answers enter the observer's history automatically,
with the source task and message phase. Monitoring spans later turns in both
tasks, including turns that start after a final answer. Use `unmonitor_task`
to stop future delivery. Archiving either task ends the subscription.

Use `wait` to suspend the current turn until new input is available. The task
shows `waiting_for_input` and does not spend model requests while waiting.
User input, a message from another task, monitored output, or a completed
operation can resume it. The original call returns `0` on resumption. If unread
input has already arrived, the call returns immediately.

## Speech input and voice conversations

Dictation and live voice use the installation's ChatGPT sign-in. If you have
already signed in for account models, the voice menu can use that credential.

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
history remains available after restart. Tasks using API-key or ChatGPT Web
profiles can still use the installation's signed-in ChatGPT account for voice.


## Development updates

Run `bun run update` in the source checkout to build, install, and start it in
the background. Run the same command again after editing the checkout. Use
`bun run update --home /path/to/home` to update a separate service and `--config`
to select a different configuration file. `bun run start` starts a managed
release in the foreground. For a server started directly with `bun host/cli.mjs
server` or a release that predates managed updates, stop it once after its tools
finish, then run the update command.

The old release serves its existing address while the candidate builds and
checks a consistent read of the state database. Before yielding the service
address, the running release pauses task scheduling and lets active operations
settle. Once it owns the database, the candidate loads the latest committed
records and starts serving. Tasks awaiting input or approval keep that state
and are available after reconnecting. The browser reconnects to the same address
and restores the current view and draft text when it loads the new release.

A failure checking the stored state leaves the current service running. A
startup failure after the old service yields ownership restores the database
backup and restarts the previous release with its working configuration.
Managed releases and their logs live under `releases/` in the service home.

## Persistence

The service home contains the SQLite state database, attachments and provider
receipts. Each commit saves the changed task and shared records together before
dispatching external effects. On restart the service loads the stored records,
then handles operations that were still outstanding. An incompatible database
format or invalid stored record fails startup.

Recovery cannot undo completed external effects or make arbitrary Bash edits
transactional. Concurrent commands and editors need their own revision checks,
locking or atomic replacement when a project requires those guarantees.
