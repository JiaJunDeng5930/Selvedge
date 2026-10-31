(** * Execution environments and recoverable resources

    A path does not identify an execution environment. A Task may borrow a
    resource without owning it, and accepted work may outlive the configuration
    from which it was issued. Execution must retain the admitted environment
    and recovery must preserve authority even when a physical outcome is lost. *)

From Selvedge.Features Require WorktreeProofs WorktreeCompletionProofs.
Export WorktreeProofs(reusing_a_binding_never_provisions_another_resource,
  admitted_scheduler_requires_ready_binding,
  a_live_pending_binding_holds_its_owner).
Export WorktreeCompletionProofs(received_creation_binds_or_stops,
  successful_setup_commits_queued_input_before_request_capture).

(** ** Resource identity is part of admitted execution

    Local and cloud backends share the managed-resource lifecycle: creation
    waits for preparation, live borrowers require availability, and archival
    waits for users of the resource. The backend is a typed domain value used
    by commands, retained resources and effects; a second host lifecycle would
    leave restart and archive policy outside those definitions.

    A controlled resource-owner reference is separate from Task lineage.
    Ordinary creation can inherit an environment without being a fork, while
    a fork can borrow a resource it does not own. External settings cannot
    manufacture that reference. [reusing_a_binding_never_provisions_another_resource]
    distinguishes borrowing from allocating. [admitted_scheduler_requires_ready_binding]
    and [a_live_pending_binding_holds_its_owner] protect every borrower, including
    one whose owner's setup failed or has not completed.

    The actual execution effect freezes the resource identity. The host resolves
    its physical receipt; it does not infer cloud ownership from a path or
    today's Task state. A missing binding fails rather than executing locally.
    Process input, filesystem observations and image snapshots use this same
    binding. Project observations without a Task binding remain local.

    An admitted setup result installs the observed workspace or stops its live
    owner. Successful setup records its settings and every queued user input
    before the next request captures history, as
    [successful_setup_commits_queued_input_before_request_capture] requires.

    Cloud setup uses the pushed repository commit and project-owned
    [.selvedge/env.sh]. The harness owns cloning, ordering, failure and cleanup;
    credentials remain host bindings. Cloud Bash has Full Access within its
    selected environment, while MCP servers remain host services. The environment
    notice is recorded in history so provider requests and accounting agree. *)

From Selvedge.Host Require CloudResourceProofs ResourceProofs.
Export CloudResourceProofs(recovery_trace_never_regains_allocation,
  retired_allocation_cannot_return, ssh_expiry_emits_no_probe).
Export ResourceProofs(local_recovery_trace_never_repeats_mutation,
  git_registration_requires_reservation_persisted_ack,
  preparation_requires_git_registration_persisted_ack).

(** ** A lost allocation response cannot authorize another allocation

    Before an allocation is emitted, its complete request, unique token and
    verified account/region/endpoint scope reach a durable control record.
    Identity observation and allocation use the same captured credential without
    persisting its secret. Recovery verifies the current credential against
    that scope and observes existing resources.

    [recovery_trace_never_regains_allocation] quantifies over a complete recovery
    trace. Together with [retired_allocation_cannot_return], it excludes
    allocation after intermediate observations as well as at startup.
    Reconciliation visits
    every management-tag page; empty, interrupted or unauthorized scans preserve
    uncertainty. Only recorded matches enter cleanup. The reserved provider tag
    namespace must not be altered by operators while an intent is open: mutable
    tags are an operational assumption, not an unforgeable ownership proof.

    Recording a discovered identity precedes destruction where storage permits.
    A confirmed in-memory identity may authorize cleanup after a failed write,
    but cannot turn the unresolved durable intent into successful persistence.
    Cleanup has its own deadline. Redirect rejection prevents an SDK request
    from silently dispatching one allocation to another endpoint.

    Local creation first records an exclusive reservation with canonical path,
    device, inode and fresh identity. Git registration and its acknowledgement
    are later facts. [git_registration_requires_reservation_persisted_ack] and
    [preparation_requires_git_registration_persisted_ack] express that order.
    Archive preserves tracked and untracked work by moving the registered
    checkout. Releasing an owned empty reservation uses nonrecursive removal;
    a path name alone is not deletion authority.

    [local_recovery_trace_never_repeats_mutation] forbids replaying checkout,
    move or release. Recovery may observe completed work and finish its
    durability barrier. Canonical Git backlinks admit both relative and
    absolute links before comparison with the owned checkout. *)

Export ResourceProofs(git_registration_waits_for_physical_durability,
  terminal_receipt_requires_matching_durable_ack,
  receipt_ack_cannot_skip_physical_durability).

(** ** Physical acknowledgement has a particular write set

    Git command completion does not establish durability. Registration,
    readiness, archive and release select their own file and directory barriers
    before a durable terminal receipt is published.
    [git_registration_waits_for_physical_durability],
    [terminal_receipt_requires_matching_durable_ack] and
    [receipt_ack_cannot_skip_physical_durability] constrain the extracted
    controller. A failed barrier keeps uncertainty.

    The shared publisher uses exclusive no-follow temporary files, file sync,
    same-directory rename and parent sync. New service directories are synced
    from stable ancestors. [host/worktrees.mjs] owns the concrete Git and path
    write sets; [host/resource-runtime.ts] acknowledges only completed physical
    barriers. These cover managed registration, path and initial-snapshot
    operations, not arbitrary later writes or symlink targets outside the tree.

    Closed phase constructors retain the evidence applicable to each resource
    state. Generated action unions and checked interpreters keep the host from
    choosing another continuation. SSH readiness retries follow observed
    transport failure and the controller's bounded deadline; a missing program
    is a preparation failure. SDK, SSH, Git, filesystem barriers, provider tags
    and credential verification remain physical assumptions. Obsolete receipts
    cannot be upgraded into missing recovery authority by a fallback decoder. *)
