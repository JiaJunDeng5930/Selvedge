import ../../interaction/IDENTITY.bend as UIIdentity
import Base
import ./project-presentation-laws.bend as Rule
import ../appearance/DESIGN.bend as Design
import ../controls/MODEL.bend as Authored
import ../layout/physical-space.bend as Model
import ../layout/enclosure.bend as Enclosure
import ../controls/PROGRAM.bend as Controls
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/MODEL.bend as View

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

def project_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +children: +List<InterfaceView.Node>, +context: Controls.Context, +project: Nat, +selected: Bool, +expanded: Bool) -> Rule.project_reference_law(key, semantic, label, role, children, context, project, selected, expanded):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def task_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +children: +List<InterfaceView.Node>, +context: Controls.Context, +task: Nat, +status: View.TaskStatus, +selected: Bool) -> Rule.task_reference_law(key, semantic, label, role, children, context, task, status, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def chooser_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +children: +List<InterfaceView.Node>, +context: Controls.Context, +selected: Maybe<&2, Nat>) -> Rule.chooser_reference_law(key, semantic, label, role, children, context, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def project_family_projection(+area: Controls.Area, +owner: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +project: Nat, +selected: Bool, +expanded: Bool, +children: +List<InterfaceView.Node>, +input: Core.Input, +name: String, +face: Controls.Face, +behavior: Controls.Behavior, +geometry: Controls.Geometry) ->
  {Controls.contextual_source_presentation(area, Controls.SourceFamily{InterfaceView.Node{owner, semantic, label, role, InterfaceView.ProjectGroup{project, selected, expanded}, children}}, input, name, face, behavior, geometry) ==
    Controls.project_presentation(Controls.project_control_matches(input, project), Controls.project_control_input(input), expanded, name, face, behavior, geometry) : Controls.ActionPresentation}:
  match area:
    case Controls.PageArea{}: {==}
    case Controls.NavigationArea{}: {==}
    case Controls.ComposerArea{}: {==}
    case Controls.ToolbarArea{}: {==}
    case Controls.CodeArea{}: {==}
    case Controls.ActivityArea{}: {==}
    case Controls.ApprovalArea{}: {==}
    case Controls.MenuArea{}: {==}
    case Controls.DialogArea{}: {==}
    case Controls.CollectionArea{}: {==}
    case Controls.CardArea{}: {==}
    case Controls.BoardViewArea{}: {==}
    case Controls.BoardLaneArea{}: {==}

def unscoped_projection(+area: Controls.Area, +input: Core.Input, +name: String, +face: Controls.Face, +behavior: Controls.Behavior, +geometry: Controls.Geometry) ->
  {Controls.contextual_source_presentation(area, Controls.Unscoped{}, input, name, face, behavior, geometry) == Controls.ActionPresentation{face, behavior, geometry} : Controls.ActionPresentation}:
  match area:
    case Controls.PageArea{}: {==}
    case Controls.NavigationArea{}: {==}
    case Controls.ComposerArea{}: {==}
    case Controls.ToolbarArea{}: {==}
    case Controls.CodeArea{}: {==}
    case Controls.ActivityArea{}: {==}
    case Controls.ApprovalArea{}: {==}
    case Controls.MenuArea{}: {==}
    case Controls.DialogArea{}: {==}
    case Controls.CollectionArea{}: {==}
    case Controls.CardArea{}: {==}
    case Controls.BoardViewArea{}: {==}
    case Controls.BoardLaneArea{}: {==}

def status_indicator_extent(+key: UIIdentity.Key, status: View.TaskStatus, visual: Design.Style) ->
  {Rule.status_extent(Authored.task_status_indicator(key, status, visual)) == (Model.ExactSize{16n}, (Model.ExactSize{16n}, Enclosure.Extent{16n, 16n})) : Model.AxisSize & (Model.AxisSize & Enclosure.Extent)}:
  Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def Rule.evidence():
  Rule.Requirements{
    +project => {==},
    +project => {==},
    +project => {==},
    +project => +trigger => {==},
    +name => +expanded => +fallback => {==},
    project_family_projection,
    unscoped_projection,
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
    +typography => +key => +owner => +owner_semantic => +owner_label => +owner_role => +owner_children => +project => +selected => +expanded => +area => +selection => +code => +appearance => +access => +open => +layers => +execution => +representation => +fallback => {==},
    {==},
    {==},
    working => {==},
    working => {==},
    working => {==},
    +key => +status => +visual => {==},
    status_indicator_extent,
    +key => role => meaning => nodes => +rest => +status => +visual => {==}}
