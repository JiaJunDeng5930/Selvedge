From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require Import Schema.
From Selvedge.Programming Require ArgumentDeclaration.
From Selvedge.Foundation Require Numbers.
From Selvedge.Kernel Require Import WorkspaceBackend.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.

Definition required_settings_text : list string :=
  ["region";"zone";"image_id";"instance_type";"vpc_id";"subnet_id";
   "key_id";"ssh_private_key";"spot_max_price"].
Definition optional_settings_text : list string := ["ssh_user";"api_endpoint"].
Definition optional_bounds : list (string * (N*N)) :=
  [("ssh_port",(1,65535));("internet_max_bandwidth_out",(0,1000));
   ("startup_timeout_ms",(1000,3600000))].
Definition setting_label name :=
  match name with
  | "region" => "Region" | "zone" => "Zone" | "image_id" => "Image ID"
  | "instance_type" => "Instance type" | "spot_max_price" => "Maximum spot price"
  | "vpc_id" => "VPC ID" | "subnet_id" => "Subnet ID"
  | "security_group_ids" => "Security groups" | "key_id" => "SSH key ID"
  | "ssh_private_key" => "Private key path" | "ssh_user" => "SSH user"
  | "ssh_port" => "SSH port" | "address_type" => "Address type"
  | "api_endpoint" => "API endpoint override"
  | "internet_max_bandwidth_out" => "Outbound bandwidth (Mbps)"
  | "startup_timeout_ms" => "Startup timeout (ms)"
  | _ => name
  end.
Definition nonempty_text := D.Text (D.TextConstraints
  1 D.maximum_natural D.maximum_natural false false false None).
Definition settings_fields :=
  (map (fun name => (name,true,nonempty_text)) required_settings_text ++
  [("security_group_ids",true,D.BoundedArray 1 D.maximum_natural nonempty_text)] ++
  map (fun name => (name,false,nonempty_text)) optional_settings_text ++
  map (fun entry => (fst entry,false,D.Natural (fst (snd entry)) (snd (snd entry)))) optional_bounds ++
  [("address_type",false,D.of_kind (KEnum "public" ["private"]))])%list.
Definition settings_declaration := D.Object settings_fields.
Definition recovery_settings_names := ["api_endpoint";"ssh_private_key";"ssh_user";"ssh_port"].
Definition recovery_settings_declaration := D.Object
  (filter (fun entry => existsb (String.eqb (fst (fst entry))) recovery_settings_names) settings_fields).
Definition retained_settings (settings : json) := JObject
  (filter (fun entry => existsb (String.eqb (fst entry)) recovery_settings_names) (object_fields settings)).
Definition declaration := D.Object
  [("backend",true,D.Const (JString (WorkspaceBackend.name WorkspaceBackend.TencentCvm)));
   (WorkspaceBackend.name WorkspaceBackend.TencentCvm,true,settings_declaration)].
Definition admit := D.decode declaration.
Definition encode := D.encode declaration.
Definition disabled (value : json) := is_null value || equal value (JBool false).

(* Keep admission authoritative. On rejection, the same field declarations
   identify the first field the user can correct. *)
Definition setting_invalid fields (entry : string * bool * D.t) :=
  let '(name, required, kind) := entry in
  match lookup name fields with
  | None => required
  | Some value => match D.decode kind value with None => true | Some _ => false end
  end.
Definition setting_problem fields name :=
  match find (fun entry => String.eqb (fst entry) name) optional_bounds with
  | Some (_, (minimum, maximum)) =>
      (setting_label name ++ " must be between " ++ Numbers.show_natural minimum ++
        " and " ++ Numbers.show_natural maximum ++ ".")%string
  | None => match name with
    | "security_group_ids" => "Enter at least one security group ID."
    | "address_type" => "Choose Public or Private for Address type."
    | _ => match lookup name fields with
      | None | Some (JString "") => ("Enter a value for " ++ setting_label name ++ ".")%string
      | Some _ => ("Check the value for " ++ setting_label name ++ ".")%string
      end
    end
  end.
Definition configuration_problem value :=
  let backend := WorkspaceBackend.name WorkspaceBackend.TencentCvm in
  if equal (get value "backend") (JString backend) then
    let fields := object_fields (get value backend) in
    match find (setting_invalid fields) settings_fields with
    | Some (name, _, _) => setting_problem fields name
    | None => "Check for unsupported Tencent Cloud workspace settings."
    end
  else "Choose Tencent Cloud as the workspace backend.".

Definition call (source : json) :=
  let value := get source "cloud" in
  if disabled value then success (JBool false)
  else match admit value with
  | Some configured => success (encode configured)
  | None => type_error (configuration_problem value) end.

Definition require_cloud (source : json) :=
  let value := get source "cloud" in
  match admit value with Some configured =>
    let configured := encode configured in
    success (set configured "retained_settings"
      (retained_settings (get configured (WorkspaceBackend.name WorkspaceBackend.TencentCvm))))
  | None => type_error "Cloud workspace backend is not configured" end.
