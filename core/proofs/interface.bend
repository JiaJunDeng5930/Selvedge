import Base
import ../../bendlib/domain.bend as D
import ../form-fields.bend as Forms
import ../SYSTEM.bend as Core
import ../interface-rules.bend as Rule
import ../interface.bend as Model
import ../ui-world.bend as V

def Rule.composer_tree_present_agreement(identity, revision, message, footer, context, submit, feedback, pending, parent, state):
  match footer:
    case Nil{}: {==}
    case Con{first, rest}: {==}

def Rule.composer_tree_agreement(view, parent, state):
  match view:
    case None{}: {==}
    case Some{V.ComposerScene{+identity, revision, message, footer, context, submit, feedback, pending}}:
      Rule.composer_tree_present_agreement(identity, revision, message, footer, context, submit, feedback, pending, parent, state)

def Rule.relocated_valid_content(valid, node, scene, base, overlays):
  match valid:
    case False{}: {==}
    case True{}:
      Model.Node{key, semantic, label, role, meaning, children} = node
      {==}

def Rule.relocated_found_content(found, target, scene, base, overlays):
  match found:
    case None{}: {==}
    case Some{Model.Node{key, semantic, label, role, +meaning, children}}:
      Rule.relocated_valid_content(Model.persistent_trigger_source(meaning, target),
        Model.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)

def Rule.relocated_key_content(found, target, scene, base, overlays):
  match found:
    case None{}: {==}
    case Some{key}: Rule.relocated_found_content(Model.find_node(base, key), target, scene, base, overlays)

def Rule.relocated_content(trigger, scene, base, overlays):
  match trigger:
    case None{}: {==}
    case Some{Model.PersistentTrigger{target, requested}}: Rule.relocated_key_content(Model.matching_focus(base, requested), target, scene, base, overlays)

def Rule.assembled_content(scene, state):
  Core.Scene{V.Scene{nav, main, views, arrangement, attention}, preferences, transfers, attachment, code, folder_picker} = scene
  {==}


def Rule.placement_destination_authority(key, semantic, label, role, destinations, face, children, target, surface):
  {==}

def Rule.placement_filtered_destination_accepted(key, semantic, label, role, destinations, face, children, target, surface, input, hidden, accepted):
  accepted

def Rule.placement_rejected_destination(key, semantic, label, role, destinations, face, children, target, surface, rejected):
  rejected


def Rule.fixed_reasoning_catalogue_entry(key, provider, name, options):
  {==}

def Rule.fixed_reasoning_open_entry(key, provider, name):
  {==}

def Rule.retained_profile_effort(profile, previous, permitted):
  Equal.cong(Bool, String, accepted => Forms.selected_profile_effort(accepted, previous, profile),
    D.profile_permitted(profile, previous), True{}, permitted)

def Rule.reset_profile_effort(profile, previous, denied):
  Equal.cong(Bool, String, accepted => Forms.selected_profile_effort(accepted, previous, profile),
    D.profile_permitted(profile, previous), False{}, denied)

def Rule.rejected_reasoning_edit(profile, reasoning):
  {==}

def Rule.accepted_reasoning_edit(profile, reasoning):
  {==}

def Rule.selected_model_permission(profile, reasoning):
  {==}

def Rule.rejected_profile_choice():
  {==}


def Rule.new_task_model_permission(message, profile, reasoning, context, world):
  {==}

def Rule.agent_model_permission(agent, revision, name, profile, reasoning, instructions, context, concurrency, world):
  {==}
