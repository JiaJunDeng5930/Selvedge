(** Derive the stored state wire shape and typed OCaml codec from the public
    extracted types loaded by the compiler. Erased dependent values require
    an adapter that preserves and re-admits their declaration-dependent data. *)
open Types

type shape =
  | Primitive of string
  | List of shape
  | Option of shape
  | Tuple of shape list
  | Ref of int

type fields = (string * shape) list

type node =
  | Record of string * fields
  | Variant of string * (string * shape list) list
  | Adapter of string * shape

let adapters = [
  "Guidance.t", ("guidance-json-1", "Guidance.json", "Guidance.parse");
  "ContextTypes.context_key", ("context-key-1", "Persistence.encode_context_key", "Persistence.decode_context_key");
  "ContextTypes.snapshot", ("context-snapshot-1", "Persistence.encode_context_snapshot", "Persistence.decode_context_snapshot");
  "BoardClock.t", ("board-clock-1", "Persistence.encode_board_clock", "Persistence.decode_board_clock");
  "ChatgptArguments.arguments", ("chatgpt-arguments-1", "ChatgptArguments.encode", "Persistence.decode_chatgpt_arguments");
  "Titles.instruction", ("title-instruction-1", "Persistence.encode_title_instruction", "Persistence.decode_title_instruction");
  "Codec.settings_request", ("settings-request-1", "Persistence.encode_settings_request", "Persistence.decode_settings_request");
  "ConnectionGrants.Grants.t", ("connection-grants-1", "Persistence.encode_connection_grants", "Persistence.decode_connection_grants");
]

let fail reason = failwith ("Cannot derive stored state: " ^ reason)
let lookup env name =
  let longident = Longident.unflatten (String.split_on_char '.' name) |> Option.get in
  let _, value = Env.lookup_value ~use:false ~loc:Location.none longident env in
  value.val_type

let rec shape_text = function
  | Primitive name -> name
  | List item -> "list(" ^ shape_text item ^ ")"
  | Option item -> "option(" ^ shape_text item ^ ")"
  | Tuple items -> "(" ^ String.concat "," (List.map shape_text items) ^ ")"
  | Ref index -> "#" ^ string_of_int index

let order_named name values = List.sort (fun left right -> String.compare (name left) (name right)) values
let label field = Ident.name field.ld_id
let constructor case = Ident.name case.cd_id
let module_name path = match path with
  | Path.Pdot (owner, _) -> Path.name owner
  | _ -> fail ("unnamed module for " ^ Path.name path)

let derive env root =
  let indices = Hashtbl.create 128 and nodes = Hashtbl.create 128 in
  let register key build = match Hashtbl.find_opt indices key with
    | Some id -> Ref id
    | None ->
        let id = Hashtbl.length indices in
        Hashtbl.add indices key id;
        Hashtbl.add nodes id (build ());
        Ref id in
  let rec visit parameters ty = match get_desc ty with
    | Tvar _ -> (match List.assoc_opt (get_id ty) parameters with
        | Some shape -> shape
        | None -> fail "unbound type parameter")
    | Ttuple items -> Tuple (List.map (visit parameters) items)
    | Tconstr (path, arguments, _) ->
        let name = Path.name path in
        (try match List.assoc_opt name adapters, name, arguments with
         | Some (version, encode, _), _, [] -> register name (fun () ->
             match get_desc (lookup env encode) with
             | Tarrow (_, _, wire_type, _) -> Adapter (version, visit [] wire_type)
             | _ -> fail ("invalid adapter " ^ encode))
         | _, ("bool" | "char" | "string" | "unit"), [] -> Primitive name
         | _, ("Big_int_Z.big_int" | "Z.t"), [] -> Primitive "big_int"
         | _, "list", [item] -> List (visit parameters item)
         | _, "option", [item] -> Option (visit parameters item)
         | _ ->
             let arguments = List.map (visit parameters) arguments in
             let declaration = Env.find_type path env in
             let parameters = List.combine (List.map get_id declaration.type_params) arguments in
             let visit = visit parameters in
             let key = name ^ "[" ^ String.concat ";" (List.map shape_text arguments) ^ "]" in
             match declaration.type_kind, declaration.type_manifest with
             | Type_abstract, Some manifest -> visit manifest
             | Type_record (fields, _), _ -> register key (fun () ->
                 Record (module_name path, List.map (fun field -> label field, visit field.ld_type) (order_named label fields)))
             | Type_variant (cases, _), _ -> register key (fun () ->
                 Variant (module_name path, List.map (fun case ->
                   let items = match case.cd_args, case.cd_res with
                     | Cstr_tuple items, None -> items
                     | _ -> fail ("unsupported constructor " ^ name ^ "." ^ constructor case) in
                   constructor case, List.map visit items) (order_named constructor cases)))
             | _ -> fail ("opaque or non-data type " ^ name)
         with Failure message -> failwith (message ^ "\n  in " ^ name))
    | _ -> fail ("unsupported type " ^ Format.asprintf "%a" Printtyp.type_expr ty)
  in
  let root = visit [] root in
  root, Array.init (Hashtbl.length nodes) (Hashtbl.find nodes)

