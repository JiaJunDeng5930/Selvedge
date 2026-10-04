import Base
import ../../bendlib/stdlib.bend as Std
import ../physical-source.bend as Source
import ../physical-content.bend as Content
import ../physical-content-rules.bend as ContentRules
import ../physical-source-rules.bend as Rule
import ../physical-space.bend as Model
import ../document.bend as Doc

def admitted(+duplicate: Maybe<&2, Content.NativeSlot>, +prepared: Content.Prepared,
  proof: {Content.duplicate_native_slot(Content.native_slots(prepared)) == duplicate : Maybe<&2, Content.NativeSlot>}) ->
  {ContentRules.ready_native_targets_valid(Source.admit_duplicate(duplicate, prepared)) == True{} : Bool}:
  match duplicate:
    case None{}:
      Std.transport(Maybe<&2, Content.NativeSlot>, None{},
        (result => {ContentRules.no_duplicate(result) == True{} : Bool}), {==},
        Content.duplicate_native_slot(Content.native_slots(prepared)), proof)
    case Some{Content.NativeSlot{owner_key, target_key}}:
      match prepared:
        case Content.Prepared{snapshot, tree, roots, policies}: {==}

def admission(+prepared: Content.Prepared) ->
  {ContentRules.ready_native_targets_valid(Source.admit_native_targets(prepared)) == True{} : Bool}:
  admitted(Content.duplicate_native_slot(Content.native_slots(prepared)), prepared, {==})

def single_root(trees: +List<Model.Tree<Content.Value, Doc.Event>>, +snapshot: Content.Snapshot,
  +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {ContentRules.ready_native_targets_valid(Source.single_root(trees, snapshot, roots, policies)) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{tree, Nil{}}: admission(Content.Prepared{snapshot, tree, roots, policies})
    case Con{tree, Con{next, rest}}: {==}

def preparation(result: Source.Forest, +snapshot: Content.Snapshot) ->
  {ContentRules.ready_native_targets_valid(Source.preparation(result, snapshot)) == True{} : Bool}:
  match result:
    case Source.ReadyForest{trees, roots, policies}: single_root(trees, snapshot, roots, policies)
    case Source.MissingForest{first, remaining}: {==}
    case Source.InvalidForest{error}: {==}

def native_targets(+snapshot: Content.Snapshot, +observations: +List<Content.Observation>) ->
  Rule.native_targets_claim(snapshot, observations):
  match snapshot:
    case Content.Snapshot{generation, source, default_font}:
      preparation(Source.prepare_forest(source <> Nil{}, default_font, generation, "", 0n, Source.Ordinary{}, observations), snapshot)

def Rule.evidence():
  Rule.Requirements{+snapshot => +observations => native_targets(snapshot, observations)}
