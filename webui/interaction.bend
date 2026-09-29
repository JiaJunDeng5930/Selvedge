import Base

# Web realization semantics. Measurements and browser completions are inputs;
# effects describe browser work. Product intent is defined by core/SYSTEM.bend.
# A reading anchor is an opaque content identity and an offset in the adapter's
# logical coordinate system. Geometry and focus observations are external input.
type Anchor is Data:
  Anchor{identity: String, offset: F32}

type Reading is Data:
  FollowingLatest{}
  ReadingHistory{anchor: Anchor}

type ReadingEvent is Data:
  ReadHistory{anchor: Anchor}
  FollowLatest{}
  LayoutChanged{}

type ScrollEffect is Data:
  LeaveViewport{}
  AlignLatest{}
  PreserveAnchor{anchor: Anchor}

type ReadingDecision is Data:
  ReadingDecision{reading: Reading, effect: ScrollEffect, window: WindowEffect}

type WindowEffect is Data:
  KeepWindow{}
  PinWindow{}
  LatestWindow{}

type Draft is Data:
  Draft{owner: String, text: String, revision: Nat}

type Selection is Data:
  Selection{start: Nat, end: Nat, direction: String}

type Editor is Data:
  Editor{draft: Draft, selection: Selection, intent: String}

type Scope is Data:
  Scope{identity: String, trigger: String, target: String}

type Focus is Data:
  Focus{scopes: +List<Scope>}

type FocusDecision is Data:
  FocusDecision{focus: Focus, target: String}

type CopyState is Data:
  CopyIdle{}
  CopyPending{}
  CopySucceeded{}
  CopyFailed{}

type CodeView is Data:
  CodeView{wrap: Bool, copy: CopyState}

type Rect is Data:
  Rect{left: F32, top: F32, right: F32, bottom: F32}

type Target is Data:
  Target{visible: Bool, enabled: Bool, keyboard: Bool, pointer: Bool,
    bounds: Rect}

def initial_reading() -> Reading:
  FollowingLatest{}

def restore_window(reading: Reading) -> WindowEffect:
  match reading:
    case FollowingLatest{}: KeepWindow{}
    case ReadingHistory{anchor}: PinWindow{}

# Request ownership includes the lifetime of the mounted reader, not only the
# thread key. A queued request from an earlier mount must not change a newer
# reader, even after switching away from a thread and returning to it.
def owns_reading(requested: String, current: String) -> Bool:
  String.eq(requested, current)

def layout_effect(reading: Reading) -> ScrollEffect:
  match reading:
    case FollowingLatest{}: AlignLatest{}
    case ReadingHistory{anchor}: PreserveAnchor{anchor}

def enter_history(anchor: Anchor, previous: Reading) -> ReadingDecision:
  match previous:
    case FollowingLatest{}: ReadingDecision{ReadingHistory{anchor}, LeaveViewport{}, PinWindow{}}
    case ReadingHistory{old}: ReadingDecision{ReadingHistory{anchor}, LeaveViewport{}, KeepWindow{}}

def reading_step(event: ReadingEvent, +reading: Reading) -> ReadingDecision:
  match event:
    case ReadHistory{anchor}: enter_history(anchor, reading)
    case FollowLatest{}: ReadingDecision{FollowingLatest{}, AlignLatest{}, LatestWindow{}}
    case LayoutChanged{}: ReadingDecision{reading, layout_effect(reading), KeepWindow{}}

def follows_latest(reading: Reading) -> Bool:
  match reading:
    case FollowingLatest{}: True{}
    case ReadingHistory{anchor}: False{}

# Revision, not text equality, identifies a submitted edit. Typing the same text
# again while a submission is pending must still create a new, unsubmitted draft.
def initial_draft(owner: String, text: String) -> Draft:
  Draft{owner, text, 0n}

def edit_draft(text: String, draft: Draft) -> Draft:
  Draft{owner, previous, revision} = draft
  Draft{owner, text, 1n+revision}

def draft_matches(submitted: Draft, current: Draft) -> Bool:
  Draft{owner, text, revision} = submitted
  Draft{current_owner, current_text, current_revision} = current
  String.eq(owner, current_owner) && Nat.is_eq(revision, current_revision)

def clear_draft(clear: Bool, draft: Draft) -> Draft:
  match clear:
    case False{}: draft
    case True{}:
      Draft{owner, text, revision} = draft
      Draft{owner, "", 1n+revision}

def acknowledge_draft(accepted: Bool, retained: Bool, submitted: Draft, +current: Draft) -> Draft:
  match accepted retained:
    case True{} False{}: clear_draft(draft_matches(submitted, current), current)
    case _ _: current

# Submission intent is independent of the editor's identity, content and range.
def select_intent(intent: String, editor: Editor) -> Editor:
  Editor{draft, selection, previous} = editor
  Editor{draft, selection, intent}

