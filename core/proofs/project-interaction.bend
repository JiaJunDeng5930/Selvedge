import Base
import ../code-block.bend as Content
import ../live-output.bend as Live
import ../user-input.bend as U
import ../user-context.bend as Context
import ../interface.bend as Interface
import ../../MODEL.bend as M
import ../../BOARD.bend as B
import ../../COMMANDS.bend as Commands
import ../../bendlib/tasks.bend as Tasks
import ../../bendlib/conversation.bend as Conversation
import ../project-interaction-laws.bend as Rule
import ../user-experience.bend as E
import ../ui-world.bend as View
import ../../bendlib/domain.bend as D
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/stdlib.bend as Std
import ../ui-identity.bend as Identity
import ../SYSTEM.bend as Core

def registered_choices_complete(+entries: +List<Finite.Entry(D.Project)>) ->
  {List.length(&2, View.ProjectChoice, View.project_choices(entries)) == List.length(&2, Finite.Entry(D.Project), entries) : Nat}:
  match entries:
    case Nil{}: {==}
    case Con{(id, D.Project{name, workspace, guidance}), +rest}:
      Equal.cong(Nat, Nat, (n => (1n + n : Nat)), List.length(&2, View.ProjectChoice, View.project_choices(rest)), List.length(&2, Finite.Entry(D.Project), rest), registered_choices_complete(rest))

def nat_same(+value: Nat) -> {Nat.is_eq(value, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: nat_same(rest)

def deletion_retains_head(+other: Nat, +id: Nat, +tail: +List<Nat>, distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(other <> tail, id), other) == True{} : Bool}:
  backwards = Equal.sym(Bool, Nat.is_eq(id, other), False{}, distinct)
  %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
    Finite.keep(~Nat, Bool.not(_), other, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
  same = Equal.sym(Bool, Nat.is_eq(other, other), True{}, nat_same(other))
  %same : {Bool.or(_, List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other)) == True{} : Bool}
  {==}

def deletion_retains_step(hit: Bool, +head: Nat, +tail: +List<Nat>, +id: Nat, +other: Nat,
  observed: {Nat.is_eq(id, head) == hit : Bool},
  induction: {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other) == True{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(head <> tail, id), other) == True{} : Bool}:
  match hit:
    case True{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, head), True{}, observed)
      %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
        Finite.keep(~Nat, Bool.not(_), head, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
      induction
    case False{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, head), False{}, observed)
      %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
        Finite.keep(~Nat, Bool.not(_), head, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
      prior = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other), True{}, induction)
      %prior : {Bool.or(Nat.is_eq(head, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(head, other))

def deletion_retains_other(+prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>, +id: Nat,
  distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(List.append(&2, Nat, prefix, other <> suffix), id), other) == True{} : Bool}:
  match prefix:
    case Nil{}: deletion_retains_head(other, id, suffix, distinct)
    case Con{+head, +rest}: deletion_retains_step(Nat.is_eq(id, head), head, List.append(&2, Nat, rest, other <> suffix), id, other, {==}, deletion_retains_other(rest, other, suffix, id, distinct))

def existing_other_head(+other: Nat, +suffix: +List<Nat>) ->
  {List.contains(~Nat, ~Nat.is_eq, other <> suffix, other) == True{} : Bool}:
  backwards = Equal.sym(Bool, Nat.is_eq(other, other), True{}, nat_same(other))
  %backwards : {Bool.or(_, List.contains(~Nat, ~Nat.is_eq, suffix, other)) == True{} : Bool}
  {==}

def existing_other(+prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>) ->
  {List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, prefix, other <> suffix), other) == True{} : Bool}:
  match prefix:
    case Nil{}: existing_other_head(other, suffix)
    case Con{+head, +rest}:
      backwards = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, rest, other <> suffix), other), True{}, existing_other(rest, other, suffix))
      %backwards : {Bool.or(Nat.is_eq(head, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(head, other))

def toggle_retains_case(hit: Bool, +prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>, +id: Nat,
  distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.toggle_collapsed(hit, id, List.append(&2, Nat, prefix, other <> suffix)), other) == True{} : Bool}:
  match hit:
    case True{}: deletion_retains_other(prefix, other, suffix, id, distinct)
    case False{}:
      backwards = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, prefix, other <> suffix), other), True{}, existing_other(prefix, other, suffix))
      %backwards : {Bool.or(Nat.is_eq(id, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(id, other))

def picker_complete_nodes(+values: +List<View.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: Identity.Key, +state: Core.State) -> Rule.picker_nodes(values, selected, parent, state):
  {==}

def encapsulated_missing_draft_focus(+session: E.Session, +project: Maybe<&2, Nat>, +world: M.World(), observed_drafts: {E.drafts(session) == Nil{} : +List<U.Draft>}) ->
  {E.activate_selected(U.SelectProject{project}, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_route(U.Start{}, session)))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}:
  E.Session{+route, +stored_drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_drafts = Equal.sym(E.Session, session, E.with_drafts(Nil{}, session),
    Equal.cong(+List<U.Draft>, E.Session, value => E.with_drafts(value, session), E.drafts(session), Nil{}, observed_drafts))
  %backwards_drafts : {E.activate_selected(U.SelectProject{project}, E.from_program(world, _)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(_)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_route(U.Start{}, _)))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}
  {==}

def encapsulated_select_focus_and_input(+session: E.Session, +project: Maybe<&2, Nat>, +world: M.World(), +revision: Nat, +message: U.Text, +profile: String, +reasoning: String, +old: Context.Origin, +workspace: Maybe<&2, D.Workspace>, +sandbox: Maybe<&2, D.Sandbox>, +approval: Maybe<&2, Context.ApprovalChoice>, +feedback: U.Feedback, +directory_entry: String, +rest: +List<U.Draft>, observed_drafts: {E.drafts(session) == U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest : +List<U.Draft>}) ->
  {E.activate_selected(U.SelectProject{project}, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_drafts(E.put_draft(U.Draft{(revision + 1n : Nat), U.NewTask{message, profile, reasoning, Context.Configuration{E.context_project(project), workspace, sandbox, approval}}, U.Editing{}, directory_entry},
            U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest), E.with_route(U.Start{}, session))))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}:
  E.Session{+route, +stored_drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_drafts = Equal.sym(E.Session, session, E.with_drafts(U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest, session),
    Equal.cong(+List<U.Draft>, E.Session, value => E.with_drafts(value, session), E.drafts(session), U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest, observed_drafts))
  %backwards_drafts : {E.activate_selected(U.SelectProject{project}, E.from_program(world, _)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(_)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_drafts(E.put_draft(U.Draft{(revision + 1n : Nat), U.NewTask{message, profile, reasoning, Context.Configuration{E.context_project(project), workspace, sandbox, approval}}, U.Editing{}, directory_entry},
            U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest), E.with_route(U.Start{}, _))))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}
  {==}

