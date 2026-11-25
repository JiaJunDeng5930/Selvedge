open Js_of_ocaml
module Model = KernelModel
module Json = Json_io.Make(Model)

let initial () = Model.selvedge_kernel_initial
let shared_writes before next =
  Stored_state.shared_writes before next
  |> List.map (fun (id, data) -> Js.Unsafe.obj [|
       "id", Js.Unsafe.inject (Js.number_of_float (float_of_int id));
       "data", Js.Unsafe.inject (Js.bytestring data) |])
  |> Array.of_list |> Js.array
let initial_shared () = shared_writes None (initial ())

let restore_state sequence shared tasks =
  let number row key = Js.float_of_number (Js.Unsafe.get row key) in
  let bytes row = Js.to_bytestring (Js.Unsafe.get row "data") in
  let decode_task row =
    let length, reversed =
      Array.fold_left (fun (cursor, reversed) chunk ->
        let messages = Stored_state.decode_history_exn (bytes chunk) in
        (* DEFENSE: Stored history must be contiguous and each chunk must add messages. *)
        if number chunk "start" <> float_of_int cursor || messages = [] then raise State_wire.Invalid_state;
        cursor + List.length messages, List.rev_append messages reversed)
      (0, []) (Js.to_array (Js.Unsafe.get row "history")) in
    (* DEFENSE: The task record retains its expected length even if its last chunk is missing. *)
    if number row "length" <> float_of_int length then raise State_wire.Invalid_state;
    Stored_state.decode_task_exn (bytes row) (List.rev reversed) in
  try
    let tasks = Array.to_list (Array.map decode_task (Js.to_array tasks)) in
    let sequence = Big_int_Z.big_int_of_string (Js.to_string sequence) in
    let sections = Array.map Js.to_bytestring (Js.to_array shared) in
    Js.Unsafe.inject (Stored_state.restore_exn sections ~sequence ~tasks)
  with State_wire.Invalid_state -> Js.Unsafe.inject Js.null

type ('task, 'message) task_change = {
  id : int;
  previous : 'task option;
  task : 'task;
  history : (int * 'message list) option;
}

let changed_task id previous task =
  let history = Stored_state.task_history task in
  let appended = match previous with
    | Some old when Stored_state.task_history old == history -> None
    | _ ->
        (* A committed task only extends its history. Born tasks record their initial prefix. *)
        let start = match previous with None -> 0 | Some old -> List.length (Stored_state.task_history old) in
        let messages = Model.selvedge_kernel_task_history_since (Big_int_Z.big_int_of_int start) task in
        match messages with
        | [] ->
            (* DEFENSE: A shortened committed history cannot be written as an append. *)
            if List.length history <> start then invalid_arg "The committed task history cannot shrink";
            None
        | _ -> Some (start, messages) in
  {id; previous; task; history = appended}

let changed_tasks before next =
  let rec collect id writes previous current =
    if previous == current then writes else
    match previous, current with
    | old :: old_rest, task :: rest ->
        let writes = if Stored_state.same_task old task then writes else changed_task id (Some old) task :: writes in
        collect (id + 1) writes old_rest rest
    | [], task :: rest -> collect (id + 1) (changed_task id None task :: writes) [] rest
    | [], [] -> writes
    | _ :: _, [] ->
        (* DEFENSE: Archival keeps task identities, so a shorter registry would
           silently leave stale durable rows. *)
        invalid_arg "The committed task registry cannot shrink"
  in
  List.rev (collect 0 [] (Stored_state.tasks before) (Stored_state.tasks next))

let task_writes changes =
  let number value = Js.Unsafe.inject (Js.number_of_float (float_of_int value)) in
  List.map (fun change ->
    let history = match change.history with
      | None -> Js.Unsafe.inject Js.null
      | Some (start, messages) -> Js.Unsafe.inject (Js.Unsafe.obj [|
          "start", number start; "length", number (List.length messages);
          "data", Js.Unsafe.inject (Js.bytestring (Stored_state.encode_history messages)) |]) in
    Js.Unsafe.obj [| "id", number change.id; "history", history;
      "born", Js.Unsafe.inject (Js.bool (Option.is_none change.previous));
      "data", Js.Unsafe.inject (Js.bytestring (Stored_state.encode_task_metadata change.task)) |]) changes
  |> Array.of_list |> Js.array

let storage before next changes =
  if Big_int_Z.eq_big_int (Stored_state.sequence before) (Stored_state.sequence next) then
    Js.Unsafe.inject Js.null
  else
    Js.Unsafe.inject (Js.Unsafe.obj [| "shared", Js.Unsafe.inject (shared_writes (Some before) next);
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
  let tasks = List.map (fun change ->
    let result = row change.id (observe_row Model.selvedge_kernel_task_publication change.id change.task next) in
    let appended = match change.history with
      | None -> "[]"
      | Some (_, messages) -> Json.stringify
          (Model.selvedge_kernel_history_publication (Big_int_Z.big_int_of_int change.id) messages) in
    Js.Unsafe.set result "appended" (Js.string appended);
    result) changes in
  let changed = Hashtbl.create (List.length changes) in
  let ancestors = Hashtbl.create (List.length changes) in
  List.iter (fun change ->
    Hashtbl.add changed change.id ();
    if Option.is_none change.previous then List.iter (fun ancestor ->
      Hashtbl.replace ancestors (Big_int_Z.int_of_big_int ancestor) ())
      (Stored_state.task_lineage change.task)) changes;
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
  let membership_changed change =
    let project = Model.selvedge_kernel_publication_project change.task in
    let old_project = Option.bind change.previous Model.selvedge_kernel_publication_project in
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
