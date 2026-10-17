import Base
import ./MODEL.bend as G
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ../../bendlib/association-map.bend as Finite

type MessageBoundary is Type:
  MessageBoundary{
    output: @+text:String -> {Actual.expand(G.Output{}, text) == text : String},
    literal: @+text:String -> @+output:String -> {Actual.expand(G.Literal{text}, output) == text : String},
    concatenation: @+parts:+List<G.Message> -> @+output:String ->
      {Actual.expand(G.Concat{parts}, output) == Actual.expand_parts(parts, output) : String},
    empty_parts: @+output:String -> {Actual.expand_parts(Nil{}, output) == "" : String},
    head_before_tail: @+head:G.Message -> @+tail:+List<G.Message> -> @+output:String ->
      {Actual.expand_parts(head <> tail, output) == Actual.expand(head, output) ++ Actual.expand_parts(tail, output) : String},
    pending_meaning: @+source:Nat -> @+output:String -> @+state:G.State ->
      {Actual.pending(source, output, state) == Spec.pending(source, output, state) : +List<G.Delivery>},
    resolved_target: @+graph:Nat -> @+rule:String -> @+nodes:+List<G.ResolvedNode> -> @+key:String -> @+target:Nat -> @+message:G.Message -> @+output:String ->
      @observed:{G.resolve(key, nodes) == Some{target} : Maybe<&2, Nat>} ->
      {Actual.action(graph, rule, nodes, G.Action{key, message}, output) == [G.Delivery{graph, rule, target, Actual.expand(message, output)}] : +List<G.Delivery>},
    missing_target: @+graph:Nat -> @+rule:String -> @+nodes:+List<G.ResolvedNode> -> @+key:String -> @+message:G.Message -> @+output:String ->
      @observed:{G.resolve(key, nodes) == None{} : Maybe<&2, Nat>} ->
      {Actual.action(graph, rule, nodes, G.Action{key, message}, output) == Nil{} : +List<G.Delivery>},
    selected_source: @+source:Nat -> @+graph:Nat -> @+key:String -> @+origin:String -> @+nodes:+List<G.ResolvedNode> -> @+actions:+List<G.Action> -> @+output:String ->
      @observed:{G.resolve(origin, nodes) == Some{source} : Maybe<&2, Nat>} ->
      {Actual.rule(source, graph, nodes, G.Rule{key, origin, actions}, output) == Actual.actions(graph, key, nodes, actions, output) : +List<G.Delivery>},
    other_source: @+source:Nat -> @+other:Nat -> @+graph:Nat -> @+key:String -> @+origin:String -> @+nodes:+List<G.ResolvedNode> -> @+actions:+List<G.Action> -> @+output:String ->
      @observed:{G.resolve(origin, nodes) == Some{other} : Maybe<&2, Nat>} -> @different:{Nat.is_eq(source, other) == False{} : Bool} ->
      {Actual.rule(source, graph, nodes, G.Rule{key, origin, actions}, output) == Nil{} : +List<G.Delivery>},
    dispatch_order: @+source:Nat -> @+output:String -> @+left:+List<Finite.Entry(G.Graph)> -> @+right:+List<Finite.Entry(G.Graph)> ->
      {Actual.pending_entries(source, output, List.append(&2, Finite.Entry(G.Graph), left, right)) ==
       List.append(&2, G.Delivery, Actual.pending_entries(source, output, left), Actual.pending_entries(source, output, right)) : +List<G.Delivery>}}

type RegistryBoundary is Type:
  RegistryBoundary{
    admission: G.AdmissionBoundary,
    installation: @+id:Nat -> @+declaration:G.Declaration -> @+nodes:+List<G.ResolvedNode> -> @+state:G.State ->
      {Actual.install(id, declaration, nodes, state) == Spec.install(id, declaration, nodes, state) : G.State},
    removal: @+id:Nat -> @+state:G.State -> {Actual.remove(id, state) == Spec.remove(id, state) : G.State},
    recording: @+id:Nat -> @+values:+List<G.Receipt> -> @+state:G.State -> {Actual.receipts(id, values, state) == Spec.receipts(id, values, state) : G.State},
    installed_value: @+id:Nat -> @+declaration:G.Declaration -> @+nodes:+List<G.ResolvedNode> -> @+state:G.State ->
      {G.find(Actual.install(id, declaration, nodes, state), id) == Some{Actual.installed(declaration, nodes)} : Maybe<&2, G.Graph>},
    removed_absence: @+id:Nat -> @+state:G.State -> {G.find(Actual.remove(id, state), id) == None{} : Maybe<&2, G.Graph>},
    unrelated_installation: @+id:Nat -> @+other:Nat -> @+declaration:G.Declaration -> @+nodes:+List<G.ResolvedNode> -> @+state:G.State ->
      @different:{Nat.is_eq(other, id) == False{} : Bool} ->
      {G.find(Actual.install(id, declaration, nodes, state), other) == G.find(state, other) : Maybe<&2, G.Graph>},
    unrelated_removal: @+id:Nat -> @+other:Nat -> @+state:G.State -> @different:{Nat.is_eq(other, id) == False{} : Bool} ->
      {G.find(Actual.remove(id, state), other) == G.find(state, other) : Maybe<&2, G.Graph>},
    messages: MessageBoundary}
