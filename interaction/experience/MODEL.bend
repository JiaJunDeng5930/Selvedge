import Base
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms
import ../services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as D

type Subject is Data:
  Subject{editor: U.Editor, field: Forms.Field}

type Object is Data:
  TaskDraft{}
  Task{task: Nat}
  Project{project: Maybe<&2, Nat>}
  MessageDraft{task: Nat}
  EditorObject{editor: U.Editor}
  WorkspaceOf{editor: U.Editor}
  ExecutionConfigurationOf{editor: U.Editor}

type Value is Data:
  Filesystem{mode: D.SandboxMode}
  Network{enabled: Bool}
  Approval{choice: Context.ApprovalChoice}
  Model{profile: D.Profile}
  Effort{effort: String}
  PrimaryDirectory{path: String}

type Alternative is Data:
  Alternative{label: String, explanation: String, value: Value}

type Availability is Data:
  Available{}
  Unavailable{reason: String}

type Decision is Data:
  Decision{subject: Subject, observation: Forms.Observed, question: String,
    alternatives: +List<Alternative>, availability: Availability}

type Collection is Data:
  Collection{editor: U.Editor, workspace: D.Workspace}

type ActionIdentity is Data:
  ActionIdentity{editor: U.Editor, revision: Nat}

type ActionContext is Data:
  Creation{}
  Continuation{task: Nat}
  ObjectEditing{}

type ActionUnit is Data:
  ActionUnit{identity: ActionIdentity, pending: Bool}

type Support is Data:
  Support{identity: ActionIdentity, fields: +List<Forms.Field>}

type Feedback is Data:
  Feedback{editor: U.Editor, revision: Nat, reason: String}

# These observations are constructed by the owning operations, then read through
# getters. A missing reference remains distinct from an optional absent value.
type PropertyKind is Data:
  ProjectProperty{}
  WorkspaceProperty{}
  PermissionsProperty{}
  ModelProperty{}
  DeliveryProperty{}

type PropertyState is Data:
  Selected{}
  Absent{}
  Invalid{}
  UnavailableObservation{}

type Property is Data:
  ProjectObservation{editor: U.Editor, selected: Maybe<&2, Nat>, found: Maybe<&2, D.Project>}
  WorkspaceObservation{editor: U.Editor, observation: Context.Observation, source: Maybe<&2, D.Project>}
  PermissionsObservation{editor: U.Editor, observation: Context.Observation}
  ModelObservation{editor: U.Editor, profile: String, effort: String, found: Maybe<&2, D.Profile>}
  DeliveryObservation{editor: U.Editor, delivery: U.Delivery}

type Obstruction is Data:
  Obstruction{target: Object, field: Maybe<&2, Subject>, code: String, message: String}

type AssessmentState is Data:
  Ready{}
  NeedsDirectoryObservation{}
  Blocked{}

type Assessment is Data:
  Assessment{identity: ActionIdentity, requirements: +List<Obstruction>, state: AssessmentState,
    refusal: Maybe<&2, Obstruction>}
