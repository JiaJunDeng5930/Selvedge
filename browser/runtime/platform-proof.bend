import ../editor/skill-mention.bend as Mention
import Base
import ./CONTRACT.bend as Rule
import ./PLATFORM.bend as Model
import ../focus/MODEL.bend as Focus
import ../focus/CONTRACT.bend as FocusRules
import ../focus/PROOF.bend as FocusEvidence
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../editor/MODEL.bend as Editor
import ../controls/GEOMETRY.bend as Physical
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/interactive_markdown/TYPES.bend as IM

def Rule.editing_retains_selection(revision, body, directory_entry, editor):
  {==}

# Capacity reconciliation uses the committed post-state without replaying its effects.

def Rule.merge_reflow_product(product, effects, refreshed):
  match refreshed:
    case Model.Decision{ignored, platform, reconciliation}: {==}

def Rule.changed_capacity_product(decision, capacity):
  Model.Decision{InteractionTypes.Decision{+state, reply, runtime, interaction, services, durable}, Model.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects} = decision
  Rule.merge_reflow_product(InteractionTypes.Decision{state, reply, runtime, interaction, services, durable}, effects, Model.after_core(Model.unchanged(state),
    Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}))

def Rule.retained_capacity_product(same, decision, capacity):
  match same:
    case True{}: {==}
    case False{}: Rule.changed_capacity_product(decision, capacity)

def Rule.reflow_preserves_product(decision, capacity):
  Model.Decision{+product, Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +old_capacity, +scope}, +effects} = decision
  Rule.retained_capacity_product(Model.same_capacity(old_capacity, capacity),
    Model.Decision{product, Model.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects}, capacity)

def Rule.realized_preserves_product(decision):
  Model.Decision{InteractionTypes.Decision{core, reply, runtime, interaction, services, durable},
    Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}, effects} = decision
  {==}

def Rule.realized_empty(product, platform):
  InteractionTypes.Decision{core, reply, runtime, interaction, services, durable} = product
  Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  {==}

def realized_focus(+found: Maybe<&2, String>, +ticket: Nat, +rest: +List<Model.Effect>) ->
  {Model.realized_product_focus(found, ticket, rest) == List.append(&2, Model.Effect, Rule.expected_focus(found, ticket), rest) : +List<Model.Effect>}:
  match found:
    case None{}: {==}
    case Some{key}: {==}

def effects_realized(+surface: SurfaceTypes.Surface, source: +List<Model.Effect>) ->
  {Model.realized_effects(surface, source) == Rule.expected_effects(surface, source) : +List<Model.Effect>}:
  match source:
    case Nil{}: {==}
    case Con{Model.Focus{+ticket, Focus.Product{+requested}}, +rest}:
      Equal.trans(+List<Model.Effect>,
        Model.realized_product_focus(InterfaceView.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, requested), ticket), Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, requested), ticket), Rule.expected_effects(surface, rest)),
        realized_focus(InterfaceView.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest)),
        Equal.cong(+List<Model.Effect>, +List<Model.Effect>,
          (remaining => List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, requested), ticket), remaining)),
          Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest)))
    case Con{Model.ScopeFocus{+ticket, +previous, +current}, +rest}:
      Equal.trans(+List<Model.Effect>,
        Model.realized_product_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), Rule.expected_effects(surface, rest)),
        realized_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest)),
        Equal.cong(+List<Model.Effect>, +List<Model.Effect>,
          (remaining => List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), remaining)),
          Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest)))
    case Con{Model.Focus{+ticket, Focus.Content{+owner, +identity}}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.Focus{ticket, Focus.Content{owner, identity}} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))
    case Con{Model.ApplyReading{+task, +generation, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.ApplyReading{task, generation, effect} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))
    case Con{Model.Clipboard{+block, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.Clipboard{block, effect} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))
    case Con{Model.ObserveSkillCatalog{+key, +ticket, +workspace_key, +workspace}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.ObserveSkillCatalog{key, ticket, workspace_key, workspace} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))
    case Con{Model.SetEditorSelection{+key, +selection}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.SetEditorSelection{key, selection} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))

