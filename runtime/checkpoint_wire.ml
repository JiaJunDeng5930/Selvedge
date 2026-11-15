(** Version 1 wire primitives. Strings are length-prefixed byte strings, and
    exact integers use their decimal spelling. Compound shapes are generated. *)
exception Invalid_checkpoint

type reader = { bytes : string; mutable offset : int }

let start bytes = { bytes; offset = 0 }
let remaining reader = String.length reader.bytes - reader.offset
let reserve reader length =
  (* DEFENSE: A checkpoint ending inside a value cannot restore a world. *)
  if length < 0 || length > remaining reader then raise Invalid_checkpoint;
  let offset = reader.offset in
  reader.offset <- offset + length;
  offset

let write_char = Buffer.add_char
let read_char reader = String.get reader.bytes (reserve reader 1)
let write_length output length = Buffer.add_int32_le output (Int32.of_int length)
let read_length reader = Int32.to_int (String.get_int32_le reader.bytes (reserve reader 4))
let write_string output value =
  write_length output (String.length value);
  Buffer.add_string output value
let read_string reader =
  let length = read_length reader in
  String.sub reader.bytes (reserve reader length) length

let write_big_int output value = write_string output (Big_int_Z.string_of_big_int value)
let read_big_int reader =
  let spelling = read_string reader in
  (* DEFENSE: A structurally invalid image can contain a non-integer spelling. *)
  try Big_int_Z.big_int_of_string spelling with Invalid_argument _ | Failure _ -> raise Invalid_checkpoint

let write_bool output value = write_char output (if value then '\001' else '\000')
let read_bool reader = match read_char reader with
  | '\000' -> false
  | '\001' -> true
  (* DEFENSE: An invalid tag cannot select a boolean or optional value. *)
  | _ -> raise Invalid_checkpoint
let write_unit output () = write_char output '\000'
let read_unit reader =
  (* DEFENSE: A unit value occupies a validated byte, as do list elements. *)
  if read_char reader <> '\000' then raise Invalid_checkpoint

let write_option write output = function
  | None -> write_bool output false
  | Some value -> write_bool output true; write output value
let read_option read reader = if read_bool reader then Some (read reader) else None
let write_list write output values =
  write_length output (List.length values);
  List.iter (write output) values
let read_list read reader =
  let length = read_length reader in
  (* DEFENSE: Every element occupies bytes, so an impossible count cannot allocate a list. *)
  if length < 0 || length > remaining reader then raise Invalid_checkpoint;
  let rec loop count values =
    if count = 0 then List.rev values
    else loop (count - 1) (read reader :: values) in
  loop length []
