import Base
import ../interaction.bend as UI
import ../interaction-laws.bend as Laws

def stale(+submitted: UI.Draft, +current: UI.Draft,
  different: {UI.draft_matches(submitted, current) == False{} : Bool}) ->
  {UI.acknowledge_draft(True{}, False{}, submitted, current) == current : UI.Draft}:
  Equal.cong(Bool, UI.Draft, (clear => UI.clear_draft(clear, current)),
    UI.draft_matches(submitted, current), False{}, different)

def accepted(+submitted: UI.Draft, +owner: String, text: String, +revision: Nat,
  same: {UI.draft_matches(submitted, UI.Draft{owner, text, revision}) == True{} : Bool}) ->
  {UI.acknowledge_draft(True{}, False{}, submitted, UI.Draft{owner, text, revision}) ==
    UI.Draft{owner, "", 1n+revision} : UI.Draft}:
  Equal.cong(Bool, UI.Draft, (clear => UI.clear_draft(clear, UI.Draft{owner, text, revision})),
    UI.draft_matches(submitted, UI.Draft{owner, text, revision}), True{}, same)

def nested(+scope: UI.Scope, +rest: +List<UI.Scope>) ->
  {UI.leave_top(False{}, scope, rest) == UI.FocusDecision{UI.Focus{scope <> rest}, ""} : UI.FocusDecision}:
  UI.Scope{identity, trigger, target} = scope
  {==}

def Laws.guarantees():
  Laws.Guarantees{
    {==},
    (anchor => {==}),
    (reading => {==}),
    (anchor => {==}),
    (anchor => old => {==}),
    (anchor => {==}),
    {==},
    (requested => current => {==}),
    (owner => old => text => revision => {==}),
    (owner => text => revision => current_owner => current_text => current_revision => {==}),
    (retained => submitted => current => {==}),
    (submitted => current => {==}),
    (submitted => current => different => stale(submitted, current, different)),
    (submitted => owner => text => revision => same => accepted(submitted, owner, text, revision, same)),
    (draft => selection => old => intent => {==}),
    (enter => multiline => modified => shift => alt => enabled => pending => {==}),
    (composing => enter => multiline => modified => shift => alt => enabled => pending => {==}),
    (identity => trigger => target => scopes => {==}),
    (identity => trigger => target => rest => {==}),
    (scope => rest => nested(scope, rest)),
    (identity => key => trigger => target => rest => {==}),
    (closing => parent => current => still_owned => {==}),
    (accepted => still_owned => {==}),
    (left => top => right => bottom => inner_left => inner_top => inner_right => inner_bottom => {==}),
    (viewport => visible => enabled => keyboard => pointer => bounds => {==}),
    (viewport => enabled => keyboard => pointer => bounds => {==}),
    (wrap => copy => {==}),
    (wrap => copy => {==}),
    (wrap => copy => {==}),
    (wrap => copy => {==}),
    (wrap => {==}),
    (wrap => {==})}