def deferred_realization(+source: +List<Model.Effect>, +surface: SurfaceTypes.Surface) ->
  {Model.deferred_realized_effects(source, (_ => surface)) == Rule.expected_effects(surface, source) : +List<Model.Effect>}:
  match source:
    case Nil{}: {==}
    case Con{Model.Focus{ticket, Focus.Product{requested}}, rest}:
      effects_realized(surface, Model.Focus{ticket, Focus.Product{requested}} <> rest)
    case Con{Model.ScopeFocus{ticket, previous, current}, rest}:
      effects_realized(surface, Model.ScopeFocus{ticket, previous, current} <> rest)
    case Con{Model.Focus{+ticket, Focus.Content{+owner, +identity}}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.Focus{ticket, Focus.Content{owner, identity}} <> tail),
        Model.deferred_realized_effects(rest, (_ => surface)), Rule.expected_effects(surface, rest), deferred_realization(rest, surface))
    case Con{Model.ApplyReading{+task, +generation, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.ApplyReading{task, generation, effect} <> tail),
        Model.deferred_realized_effects(rest, (_ => surface)), Rule.expected_effects(surface, rest), deferred_realization(rest, surface))
    case Con{Model.Clipboard{+block, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.Clipboard{block, effect} <> tail),
        Model.deferred_realized_effects(rest, (_ => surface)), Rule.expected_effects(surface, rest), deferred_realization(rest, surface))
    case Con{Model.ObserveSkillCatalog{+key, +ticket, +workspace_key, +workspace}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.ObserveSkillCatalog{key, ticket, workspace_key, workspace} <> tail),
        Model.deferred_realized_effects(rest, (_ => surface)), Rule.expected_effects(surface, rest), deferred_realization(rest, surface))
    case Con{Model.SetEditorSelection{+key, +selection}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.SetEditorSelection{key, selection} <> tail),
        Model.deferred_realized_effects(rest, (_ => surface)), Rule.expected_effects(surface, rest), deferred_realization(rest, surface))

def actual_decision_effects(decision: Model.Decision) ->
  {Rule.effects(Model.realized_decision(decision)) == Rule.expected_effects(Rule.decision_surface(decision), Rule.effects(decision)) : +List<Model.Effect>}:
  Model.Decision{InteractionTypes.Decision{+core, reply, runtime, interaction, services, durable},
    Model.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}, effects} = decision
  deferred_realization(effects, InterfaceView.observe(capacity, core))

def Rule.step_realizes_effects(input, state):
  actual_decision_effects(Model.step_raw(input, state))

def realized_focus_external(found: Maybe<&2, String>, ticket: Nat, +rest: +List<Model.Effect>,
  external: {Rule.external_effects(rest) == True{} : Bool}) ->
  {Rule.external_effects(Model.realized_product_focus(found, ticket, rest)) == True{} : Bool}:
  match found:
    case None{}: external
    case Some{key}: external

def Rule.realized_effects_are_external(surface, source):
  match source:
    case Nil{}: {==}
    case Con{Model.Focus{ticket, Focus.Product{requested}}, +rest}:
      realized_focus_external(InterfaceView.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest),
        Rule.realized_effects_are_external(surface, rest))
    case Con{Model.ScopeFocus{ticket, previous, current}, +rest}:
      realized_focus_external(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest),
        Rule.realized_effects_are_external(surface, rest))
    case Con{Model.Focus{ticket, Focus.Content{owner, identity}}, rest}: Rule.realized_effects_are_external(surface, rest)
    case Con{Model.ApplyReading{task, generation, effect}, rest}: Rule.realized_effects_are_external(surface, rest)
    case Con{Model.Clipboard{block, effect}, rest}: Rule.realized_effects_are_external(surface, rest)
    case Con{Model.ObserveSkillCatalog{key, ticket, workspace_key, workspace}, rest}: Rule.realized_effects_are_external(surface, rest)
    case Con{Model.SetEditorSelection{key, selection}, rest}: Rule.realized_effects_are_external(surface, rest)

