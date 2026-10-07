import Base
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/INPUT.bend as U
import ../editor/MODEL.bend as Editor
import ./PLATFORM.bend as Model
import ../focus/MODEL.bend as Focus
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
law editing_retains_selection:
  for revision: Nat
  for body: U.Body
  for directory_entry: String
  for editor: Editor.Editor
  {Model.synchronize_editor(Some{U.Draft{revision, body, U.Editing{}, directory_entry}}, editor) == editor : Editor.Editor}
law merge_reflow_product:
  for +product: Core.Decision
  for effects: +List<Model.Effect>
  for refreshed: Model.Decision
  {Model.decision_product(Model.merge_reflow(product, effects, refreshed)) == product : Core.Decision}
law changed_capacity_product:
  for decision: Model.Decision
  for capacity: View.Capacity
  {Model.decision_product(Model.changed_capacity(decision, capacity)) == Model.decision_product(decision) : Core.Decision}
law retained_capacity_product:
  for same: Bool
  for +decision: Model.Decision
  for capacity: View.Capacity
  {Model.decision_product(Model.retained_capacity(same, decision, capacity)) == Model.decision_product(decision) : Core.Decision}
law reflow_preserves_product:
  for +decision: Model.Decision
  for +capacity: View.Capacity
  {Model.decision_product(Model.reflow_capacity(decision, capacity)) == Model.decision_product(decision) : Core.Decision}

# Product focus is resolved against the returned state; other effects retain order.
def effects(decision: Model.Decision) -> +List<Model.Effect>:
  Model.Decision{product, platform, result} = decision
  result

def decision_surface(decision: Model.Decision) -> InterfaceView.Surface:
  Model.Decision{Core.Decision{core, reply, runtime, interaction, services, durable}, platform, result} = decision
  InterfaceView.observe(Model.capacity(platform), core)

def expected_focus(found: Maybe<&2, String>, ticket: Nat) -> +List<Model.Effect>:
  match found:
    case None{}: Nil{}
    case Some{key}: [Model.Focus{ticket, Focus.Product{key}}]

def expected_effects(+surface: InterfaceView.Surface, source: +List<Model.Effect>) -> +List<Model.Effect>:
  match source:
    case Nil{}: Nil{}
    case Con{Model.Focus{ticket, Focus.Product{requested}}, rest}:
      List.append(&2, Model.Effect, expected_focus(InterfaceView.focus_target(surface, requested), ticket), expected_effects(surface, rest))
    case Con{Model.ScopeFocus{ticket, previous, current}, rest}:
      List.append(&2, Model.Effect, expected_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), expected_effects(surface, rest))
    case Con{other, rest}: other <> expected_effects(surface, rest)

law realized_preserves_product:
  for decision: Model.Decision
  {Model.decision_product(Model.realized_decision(decision)) == Model.decision_product(decision) : Core.Decision}
law realized_empty:
  for product: Core.Decision
  for platform: Model.Platform
  {Model.realized_decision(Model.Decision{product, platform, Nil{}}) == Model.Decision{product, platform, Nil{}} : Model.Decision}
law step_realizes_effects:
  for +input: Model.Input
  for +state: Model.State
  {effects(Model.step(input, state)) == expected_effects(decision_surface(Model.step_raw(input, state)), effects(Model.step_raw(input, state))) : +List<Model.Effect>}


# Internal scope intents must be discharged before effects leave the platform.
def external_effects(source: +List<Model.Effect>) -> Bool:
  match source:
    case Nil{}: True{}
    case Con{Model.ScopeFocus{ticket, previous, current}, rest}: False{}
    case Con{other, rest}: external_effects(rest)

law realized_effects_are_external:
  for +surface: InterfaceView.Surface
  for source: +List<Model.Effect>
  {external_effects(Model.realized_effects(surface, source)) == True{} : Bool}
law actual_step_effects_are_external:
  for input: Model.Input
  for state: Model.State
  {external_effects(effects(Model.step(input, state))) == True{} : Bool}
def ticket(+platform: Model.Platform) -> Nat:
  editors = Model.editors(platform)
  +ticket = Model.focus_ticket(platform)
  ticket

def capacity(+platform: Model.Platform) -> View.Capacity:
  editors = Model.editors(platform)
  +capacity = Model.capacity(platform)
  capacity

def loss_effects(core: Core.State, +platform: Model.Platform, target: Focus.Target) -> +List<Model.Effect>:
  match target:
    case Focus.Product{identity}: expected_focus(InterfaceView.focus_target(InterfaceView.observe(capacity(platform), core), identity), ticket(platform))
    case Focus.Content{owner, identity}: [Model.Focus{ticket(platform), Focus.Content{owner, identity}}]

law failed_focus_receipt:
  for +model_state: Model.State
  for +received: Nat
  for +target: Focus.Target
  for +observed: Maybe<&2, Focus.Target>
  for failed: {Model.focus_confirmed(target, observed) == False{} : Bool}
  {Model.step(Model.FocusApplied{received, target, observed}, model_state) == Model.Decision{Model.unchanged(Model.core(model_state)), Model.platform(model_state), Nil{}} : Model.Decision}

law publication_focus_after_some:
  for +model_state: Model.State
  for +received: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Focus.Target
  {Model.step(Model.PublicationFocusObserved{received, before, Some{after}}, model_state) == Model.Decision{Model.unchanged(Model.core(model_state)), Model.platform(model_state), Nil{}} : Model.Decision}

law publication_focus_before_none:
  for +model_state: Model.State
  for +received: Nat
  for +after: Maybe<&2, Focus.Target>
  {Model.step(Model.PublicationFocusObserved{received, None{}, after}, model_state) == Model.Decision{Model.unchanged(Model.core(model_state)), Model.platform(model_state), Nil{}} : Model.Decision}

law publication_focus_stale:
  for +model_state: Model.State
  for +received: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Maybe<&2, Focus.Target>
  for stale: {Nat.is_eq(received, ticket(Model.platform(model_state))) == False{} : Bool}
  {Model.step(Model.PublicationFocusObserved{received, before, after}, model_state) == Model.Decision{Model.unchanged(Model.core(model_state)), Model.platform(model_state), Nil{}} : Model.Decision}

law publication_focus_inactive:
  for +model_state: Model.State
  for +received: Nat
  for +target: Focus.Target
  for inactive: {Model.active_target(Model.core(model_state), capacity(Model.platform(model_state)), target) == False{} : Bool}
  {Model.step(Model.PublicationFocusObserved{received, Some{target}, None{}}, model_state) == Model.Decision{Model.unchanged(Model.core(model_state)), Model.platform(model_state), Nil{}} : Model.Decision}

law publication_focus_loss:
  for +model_state: Model.State
  for +received: Nat
  for +target: Focus.Target
  for current: {Nat.is_eq(received, ticket(Model.platform(model_state))) == True{} : Bool}
  for active: {Model.active_target(Model.core(model_state), capacity(Model.platform(model_state)), target) == True{} : Bool}
  {Model.step(Model.PublicationFocusObserved{received, Some{target}, None{}}, model_state) == Model.Decision{Model.unchanged(Model.core(model_state)), Model.platform(model_state), loss_effects(Model.core(model_state), Model.platform(model_state), target)} : Model.Decision}