let variables items = List.mapi (fun index item -> "value" ^ string_of_int index, item) items
let tuple names = match names with [] -> "()" | [name] -> name | _ -> "(" ^ String.concat ", " names ^ ")"
let sequence = function [] -> "()" | values -> String.concat "; " values
let ctor owner name args = owner ^ "." ^ name ^ (if args = [] then "" else " " ^ tuple args)
let qualified owner name = owner ^ "." ^ name

let rec codec_name direction = function
  | Primitive name -> "Wire." ^ direction ^ "_" ^ name
  | List item -> "(Wire." ^ direction ^ "_list " ^ codec_name direction item ^ ")"
  | Option item -> "(Wire." ^ direction ^ "_option " ^ codec_name direction item ^ ")"
  | Ref index -> direction ^ "_" ^ string_of_int index
  | Tuple items ->
      let items = variables items in
      let pattern = tuple (List.map fst items) in
      if direction = "write" then
        "(fun output " ^ pattern ^ " -> " ^ sequence (List.map (fun (name, item) -> codec_name "write" item ^ " output " ^ name) items) ^ ")"
      else
        "(fun reader -> " ^ String.concat "" (List.map (fun (name, item) -> "let " ^ name ^ " = " ^ codec_name "read" item ^ " reader in ") items) ^ pattern ^ ")"

let conjunction = function [] -> "true" | tests -> String.concat " && " tests

let rec comparison = function
  | Primitive name -> "Wire.same_" ^ name
  | List item -> "(Wire.same_list " ^ comparison item ^ ")"
  | Option item -> "(Wire.same_option " ^ comparison item ^ ")"
  | Ref index -> "same_" ^ string_of_int index
  | Tuple items ->
      let left, right = List.mapi (fun index _ -> "left" ^ string_of_int index) items,
        List.mapi (fun index _ -> "right" ^ string_of_int index) items in
      "(fun " ^ tuple left ^ " " ^ tuple right ^ " -> " ^
      conjunction (List.map2 (fun item (a, b) -> comparison item ^ " " ^ a ^ " " ^ b)
        items (List.combine left right)) ^ ")"

let adapter_functions version =
  let _, (_, encode, decode) = List.find (fun (_, (candidate, _, _)) -> candidate = version) adapters in
  encode, decode

let write_body = function
  | Record (owner, fields) -> sequence (List.map (fun (name, item) -> codec_name "write" item ^ " output value." ^ qualified owner name) fields)
  | Variant (owner, cases) -> "match value with\n" ^ String.concat "\n" (List.mapi (fun index (name, items) ->
      let items = variables items in
      "  | " ^ ctor owner name (List.map fst items) ^ " -> " ^
      sequence (("Wire.write_length output " ^ string_of_int index) ::
        List.map (fun (name, item) -> codec_name "write" item ^ " output " ^ name) items)) cases)
  | Adapter (version, shape) -> let encode, _ = adapter_functions version in
      codec_name "write" shape ^ " output (" ^ encode ^ " value)"

let read_values items tail =
  String.concat "" (List.map (fun (name, item) -> "let " ^ name ^ " = " ^ codec_name "read" item ^ " reader in ") items) ^ tail
let read_body = function
  | Record (owner, fields) ->
      let items = variables (List.map snd fields) in
      let assignments = List.map2 (fun (field, _) (value, _) -> qualified owner field ^ " = " ^ value) fields items in
      read_values items ("{ " ^ String.concat "; " assignments ^ " }")
  | Variant (owner, cases) -> "match Wire.read_length reader with\n" ^ String.concat "\n" (List.mapi (fun index (name, items) ->
      let items = variables items in
      "  | " ^ string_of_int index ^ " -> " ^ read_values items (ctor owner name (List.map fst items))) cases)
      ^ "\n  (* DEFENSE: An unknown tag cannot select a constructor in this version. *)\n  | _ -> raise Wire.Invalid_state"
  | Adapter (version, shape) -> let _, decode = adapter_functions version in
      "match " ^ decode ^ " (" ^ codec_name "read" shape ^ " reader) with Some value -> value | None -> raise Wire.Invalid_state"

