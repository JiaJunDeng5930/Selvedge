open Js_of_ocaml
module Model = KernelModel
module Json = Json_io.Make(Model)

(* The host authenticates a checkpoint and admits its wire schema before the
   generated decoder constructs a world. No runtime object representation crosses IO. *)
let initial () = Model.selvedge_kernel_initial
let checkpoint world = Js.bytestring (Checkpoint_state.encode world)
let restore_checkpoint source =
  match Checkpoint_state.decode (Js.to_bytestring source) with
  | Some world -> Js.Unsafe.inject world
  | None -> Js.Unsafe.inject Js.null
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
  let world, envelope = Model.selvedge_kernel_journal_packet Checkpoint_state.same_image input world in
  Js.Unsafe.obj [|
    "world", Js.Unsafe.inject world;
    "envelope", Js.Unsafe.inject (Js.string (Json.stringify envelope))
  |])
let replay version source world = with_input source (fun input ->
  let world, durable = match version with
    | 28 -> Model.selvedge_kernel_replay_format_28 input world
    | 29 -> Model.selvedge_kernel_replay input world
    | 30 -> Model.selvedge_kernel_journal_replay Checkpoint_state.same_image input world
    (* DEFENSE: A damaged journal can carry an unrecognized replay version. *)
    | _ -> world, false in
  Js.Unsafe.obj [|
    "world", Js.Unsafe.inject world;
    "durable", Js.Unsafe.inject (Js.bool durable)
  |])
let observe world = Js.string (Json.stringify (Model.selvedge_kernel_world_json world))
let assess source world = with_input source (fun input ->
  Js.Unsafe.obj [| "envelope", Js.Unsafe.inject
    (Js.string (Json.stringify (Model.selvedge_kernel_assess input world))) |])
let () = Js.Unsafe.set Js.Unsafe.global "__selvedgeKernel" (Js.Unsafe.obj [|
  "initial", Js.Unsafe.inject (Js.wrap_callback initial);
  "packet", Js.Unsafe.inject (Js.wrap_callback packet);
  "replay", Js.Unsafe.inject (Js.wrap_callback replay);
  "checkpoint", Js.Unsafe.inject (Js.wrap_callback checkpoint);
  "restoreCheckpoint", Js.Unsafe.inject (Js.wrap_callback restore_checkpoint);
  "observe", Js.Unsafe.inject (Js.wrap_callback observe);
  "assess", Js.Unsafe.inject (Js.wrap_callback assess)
|])
