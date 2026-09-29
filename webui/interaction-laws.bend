import Base
import ./interaction.bend as UI

# These obligations fix effects as well as post-state. Keeping state unchanged
# while emitting AlignLatest would violate history preservation.
type Guarantees is Type:
  Guarantees{
    following_layout:
      {UI.reading_step(UI.LayoutChanged{}, UI.FollowingLatest{}) ==
        UI.ReadingDecision{UI.FollowingLatest{}, UI.AlignLatest{}, UI.KeepWindow{}} : UI.ReadingDecision},
    history: @+anchor:UI.Anchor ->
      {UI.reading_step(UI.LayoutChanged{}, UI.ReadingHistory{anchor}) ==
        UI.ReadingDecision{UI.ReadingHistory{anchor}, UI.PreserveAnchor{anchor}, UI.KeepWindow{}} : UI.ReadingDecision},
    latest: @reading:UI.Reading ->
      {UI.reading_step(UI.FollowLatest{}, reading) ==
        UI.ReadingDecision{UI.FollowingLatest{}, UI.AlignLatest{}, UI.LatestWindow{}} : UI.ReadingDecision},
    pin_history: @+anchor:UI.Anchor ->
      {UI.reading_step(UI.ReadHistory{anchor}, UI.FollowingLatest{}) ==
        UI.ReadingDecision{UI.ReadingHistory{anchor}, UI.LeaveViewport{}, UI.PinWindow{}} : UI.ReadingDecision},
    continue_history: @+anchor:UI.Anchor -> @old:UI.Anchor ->
      {UI.reading_step(UI.ReadHistory{anchor}, UI.ReadingHistory{old}) ==
        UI.ReadingDecision{UI.ReadingHistory{anchor}, UI.LeaveViewport{}, UI.KeepWindow{}} : UI.ReadingDecision},
    restore_history: @anchor:UI.Anchor ->
      {UI.restore_window(UI.ReadingHistory{anchor}) == UI.PinWindow{} : UI.WindowEffect},
    restore_latest:
      {UI.restore_window(UI.FollowingLatest{}) == UI.KeepWindow{} : UI.WindowEffect},
    reading_owner: @+requested:String -> @+current:String ->
      {UI.owns_reading(requested, current) == String.eq(requested, current) : Bool},
    editing: @+owner:String -> @old:String -> @+text:String -> @+revision:Nat ->
      {UI.edit_draft(text, UI.Draft{owner, old, revision}) == UI.Draft{owner, text, 1n+revision} : UI.Draft},
    matching: @+owner:String -> @text:String -> @+revision:Nat -> @+current_owner:String -> @current_text:String -> @+current_revision:Nat ->
      {UI.draft_matches(UI.Draft{owner, text, revision}, UI.Draft{current_owner, current_text, current_revision}) ==
        (String.eq(owner, current_owner) && Nat.is_eq(revision, current_revision)) : Bool},
    rejected_draft: @retained:Bool -> @submitted:UI.Draft -> @+current:UI.Draft ->
      {UI.acknowledge_draft(False{}, retained, submitted, current) == current : UI.Draft},
    retained_draft: @submitted:UI.Draft -> @+current:UI.Draft ->
      {UI.acknowledge_draft(True{}, True{}, submitted, current) == current : UI.Draft},
    stale_draft: @+submitted:UI.Draft -> @+current:UI.Draft ->
      @different:{UI.draft_matches(submitted, current) == False{} : Bool} ->
      {UI.acknowledge_draft(True{}, False{}, submitted, current) == current : UI.Draft},
    accepted_draft: @+submitted:UI.Draft -> @+owner:String -> @text:String -> @+revision:Nat ->
      @same:{UI.draft_matches(submitted, UI.Draft{owner, text, revision}) == True{} : Bool} ->
      {UI.acknowledge_draft(True{}, False{}, submitted, UI.Draft{owner, text, revision}) ==
        UI.Draft{owner, "", 1n+revision} : UI.Draft},
    intent: @+draft:UI.Draft -> @+selection:UI.Selection -> @old:String -> @+intent:String ->
      {UI.select_intent(intent, UI.Editor{draft, selection, old}) == UI.Editor{draft, selection, intent} : UI.Editor},
    composition: @enter:Bool -> @multiline:Bool -> @modified:Bool -> @shift:Bool -> @alt:Bool -> @enabled:Bool -> @pending:Bool ->
      {UI.submit_key(True{}, enter, multiline, modified, shift, alt, enabled, pending) == False{} : Bool},
    submission: @+composing:Bool -> @+enter:Bool -> @+multiline:Bool -> @+modified:Bool -> @+shift:Bool -> @+alt:Bool -> @+enabled:Bool -> @+pending:Bool ->
      {UI.submit_key(composing, enter, multiline, modified, shift, alt, enabled, pending) ==
        (Bool.not(composing) && enter && Bool.not(shift) && Bool.not(alt) && (multiline || modified) && enabled && Bool.not(pending)) : Bool},
    enter_focus: @+identity:String -> @trigger:String -> @+target:String -> @+scopes:+List<UI.Scope> ->
      {UI.enter_scope(UI.Scope{identity, trigger, target}, UI.Focus{scopes}) ==
        UI.FocusDecision{UI.Focus{UI.Scope{identity, trigger, target} <> scopes}, target} : UI.FocusDecision},
    leave_focus: @identity:String -> @+trigger:String -> @target:String -> @+rest:+List<UI.Scope> ->
      {UI.leave_top(True{}, UI.Scope{identity, trigger, target}, rest) ==
        UI.FocusDecision{UI.Focus{rest}, trigger} : UI.FocusDecision},
    nested_focus: @+scope:UI.Scope -> @+rest:+List<UI.Scope> ->
      {UI.leave_top(False{}, scope, rest) == UI.FocusDecision{UI.Focus{scope <> rest}, ""} : UI.FocusDecision},
    focus_owner: @+identity:String -> @+key:String -> @+trigger:String -> @+target:String -> @+rest:+List<UI.Scope> ->
      {UI.leave_scope(identity, UI.Focus{UI.Scope{key, trigger, target} <> rest}) ==
        UI.leave_top(String.eq(identity, key), UI.Scope{key, trigger, target}, rest) : UI.FocusDecision},
    focus_restoration: @+closing:String -> @+parent:String -> @+current:String -> @+still_owned:Bool ->
      {UI.restore_focus(closing, parent, current, still_owned) ==
        ((String.eq(current, closing) || String.eq(current, parent)) && still_owned) : Bool},
    submit_focus: @+accepted:Bool -> @+still_owned:Bool ->
      {UI.submission_focus(accepted, still_owned) == (accepted && still_owned) : Bool},
    geometry: @+left:F32 -> @+top:F32 -> @+right:F32 -> @+bottom:F32 -> @+inner_left:F32 -> @+inner_top:F32 -> @+inner_right:F32 -> @+inner_bottom:F32 ->
      {UI.contains(UI.Rect{left, top, right, bottom}, UI.Rect{inner_left, inner_top, inner_right, inner_bottom}) ==
        (F32.is_le(left, inner_left) && F32.is_le(top, inner_top) && F32.is_le(inner_right, right) && F32.is_le(inner_bottom, bottom) &&
          F32.is_lt(inner_left, inner_right) && F32.is_lt(inner_top, inner_bottom)) : Bool},
    action: @+viewport:UI.Rect -> @+visible:Bool -> @+enabled:Bool -> @+keyboard:Bool -> @+pointer:Bool -> @+bounds:UI.Rect ->
      {UI.action_realized(True{}, viewport, UI.Target{visible, enabled, keyboard, pointer, bounds}) ==
        (visible && enabled && keyboard && pointer && UI.contains(viewport, bounds)) : Bool},
    hidden_action: @viewport:UI.Rect -> @enabled:Bool -> @keyboard:Bool -> @pointer:Bool -> @bounds:UI.Rect ->
      {UI.action_realized(True{}, viewport, UI.Target{False{}, enabled, keyboard, pointer, bounds}) == False{} : Bool},
    code_wrap: @+wrap:Bool -> @+copy:UI.CopyState ->
      {UI.toggle_code_wrap(UI.CodeView{wrap, copy}) == UI.CodeView{Bool.not(wrap), copy} : UI.CodeView},
    copy_pending: @+wrap:Bool -> @copy:UI.CopyState ->
      {UI.begin_code_copy(UI.CodeView{wrap, copy}) == UI.CodeView{wrap, UI.CopyPending{}} : UI.CodeView},
    copy_success: @+wrap:Bool -> @copy:UI.CopyState ->
      {UI.finish_code_copy(True{}, UI.CodeView{wrap, copy}) == UI.CodeView{wrap, UI.CopySucceeded{}} : UI.CodeView},
    copy_failure: @+wrap:Bool -> @copy:UI.CopyState ->
      {UI.finish_code_copy(False{}, UI.CodeView{wrap, copy}) == UI.CodeView{wrap, UI.CopyFailed{}} : UI.CodeView},
    pending_copy_disabled: @wrap:Bool ->
      {UI.code_can_copy(UI.CodeView{wrap, UI.CopyPending{}}) == False{} : Bool},
    old_feedback: @+wrap:Bool ->
      {UI.expire_code_feedback(UI.CodeView{wrap, UI.CopyPending{}}) == UI.CodeView{wrap, UI.CopyPending{}} : UI.CodeView}}

law guarantees:
  Guarantees
