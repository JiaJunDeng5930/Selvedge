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

let task_writes before next =
  let rec collect id writes previous current =
    if previous == current then writes else
    match previous, current with
    | old :: old_rest, task :: rest ->
        let writes = if Stored_state.same_task old task then writes else (id, task) :: writes in
        collect (id + 1) writes old_rest rest
    | [], task :: rest -> collect (id + 1) ((id, task) :: writes) [] rest
    | [], [] -> writes
    | _ :: _, [] ->
        (* DEFENSE: Archival keeps task identities, so a shorter registry would
           silently leave stale durable rows. *)
        invalid_arg "The committed task registry cannot shrink"
  in
  collect 0 [] (Stored_state.tasks before) (Stored_state.tasks next)
  |> List.rev_map (fun (id, task) ->
    Js.Unsafe.obj [| "id", Js.Unsafe.inject (Js.number_of_float (float_of_int id));
      "data", Js.Unsafe.inject (Js.bytestring (Stored_state.encode_task task)) |])
  |> Array.of_list |> Js.array

let storage before next =
  if Big_int_Z.eq_big_int (Stored_state.sequence before) (Stored_state.sequence next) then
    Js.Unsafe.inject Js.null
  else
    let shared = if Stored_state.same_shared before next then Js.Unsafe.inject Js.null
      else Js.Unsafe.inject (Js.bytestring (Stored_state.encode_shared next)) in
    Js.Unsafe.inject (Js.Unsafe.obj [| "shared", shared;
      "tasks", Js.Unsafe.inject (task_writes before next) |])
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
  Js.Unsafe.obj [|
    "world", Js.Unsafe.inject next;
    "storage", storage world next;
    "reconcileRemote", Js.Unsafe.inject (Js.bool (world != next && Model.selvedge_kernel_remote_reconciliation_needed world next));
    "envelope", Js.Unsafe.inject (Js.string (Json.stringify envelope))
  |])
let observe world = Js.string (Json.stringify (Model.selvedge_kernel_world_json world))
let assess source world = with_input source (fun input ->
  Js.Unsafe.obj [| "envelope", Js.Unsafe.inject
    (Js.string (Json.stringify (Model.selvedge_kernel_assess input world))) |])
let () = Js.Unsafe.set Js.Unsafe.global "__selvedgeKernel" (Js.Unsafe.obj [|
  "initial", Js.Unsafe.inject (Js.wrap_callback initial);
  "packet", Js.Unsafe.inject (Js.wrap_callback packet);
  "initialShared", Js.Unsafe.inject (Js.wrap_callback initial_shared);
  "restoreState", Js.Unsafe.inject (Js.wrap_callback restore_state);
  "observe", Js.Unsafe.inject (Js.wrap_callback observe);
  "assess", Js.Unsafe.inject (Js.wrap_callback assess)
|])
