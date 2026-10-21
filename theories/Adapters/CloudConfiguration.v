From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Schema.
From Selvedge.Kernel Require Import WorkspaceBackend.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition required_settings_text : list string :=
  ["region";"zone";"image_id";"instance_type";"vpc_id";"subnet_id";
   "key_id";"ssh_private_key";"spot_max_price"].
Definition optional_settings_text : list string := ["ssh_user";"api_endpoint"].
Definition optional_bounds : list (string * (N*N)) :=
  [("ssh_port",(1,65535));("internet_max_bandwidth_out",(0,1000));
   ("startup_timeout_ms",(1000,3600000))].
Definition settings_schema : Schema.schema :=
  (map (fun name => Field name KText) required_settings_text ++
  [Field "security_group_ids" (KArray KText)] ++
  map (fun name => Field name (KOptional KText)) optional_settings_text ++
  map (fun entry => Field (fst entry) (KOptional KNatural)) optional_bounds ++
  [Field "address_type" (KOptional (KEnum "public" ["private"]))])%list.
Definition cloud_schema : Schema.schema :=
  [Field "backend" WorkspaceBackend.declaration;
   Field (WorkspaceBackend.name WorkspaceBackend.TencentCvm) KJson].
Definition nonempty_text (value : json) :=
  is_text value && negb (String.eqb (text value) "").
Definition bounded_natural (value : json) (lower upper : N) :=
  match natural value with Some n => (lower <=? n) && (n <=? upper) | None => false end.
Definition settings_valid (source : json) :=
  match Schema.decode settings_schema source with
  | None => false
  | Some _ =>
    forallb (fun name => nonempty_text (get source name)) required_settings_text &&
    forallb (fun name => negb (has source name) || nonempty_text (get source name)) optional_settings_text &&
    negb (Nat.eqb (List.length (items (get source "security_group_ids"))) 0%nat) &&
    forallb nonempty_text (items (get source "security_group_ids")) &&
    forallb (fun entry => negb (has source (fst entry)) ||
      bounded_natural (get source (fst entry)) (fst (snd entry)) (snd (snd entry))) optional_bounds &&
    (negb (has source "address_type") || negb (is_null (get source "address_type")))
  end.
Definition valid (source : json) :=
  match Schema.decode cloud_schema source with
  | None => false
  | Some _ => String.eqb (str source "backend") (WorkspaceBackend.name WorkspaceBackend.TencentCvm) &&
    settings_valid (get source (WorkspaceBackend.name WorkspaceBackend.TencentCvm))
  end.
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
