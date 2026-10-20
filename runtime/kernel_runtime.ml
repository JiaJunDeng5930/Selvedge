open Js_of_ocaml
module Model = KernelModel
module Json = Json_io.Make(Model)

(* World values stay opaque inside this worker; only domain JSON crosses IO. *)
let initial () = Model.selvedge_kernel_initial
let packet source world =
  let world, envelope = Model.selvedge_kernel_packet (Json.parse (Js.to_string source)) world in
  Js.Unsafe.obj [|
    "world", Js.Unsafe.inject world;
    "envelope", Js.Unsafe.inject (Js.string (Json.stringify envelope))
  |]
let observe world = Js.string (Json.stringify (Model.selvedge_kernel_world_json world))
let () = Js.Unsafe.set Js.Unsafe.global "__selvedgeKernel" (Js.Unsafe.obj [|
  "initial", Js.Unsafe.inject (Js.wrap_callback initial);
  "packet", Js.Unsafe.inject (Js.wrap_callback packet);
  "observe", Js.Unsafe.inject (Js.wrap_callback observe)
|])