let same_body shape =
  let compare = match shape with
  | Record (owner, fields) -> conjunction (List.map (fun (name, item) ->
      let field = qualified owner name in comparison item ^ " left." ^ field ^ " right." ^ field) fields)
  | Variant (owner, cases) ->
      let paired (name, items) =
        let names prefix = List.mapi (fun index _ -> prefix ^ string_of_int index) items in
        let left = names "a" and right = names "b" in
        "| " ^ ctor owner name left ^ ", " ^ ctor owner name right ^ " -> " ^
        conjunction (List.map2 (fun item (a, b) -> comparison item ^ " " ^ a ^ " " ^ b)
          items (List.combine left right)) in
      "match left, right with " ^ String.concat " " (List.map paired cases) ^
      (if List.length cases = 1 then "" else " | _ -> false")
  | Adapter (version, shape) ->
      let encode, _ = adapter_functions version in
      comparison shape ^ " (" ^ encode ^ " left) (" ^ encode ^ " right)" in
  "left == right || (" ^ compare ^ ")"

let schema_text = function
  | Record (_, fields) -> "record " ^ String.concat "," (List.map (fun (name, item) -> name ^ ":" ^ shape_text item) fields)
  | Variant (_, cases) -> "variant " ^ String.concat "," (List.map (fun (name, items) -> name ^ shape_text (Tuple items)) cases)
  | Adapter (version, shape) -> "adapter " ^ version ^ " " ^ shape_text shape

let write_file filename write =
  let output = open_out filename in
  Fun.protect ~finally:(fun () -> close_out output) (fun () -> write output)

let world_fields root nodes =
  match root with
  | Ref index -> (match nodes.(index) with
      | Record (owner, fields) -> owner, fields
      | _ -> fail "kernel world is not a record")
  | _ -> fail "kernel world has no record declaration"

