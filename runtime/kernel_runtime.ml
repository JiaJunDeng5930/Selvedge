open Js_of_ocaml
module Model = KernelModel
module Json = Json_io.Make(Model)

let initial () = Model.selvedge_kernel_initial
let initial_shared () = Js.bytestring (Stored_state.encode_shared (initial ()))

let restore_state sequence shared tasks =
  let decode_task bytes = Stored_state.decode_task_exn (Js.to_bytestring bytes) in
  try
    let tasks = Array.to_list (Array.map decode_task (Js.to_array tasks)) in
    let sequence = Big_int_Z.big_int_of_string (Js.to_string sequence) in
    Js.Unsafe.inject (Stored_state.restore_exn (Js.to_bytestring shared) ~sequence ~tasks)
  with State_wire.Invalid_state -> Js.Unsafe.inject Js.null

let changed_tasks before next =
  let rec collect id writes previous current =
    if previous == current then writes else
    match previous, current with
    | old :: old_rest, task :: rest ->
        let writes = if Stored_state.same_task old task then writes else (id, Some old, task) :: writes in
        collect (id + 1) writes old_rest rest
    | [], task :: rest -> collect (id + 1) ((id, None, task) :: writes) [] rest
    | [], [] -> writes
    | _ :: _, [] ->
        (* DEFENSE: Archival keeps task identities, so a shorter registry would
           silently leave stale durable rows. *)
        invalid_arg "The committed task registry cannot shrink"
  in
  List.rev (collect 0 [] (Stored_state.tasks before) (Stored_state.tasks next))

let task_writes changes =
  List.map (fun (id, _, task) ->
    Js.Unsafe.obj [| "id", Js.Unsafe.inject (Js.number_of_float (float_of_int id));
      "data", Js.Unsafe.inject (Js.bytestring (Stored_state.encode_task task)) |]) changes
  |> Array.of_list |> Js.array

let storage before next changes =
  if Big_int_Z.eq_big_int (Stored_state.sequence before) (Stored_state.sequence next) then
    Js.Unsafe.inject Js.null
  else
    let shared = if Stored_state.same_shared before next then Js.Unsafe.inject Js.null
      else Js.Unsafe.inject (Js.bytestring (Stored_state.encode_shared next)) in
    Js.Unsafe.inject (Js.Unsafe.obj [| "shared", shared;
      "tasks", Js.Unsafe.inject (task_writes changes) |])
let input_error name message =
  Js.Unsafe.obj [| "inputError", Js.Unsafe.inject (Js.Unsafe.obj [|
    "name", Js.Unsafe.inject (Js.string name);
    "message", Js.Unsafe.inject (Js.string message)
  |]) |]
let with_input source apply =
  match Model.selvedge_parse_input_json (Js.to_string source) with
  | TextJson.InputAccepted value -> apply value
  | TextJson.InputInvalid -> input_error "TypeError" "Invalid domain JSON input"
  | TextJson.InputNestingExceeded -> input_error "RangeError" Model.selvedge_input_nesting_error
let packet source world = with_input source (fun input ->
  let next, envelope = Model.selvedge_kernel_journal_packet Stored_state.same_world input world in
  let changes = changed_tasks world next in
  Js.Unsafe.obj [|
    "world", Js.Unsafe.inject next;
    "storage", storage world next changes;
    "changedTasks", Js.Unsafe.inject changes;
    "reconcileRemote", Js.Unsafe.inject (Js.bool (world != next && Model.selvedge_kernel_remote_reconciliation_needed world next));
    "envelope", Js.Unsafe.inject (Js.string (Json.stringify envelope))
  |])
let observe world = Js.string (Json.stringify (Model.selvedge_kernel_world_json world))

let observe_patch before next changes =
  let observe_row project id task world =
    Json.stringify (project (Big_int_Z.big_int_of_int id) task world) in
  let row id text =
    Js.Unsafe.obj [| "id", Js.Unsafe.inject (Js.number_of_float (float_of_int id));
      "text", Js.Unsafe.inject (Js.string text) |] in
  let tasks = List.map (fun (id, old, task) ->
    let result = row id (observe_row Model.selvedge_kernel_task_publication id task next) in
    let history = Stored_state.task_history task in
    let appended = match old with
      | Some previous when Stored_state.task_history previous == history -> "[]"
      | _ ->
          (* A committed task's history only grows. Born tasks publish their inherited prefix once. *)
          let cursor = match old with None -> 0 | Some previous -> List.length (Stored_state.task_history previous) in
          Json.stringify (Model.selvedge_kernel_task_history_suffix
            (Big_int_Z.big_int_of_int id) (Big_int_Z.big_int_of_int cursor) task) in
    Js.Unsafe.set result "appended" (Js.string appended);
    result) changes in
  let changed = Hashtbl.create (List.length changes) in
  let ancestors = Hashtbl.create (List.length changes) in
  List.iter (fun (id, old, task) ->
    Hashtbl.add changed id ();
    if Option.is_none old then List.iter (fun ancestor ->
      Hashtbl.replace ancestors (Big_int_Z.int_of_big_int ancestor) ())
      (Stored_state.task_lineage task)) changes;
  let shared_dependencies_changed = not (Stored_state.same_publication_dependencies before next) in
  let references =
    if shared_dependencies_changed || Hashtbl.length ancestors > 0 then
      let observe = observe_row Model.selvedge_kernel_task_publication_references in
      List.filter_map (fun (id, task) ->
        let fork_changed = Hashtbl.mem ancestors id ||
          List.exists (fun ancestor -> Hashtbl.mem ancestors (Big_int_Z.int_of_big_int ancestor))
            (Stored_state.task_lineage task) in
        if Hashtbl.mem changed id || not (shared_dependencies_changed || fork_changed)
        then None else
        let current = observe id task next in
        if String.equal current (observe id task before) then None
        else Some (row id current))
        (List.mapi (fun id task -> id, task) (Stored_state.tasks before))
    else [] in
  let catalog_changed = not (Stored_state.same_environment before next) in
  let membership_changed (_, previous, task) =
    let project = Model.selvedge_kernel_publication_project task in
    let old_project = Option.bind previous Model.selvedge_kernel_publication_project in
    not (Option.equal Big_int_Z.eq_big_int project old_project) in
  let projects_changed = not (Stored_state.same_projects before next) || List.exists membership_changed changes in
  Js.Unsafe.obj [|
    "shared", Js.Unsafe.inject (Js.string
      (Json.stringify (Model.selvedge_kernel_shared_publication catalog_changed projects_changed next)));
    "tasks", Js.Unsafe.inject (Js.array (Array.of_list tasks));
    "references", Js.Unsafe.inject (Js.array (Array.of_list references))
  |]
let assess source world = with_input source (fun input ->
  Js.Unsafe.obj [| "envelope", Js.Unsafe.inject
    (Js.string (Json.stringify (Model.selvedge_kernel_assess input world))) |])
let () = Js.Unsafe.set Js.Unsafe.global "__selvedgeKernel" (Js.Unsafe.obj [|
  "initial", Js.Unsafe.inject (Js.wrap_callback initial);
  "packet", Js.Unsafe.inject (Js.wrap_callback packet);
  "initialShared", Js.Unsafe.inject (Js.wrap_callback initial_shared);
  "restoreState", Js.Unsafe.inject (Js.wrap_callback restore_state);
  "observe", Js.Unsafe.inject (Js.wrap_callback observe);
  "observePatch", Js.Unsafe.inject (Js.wrap_callback observe_patch);
  "assess", Js.Unsafe.inject (Js.wrap_callback assess)
|])
