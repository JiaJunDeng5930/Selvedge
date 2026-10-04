import Base
import ../project-presentation-laws.bend as Rule
import ../design.bend as Design
import ../controls.bend as Controls
import ../../core/interface.bend as UI
import ../../core/SYSTEM.bend as Core
import ../../core/ui-world.bend as View

def projection_construction(input: Core.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) ->
  {Controls.presented_action(input, availability, name, projection, placement, help, feedback) == Rule.projected_action(input, availability, name, projection, placement, help, feedback) : Controls.Representation}:
  match projection:
    case Controls.ActionPresentation{face, behavior, geometry}: {==}

def name_geometry(+visual: Design.Style) -> Rule.name_geometry_law(visual):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  {==}

def chooser_draft_observation(+id: Nat, +fallback: Design.Style) -> Rule.chooser_draft_observation_law(id, fallback):
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = fallback
  {==}

def project_reference(+key: String, +semantic: String, +label: String, +role: UI.Role, +children: +List<UI.Node>, +context: Controls.Context, +project: Nat, +selected: Bool, +expanded: Bool) -> Rule.project_reference_law(key, semantic, label, role, children, context, project, selected, expanded):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def task_reference(+key: String, +semantic: String, +label: String, +role: UI.Role, +children: +List<UI.Node>, +context: Controls.Context, +task: Nat, +status: String, +selected: Bool) -> Rule.task_reference_law(key, semantic, label, role, children, context, task, status, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def chooser_reference(+key: String, +semantic: String, +label: String, +role: UI.Role, +children: +List<UI.Node>, +context: Controls.Context, +selected: Maybe<&2, Nat>) -> Rule.chooser_reference_law(key, semantic, label, role, children, context, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def Rule.evidence():
  Rule.Requirements{
    +project => {==},
    +project => {==},
    +project => {==},
    +project => +trigger => {==},
    +name => +expanded => +fallback => {==},
    +area => +family => +input => +availability => +name => +face => +behavior => +geometry => +placement => +help => +feedback => projection_construction(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback),
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    name_geometry,
    {==},
    +trigger => +name => +face => +behavior => +geometry => {==},
    +name => +expanded => +fallback => {==},
    +name => +expanded => +fallback => {==},
    chooser_draft_observation,
    +typography => +key => +context => +representation => +fallback => +project => +selected => +expanded => {==},
    +typography => +key => +context => +representation => +fallback => +task => +status => +selected => {==},
    project_reference,
    task_reference,
    chooser_reference,
    +typography => +in_main => +start => +key => +semantic => +label => +role => +meaning => +children => +context => {==},
    +typography => +key => +owner => +owner_semantic => +owner_label => +owner_role => +owner_children => +project => +selected => +expanded => +area => +selection => +code => +appearance => +access => +open => +layers => +execution => +representation => +fallback => {==}}