def realized_decision_external(decision: Model.Decision) ->
  {Rule.external_effects(Rule.effects(Model.realized_decision(decision))) == True{} : Bool}:
  Model.Decision{InteractionTypes.Decision{+core, reply, runtime, interaction, services, durable},
    Model.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}, +effects} = decision
  Equal.trans(Bool,
    Rule.external_effects(Model.deferred_realized_effects(effects, (_ => InterfaceView.observe(capacity, core)))),
    Rule.external_effects(Model.realized_effects(InterfaceView.observe(capacity, core), effects)), True{},
    Equal.cong(+List<Model.Effect>, Bool, Rule.external_effects,
      Model.deferred_realized_effects(effects, (_ => InterfaceView.observe(capacity, core))),
      Model.realized_effects(InterfaceView.observe(capacity, core), effects),
      Equal.trans(+List<Model.Effect>, Model.deferred_realized_effects(effects, (_ => InterfaceView.observe(capacity, core))),
        Rule.expected_effects(InterfaceView.observe(capacity, core), effects),
        Model.realized_effects(InterfaceView.observe(capacity, core), effects),
        deferred_realization(effects, InterfaceView.observe(capacity, core)),
        Equal.sym(+List<Model.Effect>, Model.realized_effects(InterfaceView.observe(capacity, core), effects),
          Rule.expected_effects(InterfaceView.observe(capacity, core), effects), effects_realized(InterfaceView.observe(capacity, core), effects)))),
    Rule.realized_effects_are_external(InterfaceView.observe(capacity, core), effects))

def Rule.actual_step_effects_are_external(input, state):
  realized_decision_external(Model.step_raw(input, state))

