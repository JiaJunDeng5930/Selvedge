import Base
import ./SYSTEM.bend as Core
import ./interface.bend as Model
import ./ui-world.bend as V
import ./user-context.bend as Context
import ./user-input.bend as U

law composer_tree_present_agreement:
  for +identity: U.Editor
  for revision: Nat
  for message: U.Text
  for footer: +List<V.ComposerControl>
  for context: Maybe<&2, Context.Observation>
  for submit: V.ControlDeclaration
  for feedback: U.Feedback
  for pending: Bool
  for +parent: String
  for +state: Core.State
  {Model.composer(Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}, parent, state) ==
      Model.expected_composer(Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}, parent, state) : +List<Model.Node>}


law composer_tree_agreement:
  for view: Maybe<&2, V.ComposerScene>
  for +parent: String
  for +state: Core.State
  {Model.composer(view, parent, state) == Model.expected_composer(view, parent, state) : +List<Model.Node>}


law relocated_valid_content:
  for valid: Bool
  for +node: Model.Node
  for +scene: Core.Scene
  for +base: +List<Model.Node>
  for +overlays: +List<Model.Node>
  {Model.content(Model.relocate_valid_trigger(valid, node, scene, base, overlays)) == scene : Core.Scene}


law relocated_found_content:
  for found: Maybe<&2, Model.Node>
  for +target: Nat
  for +scene: Core.Scene
  for +base: +List<Model.Node>
  for +overlays: +List<Model.Node>
  {Model.content(Model.relocate_found_trigger(found, target, scene, base, overlays)) == scene : Core.Scene}


law relocated_key_content:
  for found: Maybe<&2, String>
  for +target: Nat
  for +scene: Core.Scene
  for +base: +List<Model.Node>
  for +overlays: +List<Model.Node>
  {Model.content(Model.relocate_trigger_key(found, target, scene, base, overlays)) == scene : Core.Scene}


law relocated_content:
  for trigger: Maybe<&2, Model.PersistentTrigger>
  for +scene: Core.Scene
  for +base: +List<Model.Node>
  for +overlays: +List<Model.Node>
  {Model.content(Model.relocate_persistent_trigger(trigger, scene, base, overlays)) == scene : Core.Scene}


law assembled_content:
  for +scene: Core.Scene
  for +state: Core.State
  {Model.content(Model.assemble(scene, state)) == scene : Core.Scene}
