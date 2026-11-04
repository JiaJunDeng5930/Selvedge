(** * Execution environments and recoverable resources

    A path does not identify an execution environment. A Task may borrow a
    resource without owning it, and accepted work may outlive the configuration
    from which it was issued. Execution must retain the admitted environment
    and recovery must preserve authority even when a physical outcome is lost. *)

From Selvedge.Features Require WorktreeProofs WorktreeCompletionProofs.
Export WorktreeProofs(reusing_a_binding_never_provisions_another_resource,
  admitted_scheduler_requires_ready_binding,
  a_live_pending_binding_holds_its_owner,
  mismatched_cloud_project_is_rejected).
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
    Local sandbox preparation observes the running platform and architecture
    directly. No caller selects a different host platform when interpreting an
    admitted execution plan.
    [ToolArguments.bash_parameters] carries the admitted [Process.transport]
    into Bash launch. Its closed constructors select pipe or PTY execution;
    image reads use pipe execution. The internal sandbox adapter receives that
    selection and needs no second admission rule for arbitrary mode strings.
    The isolation contract governs execution authority, filesystem bindings and
    the applied filter policy. Enumerating the numeric encodings of the closed
    instruction constructors adds no isolation guarantee.

    An admitted setup result installs the observed workspace or stops its live
    owner. Successful setup records its settings and every queued user input
    before the next request captures history, as
    [successful_setup_commits_queued_input_before_request_capture] requires.

    When a Project is selected, its primary root must match the source selected
    for cloud preparation. [mismatched_cloud_project_is_rejected] requires
    refusal when they differ, because cloning another source would change the
    Task's execution environment. Other invalid workspace fields may determine
    the reported refusal cause.

    Cloud setup uses the pushed repository commit and project-owned
    [.selvedge/env.sh]. The harness owns cloning, ordering, failure and cleanup;
    credentials remain host bindings. Cloud Bash has Full Access within its
    selected environment, while MCP servers remain host services. The environment
    notice is recorded in history so provider requests and accounting agree.
    Provider context must retain that recorded guidance. Its explanatory wording
    can evolve without changing the bound environment or execution permissions. *)

From Selvedge.Host Require CloudResourceProofs ResourceProofs.
From Selvedge.Adapters Require CloudWorkspacesProofs.
Export CloudWorkspacesProofs(admitted_receipt_preserves_expected_fields).
Export CloudResourceProofs(recovery_trace_never_regains_allocation,
  retired_allocation_cannot_return, ssh_expiry_emits_no_probe,
  ssh_wait_fits_remaining_deadline,
  reconciled_termination_matches_the_unique_owned_instance).
Export ResourceProofs(local_recovery_trace_never_repeats_mutation,
  git_registration_requires_reservation_persisted_ack,
  preparation_requires_git_registration_persisted_ack,
  admitted_git_registration_matches_its_reservation,
  unregistered_release_requires_its_observed_directory).

(** ** A lost allocation response cannot authorize another allocation

    Before an allocation is emitted, its unique token and verified
    account/region/endpoint scope reach a durable control record.
    Identity observation and allocation use the same captured credential without
    persisting its secret. Recovery verifies the current credential against
    that scope and observes existing resources.

    [recovery_trace_never_regains_allocation] quantifies over a complete recovery
    trace. Together with [retired_allocation_cannot_return], it excludes
    allocation after intermediate observations as well as at startup.
    Each request allocates one instance. Reconciliation admits the matching
    instance under its unique management tag; empty, interrupted or unauthorized
    observations preserve uncertainty. Only that match enters cleanup, and a
    unique tagged instance must enter cleanup even when its configuration has
    changed. [reconciled_termination_matches_the_unique_owned_instance] constrains
    both directions of the actual selection. Image, instance type and network
    settings describe preparation; requiring their old values during cleanup
    can leave the owned instance running and billable. The first allocation
    constructs its request from the captured backend settings and the recorded
    token and Task identity. Recovery never repeats allocation, so the complete
    request is not retained in the recovery record.
    The reserved provider tag namespace must not be altered by operators while an
    intent is open: mutable tags are an operational assumption, not an
    unforgeable ownership proof.

    Recording a discovered identity precedes destruction where storage permits.
    A confirmed in-memory identity may authorize cleanup after a failed write,
    but cannot turn the unresolved durable intent into successful persistence.
    Cleanup has its own deadline. Redirect rejection prevents an SDK request
    from silently dispatching one allocation to another endpoint.

    Local creation first records an exclusive reservation with canonical path,
    device and inode. A random label copied only into a receipt has no physical
    anchor and adds no ownership authority. Git registration and its acknowledgement
    are later facts. [git_registration_requires_reservation_persisted_ack] and
    [preparation_requires_git_registration_persisted_ack] express that order.
    Archive preserves tracked and untracked work by moving the registered
    checkout. [admitted_git_registration_matches_its_reservation] binds admission
    to the observed root, Git backlink, repository, device and inode. A linked
    checkout is admitted once before its independent registration is classified.
    [unregistered_release_requires_its_observed_directory] requires the original
    reserved directory without a Git registration before release. Nonrecursive
    removal itself rejects a populated directory; a prior directory enumeration
    cannot establish emptiness at the later removal. A path name alone is not
    deletion authority.

    [local_recovery_trace_never_repeats_mutation] forbids replaying checkout,
    move or release. Recovery may observe completed work and record its
    acknowledgement. Canonical Git backlinks admit both relative and
    absolute links before comparison with the owned checkout. *)