def and_right_false(value: Bool) -> {value && False{} == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def and_left_false(value: Bool) -> {False{} && value == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def and_left_true(value: Bool) -> {True{} && value == value : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def Rule.failed_focus_receipt(model_state, received, target, observed, failed):
  Model.State{+core, +platform} = model_state
  InteractionTypes.State{+application, +services} = core
  Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope} = platform
  +accepted = Nat.is_eq(received, ticket) && Model.active_target(InteractionTypes.State{application, services}, capacity, target)
  Equal.trans(Model.Decision,
    Model.step(Model.FocusApplied{received, target, observed}, Model.State{core, platform}),
    Model.realized_decision(Model.Decision{Model.unchanged(core), platform, Nil{}}),
    Model.Decision{Model.unchanged(core), platform, Nil{}},
    Equal.cong(Bool, Model.Decision,
      (confirmed => Model.realized_decision(Model.focus_result(confirmed, target, core, platform))),
      accepted && Model.focus_confirmed(target, observed), False{},
      Equal.trans(Bool, accepted && Model.focus_confirmed(target, observed), accepted && False{}, False{},
        Equal.cong(Bool, Bool, (confirmed => accepted && confirmed), Model.focus_confirmed(target, observed), False{}, failed),
        and_right_false(accepted))), Rule.realized_empty(Model.unchanged(core), platform))

def publication_raw_empty(+core: InteractionTypes.State, +platform: Model.Platform, received: Nat, +target: Focus.Target,
  inactive: {Nat.is_eq(received, Rule.ticket(platform)) && Model.active_target(core, Rule.capacity(platform), target) == False{} : Bool}) ->
  {Model.step(Model.PublicationFocusObserved{received, Some{target}, None{}}, Model.State{core, platform}) == Model.Decision{Model.unchanged(core), platform, Nil{}} : Model.Decision}:
  InteractionTypes.State{+application, +services} = core
  Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope} = platform
  Equal.trans(Model.Decision,
    Model.step(Model.PublicationFocusObserved{received, Some{target}, None{}}, Model.State{core, platform}),
    Model.realized_decision(Model.Decision{Model.unchanged(core), platform, Nil{}}),
    Model.Decision{Model.unchanged(core), platform, Nil{}},
    Equal.cong(Bool, Model.Decision,
      (owned => Model.realized_decision(Model.publication_focus_result(owned, ticket, target, core, platform))),
      Nat.is_eq(received, ticket) && Model.active_target(core, capacity, target), False{}, inactive),
    Rule.realized_empty(Model.unchanged(core), platform))

def Rule.publication_focus_after_some(model_state, received, before, after):
  Model.State{+core, +platform} = model_state
  match core:
    case InteractionTypes.State{application, services}:
      match platform:
        case Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          match before:
            case None{}: Rule.realized_empty(Model.unchanged(core), platform)
            case Some{target}: Rule.realized_empty(Model.unchanged(core), platform)

def Rule.publication_focus_before_none(model_state, received, after):
  Model.State{+core, +platform} = model_state
  match core:
    case InteractionTypes.State{application, services}:
      match platform:
        case Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          match after:
            case None{}: Rule.realized_empty(Model.unchanged(core), platform)
            case Some{target}: Rule.realized_empty(Model.unchanged(core), platform)

def Rule.publication_focus_stale(model_state, received, before, after, stale):
  Model.State{+core, +platform} = model_state
  match before after:
    case Some{+target} None{}:
      publication_raw_empty(core, platform, received, target,
        Equal.trans(Bool,
          Nat.is_eq(received, Rule.ticket(platform)) && Model.active_target(core, Rule.capacity(platform), target),
          False{} && Model.active_target(core, Rule.capacity(platform), target), False{},
          Equal.cong(Bool, Bool, (current => current && Model.active_target(core, Rule.capacity(platform), target)),
            Nat.is_eq(received, Rule.ticket(platform)), False{}, stale),
          and_left_false(Model.active_target(core, Rule.capacity(platform), target))))
    case None{} after: Rule.publication_focus_before_none(Model.State{core, platform}, received, after)
    case Some{target} Some{after}: Rule.publication_focus_after_some(Model.State{core, platform}, received, Some{target}, after)

def Rule.publication_focus_inactive(model_state, received, target, inactive):
  Model.State{+core, +platform} = model_state
  publication_raw_empty(core, platform, received, target,
    Equal.trans(Bool,
      Nat.is_eq(received, Rule.ticket(platform)) && Model.active_target(core, Rule.capacity(platform), target),
      Nat.is_eq(received, Rule.ticket(platform)) && False{}, False{},
      Equal.cong(Bool, Bool, (active => Nat.is_eq(received, Rule.ticket(platform)) && active),
        Model.active_target(core, Rule.capacity(platform), target), False{}, inactive),
      and_right_false(Nat.is_eq(received, Rule.ticket(platform)))))

def realized_loss_focus(found: Maybe<&2, String>, ticket: Nat) ->
  {Model.realized_product_focus(found, ticket, Nil{}) == Rule.expected_focus(found, ticket) : +List<Model.Effect>}:
  match found:
    case None{}: {==}
    case Some{key}: {==}

def realized_loss(+core: InteractionTypes.State, +platform: Model.Platform, target: Focus.Target) ->
  {Model.realized_decision(Model.Decision{Model.unchanged(core), platform, [Model.Focus{Rule.ticket(platform), target}]}) == Model.Decision{Model.unchanged(core), platform, Rule.loss_effects(core, platform, target)} : Model.Decision}:
  InteractionTypes.State{+application, +services} = core
  Model.Platform{readers, editors, focused, +ticket, reduced, +capacity, scope} = platform
  match target:
    case Focus.Product{identity}:
      Equal.cong(+List<Model.Effect>, Model.Decision,
        (effects => Model.Decision{Model.unchanged(core), platform, effects}),
        Model.realized_product_focus(InterfaceView.focus_target(InterfaceView.observe(capacity, core), identity), ticket, Nil{}),
        Rule.expected_focus(InterfaceView.focus_target(InterfaceView.observe(capacity, core), identity), ticket),
        realized_loss_focus(InterfaceView.focus_target(InterfaceView.observe(capacity, core), identity), ticket))
    case Focus.Content{owner, identity}: {==}

def Rule.publication_focus_loss(model_state, received, target, current, active):
  Model.State{+core, +platform} = model_state
  InteractionTypes.State{+application, +services} = core
  Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope} = platform
  Equal.trans(Model.Decision,
    Model.step(Model.PublicationFocusObserved{received, Some{target}, None{}}, Model.State{core, platform}),
    Model.realized_decision(Model.Decision{Model.unchanged(core), platform, [Model.Focus{ticket, target}]}),
    Model.Decision{Model.unchanged(core), platform, Rule.loss_effects(core, platform, target)},
    Equal.cong(Bool, Model.Decision,
      (owned => Model.realized_decision(Model.publication_focus_result(owned, ticket, target, core, platform))),
      Nat.is_eq(received, ticket) && Model.active_target(core, capacity, target), True{},
      Equal.trans(Bool,
        Nat.is_eq(received, ticket) && Model.active_target(core, capacity, target),
        True{} && Model.active_target(core, capacity, target), True{},
        Equal.cong(Bool, Bool, (valid => valid && Model.active_target(core, capacity, target)), Nat.is_eq(received, ticket), True{}, current),
        Equal.trans(Bool, True{} && Model.active_target(core, capacity, target), Model.active_target(core, capacity, target), True{},
          and_left_true(Model.active_target(core, capacity, target)), active))),
    realized_loss(core, platform, target))


