From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Schema.
From Selvedge.Foundation Require ArgumentDeclaration.
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
Definition nonempty_text := D.Text (D.TextConstraints
  1 D.maximum_natural D.maximum_natural false false false None).
Definition settings_declaration := D.Object
  (map (fun name => (name,true,nonempty_text)) required_settings_text ++
  [("security_group_ids",true,D.BoundedArray 1 D.maximum_natural nonempty_text)] ++
  map (fun name => (name,false,nonempty_text)) optional_settings_text ++
  map (fun entry => (fst entry,false,D.Natural (fst (snd entry)) (snd (snd entry)))) optional_bounds ++
  [("address_type",false,D.of_kind (KEnum "public" ["private"]))])%list.
Definition declaration := D.Object
  [("backend",true,D.of_kind (KEnum (WorkspaceBackend.name WorkspaceBackend.TencentCvm) []));
   (WorkspaceBackend.name WorkspaceBackend.TencentCvm,true,settings_declaration)].
Definition valid := D.check declaration.
Definition disabled (value : json) := is_null value || equal value (JBool false).
Definition call (source : json) :=
  let value := get source "cloud" in
  if disabled value then success (JBool false)
  else if valid value then success value
  else type_error "cloud requires backend tencent_cvm and complete CVM, network, SSH key and spot_max_price settings; credentials belong in the service environment".

Definition require_cloud (source : json) :=
  let value := get source "cloud" in
  if valid value then success value
  else type_error "Cloud workspace backend is not configured".