def encapsulated_picker_search_preserves_session(+session: E.Session, +query: String, +world: M.World(), +trigger: String, +initial: String, previous: String, +layer_occurrence: Nat, +rest: +List<E.Layer>, observed_layers: {E.layers(session) == E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest : +List<E.Layer>}) ->
  {E.search_choices(query, E.from_program(world, session)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence} <> rest, session), Nil{}) : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest, observed_layers))
  %backwards_layers : {E.search_choices(query, E.from_program(world, _)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence} <> rest, _), Nil{}) : E.Decision}
  {==}

def encapsulated_toggle_keeps_location(+session: E.Session, +project: Nat, +world: M.World()) ->
  {E.toggle_project(project, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.toggle_project_navigation(project, E.navigation(session)), session), Nil{}) : E.Decision}:
  E.Session{+route, +drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  {==}

def Rule.evidence():
  Rule.Requirements{
    +origin => +message => +profile => +reasoning => +old => +workspace => +sandbox => +approval => world => {==},
    +project => +application => {==},
    expanded => intent => +collapsed => {==},
    intent => +collapsed => {==},
    encapsulated_toggle_keeps_location,
    +id => drafts => +world => {==},
    +drafts => +world => {==},
    entries => registered_choices_complete(entries),
    +query => +selected => +projects => {==},
    +id => +name => +workspace => guidance => +tasks => +route => +selected => +navigation => {==},
    +id => +now => +world => {==},
    +id => +name => +workspace => {==},
    +id => title => +status => +selected => +open => +parent => +state => {==},
    prefix => other => suffix => id => distinct => deletion_retains_other(prefix, other, suffix, id, distinct),
    +intent => +prefix => +other => +suffix => +id => distinct => toggle_retains_case(E.project_collapsed(E.NavigationState{intent, List.append(&2, Nat, prefix, other <> suffix)}, id), prefix, other, suffix, id, distinct),
    +id => +intent => collapsed => {==},
    picker_complete_nodes,
    +context => +world => {==},
    encapsulated_picker_search_preserves_session,
    +id => name => workspace => +selected => +expanded => +tasks => +open => +create => +toggle => +more => +parent => +state => {==},
    context => {==},
    +parent => state => {==},
    +first => +rest => +parent => +state => {==},
    encapsulated_select_focus_and_input,
    encapsulated_missing_draft_focus,
    +task => {==},
    +lifecycle => +working => {==},
    +task => {==}
  }