def Rule.realized_decision_exact(decision):
  Model.Decision{+product, +platform, +source} = decision
  InteractionTypes.Decision{+core, +reply, +runtime, +interaction, +services, +durable} = product
  Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope} = platform
  Equal.cong(+List<Model.Effect>, Model.Decision,
    (result => Model.Decision{InteractionTypes.Decision{core, reply, runtime, interaction, services, durable},
      Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}, result}),
    Model.deferred_realized_effects(source, (_ => InterfaceView.observe(capacity, core))),
    Rule.expected_effects(InterfaceView.observe(capacity, core), source),
    deferred_realization(source, InterfaceView.observe(capacity, core)))

def submission_clear_policy(body: U.Body) ->
  {Model.empty_message(body) == Rule.required_submission_clear(body) : Bool}:
  match body:
    case U.NewTask{U.Text{text}, profile, reasoning, context, create_worktree, work}: {==}
    case U.WorkName{work, name}: {==}
    case U.TitlePrompts{revision, prompts}: {==}
    case U.Message{task, U.Text{text}, delivery}: {==}
    case U.Project{project, name, workspace, create_worktree}: {==}
    case U.Card{card, revision, value, assist, profile, keep_open}: {==}
    case U.Agent{agent, revision, name, profile, reasoning, instructions, context, concurrency}: {==}
    case U.Fork{task, count, messages, context}: {==}
    case U.Compact{task, summary}: {==}
    case U.TaskGraph{graph, declaration, parsed, work}: {==}

def clear_selection_policy(clear: Bool, +owner: U.Editor, +selection: Physical.Selection, +composing: Bool, +mentions: Mention.State) ->
  {Model.clear_selection(clear, Editor.Editor{owner, selection, composing, mentions}) ==
    Bool.pick(Editor.Editor, clear, Editor.Editor{owner, Physical.Selection{0n, 0n, "none"}, False{}, Mention.clear(mentions)}, Editor.Editor{owner, selection, composing, mentions}) : Editor.Editor}:
  match clear:
    case False{}: {==}
    case True{}: {==}