(** ** Recovery records retain outstanding resource ownership

    Successful Git commands and completed file copies establish the observed
    checkout outcome. Atomic control-record publication retains the reservation,
    ownership and result needed for service restart. Reopening still checks the
    actual path and Git registration before returning or deleting a resource.
    The checkout guarantee covers service-process restart. Repository contents
    follow Git's durability policy; preserving every copied project file across
    host power loss is outside this resource contract. Recovery control records
    retain their separate persistence requirement.

    Cloud recovery records retain the outstanding instance or the fact that
    allocation remains unresolved. Failed cleanup retains its instance for an
    explicit archive retry. Allocation and destruction outcomes are observed
    at the provider. The verified provider, account, region and endpoint identify
    recovery authority; a label for the credential source adds no principal
    identity. The allocated instance ID identifies the resource needed for
    observation and cleanup. A provider request ID only supports diagnostics
    and cannot establish allocation ownership.

    An instance lookup requires the provider's [InstanceSet] array. A missing
    list is an observation failure; it cannot establish that the instance no
    longer exists. The existing cleanup failure retains the allocation for an
    explicit archive retry. [tests/cloud-workspaces.test.mjs] exercises this
    distinction through the public service and a real HTTP provider peer.

    Receipt admission checks the original receipt retained by its physical
    owner. [admitted_receipt_preserves_expected_fields] binds that admitted
    input to its expected task identity; returning a second copy adds no
    authority. Admission preserves the supplied JSON spelling. Cloud configuration
    decoding at backend use also normalizes valid integer spellings before host
    arithmetic: a receipt may spell its startup timeout as [1e3]. That conversion
    remains necessary even after receipt validation has established the settings
    shape and bounds.

    Setup logs aid diagnosis; they do not establish allocation or readiness.
    A log write failure is reported through service diagnostics without
    preventing successful preparation or cleanup. The recovery receipt retains
    its independent persistence requirement. [tests/cloud-workspaces.test.mjs]
    exercises successful and failed setup with an unwritable diagnostic log.

    Closed phase constructors retain the evidence applicable to each resource
    state. Status labels alone establish neither ownership nor recovery
    authority. Receipt admission uses the controller's decoded phase and adds
    the expected task identity and owned path; workspace declarations already
    admit the root text used by membership and containment checks.
    Each resource controller selects one physical action before awaiting its
    observation. The local plan carries one local action; a cloud transition
    carries one cloud action or explicitly has no matching transition. Their
    typed Schema encoders also supply the generated host declarations, retaining
    both the backend's action range and its single-step meaning. There is no
    unused action-list suffix for an interpreter to discard. A missing cloud
    action remains an interpretation failure and grants no physical operation.
    Checked interpreters keep the host from choosing another continuation.
    SSH readiness retries follow observed
    transport failure and the controller's bounded deadline; a missing program
    is a preparation failure. [ssh_expiry_emits_no_probe] requires an expired
    readiness check to return refusal from the actual controller. The host
    dispatches on the refusal constructor, so its diagnostic text may evolve
    independently of the deadline contract.
    [ssh_wait_fits_remaining_deadline] requires each
    probe timeout and retry delay to be positive and fit the deadline remaining
    at its clock observation. Zero must not disable the physical probe timeout.
    The awaited probe or delay already determines which observation comes next;
    separate progress or terminal states would add no recovery information.
    Project guidance can change while the service is
    stopped, so readiness revalidation observes it again rather than retaining
    the old contents. SDK, SSH, Git, filesystems, provider tags and
    credential verification remain physical assumptions. Obsolete receipts
    cannot be upgraded into missing recovery authority by a fallback decoder. *)