def submit_key(composing: Bool, enter: Bool, multiline: Bool, modified: Bool,
  shift: Bool, alt: Bool, enabled: Bool, pending: Bool) -> Bool:
  Bool.not(composing) && enter && Bool.not(shift) && Bool.not(alt) &&
    (multiline || modified) && enabled && Bool.not(pending)

# A stack expresses temporary focus ownership. Only its top owner can close;
# Escape cannot dismiss a menu and the dialog beneath it in the same event.
def initial_focus() -> Focus:
  Focus{Nil{}}

def enter_scope(scope: Scope, focus: Focus) -> FocusDecision:
  match scope focus:
    case Scope{identity, trigger, +target} Focus{scopes}:
      FocusDecision{Focus{Scope{identity, trigger, target} <> scopes}, target}

def leave_top(allowed: Bool, scope: Scope, rest: +List<Scope>) -> FocusDecision:
  match allowed scope:
    case True{} Scope{identity, trigger, target}: FocusDecision{Focus{rest}, trigger}
    case False{} Scope{identity, trigger, target}:
      FocusDecision{Focus{Scope{identity, trigger, target} <> rest}, ""}

def leave_scope(identity: String, focus: Focus) -> FocusDecision:
  Focus{scopes} = focus
  match scopes:
    case Nil{}: FocusDecision{Focus{Nil{}}, ""}
    case Con{Scope{+key, trigger, target}, rest}:
      leave_top(String.eq(identity, key), Scope{key, trigger, target}, rest)

def focus_owner(focus: Focus) -> String:
  Focus{scopes} = focus
  match scopes:
    case Nil{}: ""
    case Con{Scope{identity, trigger, target}, rest}: identity

# A delayed close callback may restore only its own focus. A newer menu,
# dialog, or explicit user focus move supersedes that earlier restoration.
def restore_focus(closing: String, parent: String, +current: String, still_owned: Bool) -> Bool:
  (String.eq(current, closing) || String.eq(current, parent)) && still_owned

def submission_focus(accepted: Bool, still_owned: Bool) -> Bool:
  accepted && still_owned

# Copy feedback acknowledges the platform result, not the click. Wrapping is a
# display choice; the adapter retains the same literal source and DOM identity.
def initial_code_view() -> CodeView:
  CodeView{False{}, CopyIdle{}}

def toggle_code_wrap(view: CodeView) -> CodeView:
  CodeView{wrap, copy} = view
  CodeView{Bool.not(wrap), copy}

def code_can_copy(view: CodeView) -> Bool:
  match view:
    case CodeView{wrap, CopyPending{}}: False{}
    case other: True{}

def begin_code_copy(view: CodeView) -> CodeView:
  CodeView{wrap, copy} = view
  CodeView{wrap, CopyPending{}}

def finish_code_copy(ok: Bool, view: CodeView) -> CodeView:
  match ok view:
    case True{} CodeView{wrap, copy}: CodeView{wrap, CopySucceeded{}}
    case False{} CodeView{wrap, copy}: CodeView{wrap, CopyFailed{}}

def expire_code_feedback(view: CodeView) -> CodeView:
  match view:
    case CodeView{wrap, CopyPending{}}: CodeView{wrap, CopyPending{}}
    case CodeView{wrap, other}: CodeView{wrap, CopyIdle{}}

# Observable realization, not a claim that the type checker executes a layout
# engine. Adapters supply measured bounds, hit tests and accessibility/focus
# observations. These predicates specify the adapter realization boundary.
def contains(outer: Rect, inner: Rect) -> Bool:
  Rect{left, top, right, bottom} = outer
  Rect{+inner_left, +inner_top, +inner_right, +inner_bottom} = inner
  F32.is_le(left, inner_left) && F32.is_le(top, inner_top) &&
    F32.is_le(inner_right, right) && F32.is_le(inner_bottom, bottom) &&
    F32.is_lt(inner_left, inner_right) && F32.is_lt(inner_top, inner_bottom)

def actionable(viewport: Rect, target: Target) -> Bool:
  Target{visible, enabled, keyboard, pointer, bounds} = target
  visible && enabled && keyboard && pointer && contains(viewport, bounds)

def action_realized(required: Bool, viewport: Rect, +target: Target) -> Bool:
  match required:
    case True{}: actionable(viewport, target)
    case False{}:
      Target{visible, enabled, keyboard, pointer, bounds} = target
      Bool.not(enabled)

def anchor_realized(expected: Anchor, observed: Anchor, +tolerance: F32) -> Bool:
  Anchor{identity, +offset} = expected
  Anchor{observed_identity, +observed_offset} = observed
  String.eq(identity, observed_identity) &&
    F32.is_le(offset, F32.add(observed_offset, tolerance)) &&
    F32.is_le(observed_offset, F32.add(offset, tolerance))

def focus_realized(focus: Focus, observed_owner: String, visible: Bool) -> Bool:
  visible && String.eq(focus_owner(focus), observed_owner)
