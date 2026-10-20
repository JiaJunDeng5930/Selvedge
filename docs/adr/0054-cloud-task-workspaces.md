# ADR 0054: Bind task workspaces to execution environments

## Context

A task can prepare a local Git worktree or a remote filesystem before executing.
Its existing startup coordination already waits for a committed workspace result,
then binds the task and starts the model. A second lifecycle in the host would
split that authority and make restart and archive behavior depend on transient
JavaScript state. A remote path alone cannot identify an execution environment:
the same absolute path can exist on the host and on several instances.

## Decision

Keep the native task resource as the authority for backend identity, ownership and
completion. Reuse its startup and archive coordination for both backends. The host
workspace entry dispatches physical creation, recovery and recycling; the local
backend retains the existing worktree behavior. The cloud abstraction supplies
an execution and filesystem binding, with Tencent Cloud CVM spot instances as its
first infrastructure backend.

Use the official Tencent SDK for instance APIs and OpenSSH for process transport.
The existing Bash and process-session tools retain their contracts. Process
control and filesystem observations resolve through the same resource binding,
so an unavailable cloud environment cannot turn into execution against a local
path. Cloud Bash uses Full Access; MCP servers remain host services, and the model
receives the corresponding path reminder.

Projects own environment setup through `.selvedge/env.sh` in their GitHub
repository. This keeps package and language initialization with the code that
needs it. The harness owns cloning, execution order, startup failure and instance
cleanup. It records the creation token and instance receipt outside the disposable
environment so a failed script or interrupted startup can still be reclaimed.
Tencent and GitHub credentials stay at the host boundary rather than in task
history or repository URLs.

## References

- [Tencent Cloud RunInstances API](https://www.tencentcloud.com/document/product/213/33237)
- [Creating a spot instance](https://www.tencentcloud.com/document/product/213/17926)
- [Tencent Cloud Node.js SDK](https://github.com/TencentCloud/tencentcloud-sdk-nodejs)