let () =
  let directory = Sys.argv.(1) and zarith = Sys.argv.(2) in
  Clflags.include_dirs := [directory; zarith];
  Compmisc.init_path ();
  let env = Compmisc.initial_env () in
  let root, nodes = derive env (lookup env (Sys.argv.(3) ^ ".selvedge_kernel_initial")) in
  let owner, fields = world_fields root nodes in
  let task = match List.assoc "world_tasks" fields with
    | List item -> item
    | _ -> fail "kernel tasks are not an indexed list" in
  let task_owner, task_fields = world_fields task nodes in
  let history = List.assoc "task_history" task_fields in
  let metadata = List.remove_assoc "task_history" task_fields in
  let feature_owner, feature_fields = world_fields (List.assoc "world_features" fields) nodes in
  let feature_prefix = qualified owner "world_features" ^ "." in
  let shared = List.filter (fun (name, _) ->
    not (List.mem name ["world_tasks"; "world_sequence"; "world_features"])) fields in
  let sections = List.map (fun (name, shape) -> qualified owner name, shape) shared
    @ List.map (fun (name, shape) -> feature_prefix ^ qualified feature_owner name, shape) feature_fields in
  write_file (Filename.concat directory "state-shape.txt") (fun output ->
    Printf.fprintf output "selvedge-state-wire-2 %s\n" (shape_text root);
    Printf.fprintf output "task metadata %s\ntask history %s\n"
      (schema_text (Record (task_owner, metadata))) (shape_text history);
    List.iter (fun (name, shape) -> Printf.fprintf output "section %s %s\n" name (shape_text shape)) sections;
    Array.iteri (fun index node -> Printf.fprintf output "%d %s\n" index (schema_text node)) nodes);
  write_file (Filename.concat directory "stored_state.ml") (fun output ->
    Printf.fprintf output "(* Generated from the extracted kernel world. *)\nmodule Wire = State_wire\n";
    let emit direction arguments body = Array.iteri (fun index node ->
      Printf.fprintf output "%s %s_%d %s = %s\n" (if index = 0 then "let rec" else "and") direction index arguments (body node)) nodes in
    emit "write" "output value" write_body;
    emit "read" "reader" read_body;
    emit "same" "left right" same_body;
    Printf.fprintf output "let same_world = %s\nlet same_task = %s\n" (comparison root) (comparison task);
    Printf.fprintf output "let same_publication_dependencies left right = %s\n"
      (conjunction (List.map (fun name ->
        let field = feature_prefix ^ qualified feature_owner name in
        comparison (List.assoc name feature_fields) ^ " left." ^ field ^ " right." ^ field)
        ["feature_titles"; "feature_task_owners"]));
    Printf.fprintf output "let feature_matches name before = match name with\n";
    List.iter (fun (name, shape) ->
      let field = feature_prefix ^ qualified feature_owner name in
      Printf.fprintf output "  | %S -> let previous = before.%s in fun current -> %s previous current.%s\n"
        name field (comparison shape) field) feature_fields;
    Printf.fprintf output "  | _ -> invalid_arg \"Unknown feature in publication dependencies\"\n";
    Printf.fprintf output "let tasks value = value.%s\nlet sequence value = value.%s\n"
      (qualified owner "world_tasks") (qualified owner "world_sequence");
    List.iter (fun (function_name, name) ->
      let field = qualified owner name in
      Printf.fprintf output "let %s left right = %s left.%s right.%s\n"
        function_name (comparison (List.assoc name fields)) field field)
      ["same_environment", "world_environment"; "same_projects", "world_projects"];
    Printf.fprintf output "let task_lineage value = value.%s\n" (qualified task_owner "task_lineage");
    Printf.fprintf output "let task_history value = value.%s\n" (qualified task_owner "task_history");
    Printf.fprintf output "let encode write value = let output = Buffer.create 4_096 in write output value; Buffer.contents output\n";
    Printf.fprintf output "let decode_exn read bytes =\n  let reader = Wire.start bytes in\n  let value = read reader in\n  (* DEFENSE: Trailing bytes cannot belong to the stored record. *)\n  if Wire.remaining reader = 0 then value else raise Wire.Invalid_state\n";
    Printf.fprintf output "let encode_task_metadata = encode (fun output value -> %s)\n"
      (write_body (Record (task_owner, metadata)));
    Printf.fprintf output "let encode_history = encode %s\nlet decode_history_exn = decode_exn %s\n"
      (codec_name "write" history) (codec_name "read" history);
    let items = variables (List.map snd metadata) in
    let assignments = List.map2 (fun (field, _) (name, _) -> qualified task_owner field ^ " = " ^ name)
      metadata items in
    let assignments = (qualified task_owner "task_history" ^ " = history") :: assignments in
    Printf.fprintf output "let decode_task_exn bytes history = decode_exn (fun reader -> %s) bytes\n"
      (read_values items ("{ " ^ String.concat "; " assignments ^ " }"));
    Printf.fprintf output "let shared_writes before value =\n  let updates = ref [] in\n";
    List.iteri (fun id (name, shape) ->
      Printf.fprintf output
        "  (match before with Some previous when %s previous.%s value.%s -> ()\n   | _ -> updates := (%d, encode %s value.%s) :: !updates);\n"
        (comparison shape) name name id (codec_name "write" shape) name) sections;
    Printf.fprintf output "  List.rev !updates\n";
    Printf.fprintf output "let restore_exn sections ~sequence ~tasks =\n";
    Printf.fprintf output "  (* DEFENSE: A truncated or additional section cannot reconstruct this world. *)\n";
    Printf.fprintf output "  if Array.length sections <> %d then raise Wire.Invalid_state;\n" (List.length sections);
    List.iteri (fun id (_, shape) -> Printf.fprintf output "  let value%d = decode_exn %s sections.(%d) in\n"
      id (codec_name "read" shape) id) sections;
    let assignments_for owner offset fields =
      List.mapi (fun index (name, _) -> Printf.sprintf "%s = value%d" (qualified owner name) (offset + index)) fields in
    let features = "{ " ^ String.concat "; " (assignments_for feature_owner (List.length shared) feature_fields) ^ " }" in
    let assignments = (qualified owner "world_tasks" ^ " = tasks") ::
      (qualified owner "world_sequence" ^ " = sequence") ::
      (qualified owner "world_features" ^ " = " ^ features) :: assignments_for owner 0 shared in
    Printf.fprintf output "  { %s }\n" (String.concat "; " assignments))