def editor_commit_policy(found: Maybe<&2, U.Draft>, editor: Editor.Editor) ->
  {Model.synchronize_editor(found, editor) == Rule.required_editor_reconciliation(found, editor) : Editor.Editor}:
  match found editor:
    case None{} retained: {==}
    case Some{U.Draft{revision, body, U.Editing{}, directory}} retained: {==}
    case Some{U.Draft{revision, body, U.Rejected{submitted, reason}, directory}} retained: {==}
    case Some{U.Draft{revision, body, U.WorkspaceRejected{submitted, reason}, directory}} retained: {==}
    case Some{U.Draft{revision, +body, U.Accepted{submitted, result}, directory}} Editor.Editor{+owner, +selection, +composing, +mentions}:
      Equal.trans(Editor.Editor,
        Model.clear_selection(Model.empty_message(body), Editor.Editor{owner, selection, composing, mentions}),
        Bool.pick(Editor.Editor, Model.empty_message(body), Editor.Editor{owner, Physical.Selection{0n, 0n, "none"}, False{}, Mention.clear(mentions)}, Editor.Editor{owner, selection, composing, mentions}),
        Bool.pick(Editor.Editor, Rule.required_submission_clear(body), Editor.Editor{owner, Physical.Selection{0n, 0n, "none"}, False{}, Mention.clear(mentions)}, Editor.Editor{owner, selection, composing, mentions}),
        clear_selection_policy(Model.empty_message(body), owner, selection, composing, mentions),
        Equal.cong(Bool, Editor.Editor,
          (clear => Bool.pick(Editor.Editor, clear, Editor.Editor{owner, Physical.Selection{0n, 0n, "none"}, False{}, Mention.clear(mentions)}, Editor.Editor{owner, selection, composing, mentions})),
          Model.empty_message(body), Rule.required_submission_clear(body), submission_clear_policy(body)))

def editor_list_policy(editors: +List<Editor.Editor>, +drafts: +List<U.Draft>) ->
  {Model.synchronize_drafts(drafts, editors) == Rule.required_editors(editors, drafts) : +List<Editor.Editor>}:
  match editors:
    case Nil{}: {==}
    case Con{Editor.Editor{+owner, +selection, +composing, +mentions}, +rest}:
      +current: Editor.Editor = Editor.Editor{owner, selection, composing, mentions}
      +actual: Editor.Editor = Model.synchronize_editor(E.find_draft(drafts, owner), current)
      +required: Editor.Editor = Rule.required_editor_reconciliation(E.find_draft(drafts, owner), current)
      Equal.trans(+List<Editor.Editor>, actual <> Model.synchronize_drafts(drafts, rest), required <> Model.synchronize_drafts(drafts, rest), required <> Rule.required_editors(rest, drafts),
        Equal.cong(Editor.Editor, +List<Editor.Editor>, (head => head <> Model.synchronize_drafts(drafts, rest)), actual, required, editor_commit_policy(E.find_draft(drafts, owner), current)),
        Equal.cong(+List<Editor.Editor>, +List<Editor.Editor>, (tail => required <> tail), Model.synchronize_drafts(drafts, rest), Rule.required_editors(rest, drafts), editor_list_policy(rest, drafts)))

