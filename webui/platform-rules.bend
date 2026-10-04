import Base
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/user-input.bend as U
import ./editor.bend as Editor
import ./platform.bend as Model

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
