import Base
import ../bendlib/json.bend as J
import ./ui-identity.bend as Identity

type Requirements is Type:
  Requirements{
    place_payload: @path:String ->
      {Identity.place(path) == Identity.Place{path} : Identity.Key},
    entity_payload: @owner:Identity.Key -> @kind:String -> @identity:String ->
      {Identity.entity(owner, kind, identity) == Identity.Entity{owner, kind, identity} : Identity.Key},
    part_payload: @owner:Identity.Key -> @name:String ->
      {Identity.part(owner, name) == Identity.Part{owner, name} : Identity.Key},
    place_comparison: @path:String -> @other_path:String ->
      {Identity.same(Identity.Place{path}, Identity.Place{other_path}) == String.eq(path, other_path) : Bool},
    entity_comparison: @owner:Identity.Key -> @kind:String -> @identity:String -> @other_owner:Identity.Key -> @other_kind:String -> @other_identity:String ->
      {Identity.same(Identity.Entity{owner, kind, identity}, Identity.Entity{other_owner, other_kind, other_identity}) == (Identity.same(owner, other_owner) && (String.eq(kind, other_kind) && String.eq(identity, other_identity))) : Bool},
    part_comparison: @owner:Identity.Key -> @name:String -> @other_owner:Identity.Key -> @other_name:String ->
      {Identity.same(Identity.Part{owner, name}, Identity.Part{other_owner, other_name}) == (Identity.same(owner, other_owner) && String.eq(name, other_name)) : Bool},
    place_entity_distinct: @path:String -> @owner:Identity.Key -> @kind:String -> @identity:String ->
      {Identity.same(Identity.Place{path}, Identity.Entity{owner, kind, identity}) == False{} : Bool},
    place_entity_reverse_distinct: @path:String -> @owner:Identity.Key -> @kind:String -> @identity:String ->
      {Identity.same(Identity.Entity{owner, kind, identity}, Identity.Place{path}) == False{} : Bool},
    place_part_distinct: @path:String -> @owner:Identity.Key -> @name:String ->
      {Identity.same(Identity.Place{path}, Identity.Part{owner, name}) == False{} : Bool},
    place_part_reverse_distinct: @path:String -> @owner:Identity.Key -> @name:String ->
      {Identity.same(Identity.Part{owner, name}, Identity.Place{path}) == False{} : Bool},
    entity_part_distinct: @owner:Identity.Key -> @kind:String -> @identity:String -> @part_owner:Identity.Key -> @name:String ->
      {Identity.same(Identity.Entity{owner, kind, identity}, Identity.Part{part_owner, name}) == False{} : Bool},
    entity_part_reverse_distinct: @owner:Identity.Key -> @kind:String -> @identity:String -> @part_owner:Identity.Key -> @name:String ->
      {Identity.same(Identity.Part{part_owner, name}, Identity.Entity{owner, kind, identity}) == False{} : Bool},
    place_encoding: @path:String ->
      {Identity.encode(Identity.Place{path}) == ("[\"place\",\"" ++ J.escape(path) ++ "\"]") : String},
    entity_encoding: @owner:Identity.Key -> @kind:String -> @identity:String ->
      {Identity.encode(Identity.Entity{owner, kind, identity}) == ("[\"entity\"," ++ Identity.encode(owner) ++ ",\"" ++ J.escape(kind) ++ "\",\"" ++ J.escape(identity) ++ "\"]") : String},
    part_encoding: @owner:Identity.Key -> @name:String ->
      {Identity.encode(Identity.Part{owner, name}) == ("[\"part\"," ++ Identity.encode(owner) ++ ",\"" ++ J.escape(name) ++ "\"]") : String}}

law evidence:
  Requirements