def Rule.after_core_complete(decision, platform):
  InteractionTypes.Decision{InteractionTypes.State{+application, +services_state}, +reply, +runtime, +interaction, +services, +durable} = decision
  Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +previous} = platform
  +core: InteractionTypes.State = InteractionTypes.State{application, services_state}
  +surface: SurfaceTypes.Surface = InterfaceView.observe(capacity, core)
  +current: Focus.Scope = Focus.current(core, capacity)
  +transition: Bool = Model.focus_transition_on(previous, current, focused, surface)
  +required_transition: Bool = FocusRules.required_transition(previous, current, focused, FocusRules.required_target_eligible(surface, focused))
  +actual_ticket: Nat = Model.focus_revision(transition, interaction, ticket)
  +required_ticket: Nat = FocusRules.required_focus_ticket(required_transition, interaction, ticket)
  +actual_editors: +List<Editor.Editor> = Model.synchronize_editors(editors, application)
  +required_editors: +List<Editor.Editor> = Rule.required_editors(editors, E.drafts(E.session(application)))
  +required_effects: +List<Model.Effect> = FocusRules.expected_effects(decision, platform, current)
  Equal.trans(Model.Decision, Model.after_core(decision, platform),
    Model.Decision{decision, Model.Platform{readers, actual_editors, focused, actual_ticket, reduced, capacity, current}, required_effects}, Rule.required_platform_commit(decision, platform),
    Equal.cong(+List<Model.Effect>, Model.Decision,
      (effects => Model.Decision{decision, Model.Platform{readers, actual_editors, focused, actual_ticket, reduced, capacity, current}, effects}),
      FocusRules.effects(Model.after_core_scoped(decision, platform, current)), required_effects, FocusEvidence.after_core_effects(decision, platform, current)),
    Equal.trans(Model.Decision,
      Model.Decision{decision, Model.Platform{readers, actual_editors, focused, actual_ticket, reduced, capacity, current}, required_effects},
      Model.Decision{decision, Model.Platform{readers, required_editors, focused, actual_ticket, reduced, capacity, current}, required_effects}, Rule.required_platform_commit(decision, platform),
      Equal.cong(+List<Editor.Editor>, Model.Decision,
        (next => Model.Decision{decision, Model.Platform{readers, next, focused, actual_ticket, reduced, capacity, current}, required_effects}),
        actual_editors, required_editors, editor_list_policy(editors, E.drafts(E.session(application)))),
      Equal.cong(Nat, Model.Decision,
        (next => Model.Decision{decision, Model.Platform{readers, required_editors, focused, next, reduced, capacity, current}, required_effects}),
        actual_ticket, required_ticket,
        Equal.trans(Nat, actual_ticket, FocusRules.required_focus_ticket(transition, interaction, ticket), required_ticket,
          FocusEvidence.ticket_policy(transition, interaction, ticket),
          Equal.cong(Bool, Nat, (next => FocusRules.required_focus_ticket(next, interaction, ticket)),
            transition, required_transition, FocusEvidence.transition_on_policy(previous, current, focused, surface))))))

def Rule.content_owner_classification(found): FocusEvidence.content_owner_policy(found)

def content_owner_from_lookup(+core: InteractionTypes.State, +platform: Model.Platform, +owner: String, +node: SurfaceTypes.Node,
  found: {InterfaceView.find_node(InterfaceView.active_nodes(InterfaceView.observe(Model.capacity(platform), core)), owner) ==
    Some{node} : Maybe<&2, SurfaceTypes.Node>},
  eligible: {FocusRules.required_content_owner(Some{node}) == True{} : Bool}) ->
  {Model.active_content_owner(core, Model.capacity(platform), owner) == True{} : Bool}:
  Equal.trans(Bool,
    Model.active_content_owner(core, Model.capacity(platform), owner), Model.found_content_owner(Some{node}), True{},
    Equal.cong(Maybe<&2, SurfaceTypes.Node>, Bool, Model.found_content_owner,
      InterfaceView.find_node(InterfaceView.active_nodes(InterfaceView.observe(Model.capacity(platform), core)), owner),
      Some{node}, found),
    Equal.trans(Bool, Model.found_content_owner(Some{node}), FocusRules.required_content_owner(Some{node}), True{},
      Rule.content_owner_classification(Some{node}), eligible))

def observed_content_focus_owned(+core: InteractionTypes.State, +platform: Model.Platform, +owner: String, +identity: String,
  active: {Model.active_content_owner(core, Model.capacity(platform), owner) == True{} : Bool}) ->
  {Model.step(Model.ContentFocusObserved{owner, identity}, Model.State{core, platform}) ==
    Rule.required_content_focus_observation(core, platform, owner, identity) : Model.Decision}:
  match core platform:
    case InteractionTypes.State{+application, +services} Model.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}:
      Equal.cong(Bool, Model.Decision,
        (inside => Model.realized_decision(Model.observed_focus(
          Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}, inside,
          Focus.Content{owner, identity}, InteractionTypes.State{application, services}))),
        Model.active_content_owner(InteractionTypes.State{application, services}, capacity, owner), True{}, active)

def Rule.available_surface_content_focus_observation(core, platform, owner, identity, node, found, eligible):
  observed_content_focus_owned(core, platform, owner, identity,
    content_owner_from_lookup(core, platform, owner, node, found, eligible))
