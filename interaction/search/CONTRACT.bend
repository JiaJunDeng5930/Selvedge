import Base
import ./MODEL.bend as Search
import ../../harness/MODEL.bend as M
import ../../harness/COMMANDS.bend as Commands
import ../../bendlib/json.bend as J

law submitted_search_uses_shared_bounded_query:
  @+query:String -> @+project:Maybe<&2, Nat> -> @+work:Maybe<&2, Nat> -> @prior:Maybe<&2, J.Json> -> @+after:Nat -> @+world:M.World() ->
  {Search.submit(after, Search.State{query, project, work, prior}, world) ==
    Search.State{query, project, work, Some{Commands.query(M.Search{query, project, work, after, 20n}, world)}} : Search.State}

law editing_keyword_discards_previous_result:
  @+next:String -> @+query:String -> @+project:Maybe<&2, Nat> -> @+work:Maybe<&2, Nat> -> @prior:Maybe<&2, J.Json> ->
  {Search.write(next, Search.State{query, project, work, prior}) == Search.State{next, project, work, None{}} : Search.State}

law choosing_project_keeps_work_and_discards_previous_result:
  @+value:String -> @+query:String -> @+project:Maybe<&2, Nat> -> @+work:Maybe<&2, Nat> -> @prior:Maybe<&2, J.Json> ->
  {Search.choose(True{}, value, Search.State{query, project, work, prior}) == Search.State{query, Nat.read(value), work, None{}} : Search.State}

law choosing_work_keeps_project_and_discards_previous_result:
  @+value:String -> @+query:String -> @+project:Maybe<&2, Nat> -> @+work:Maybe<&2, Nat> -> @prior:Maybe<&2, J.Json> ->
  {Search.choose(False{}, value, Search.State{query, project, work, prior}) == Search.State{query, project, Nat.read(value), None{}} : Search.State}
