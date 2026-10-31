From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Programming Require Callback DeclarationFields DeclarationRegistry SchemaProjection.
From Selvedge.Foundation Require TextJson.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition callback_coordinates (callback : option Callback.callback_kind) :=
 match callback with Some kind => Callback.coordinates kind | None => [] end.

(** The public discriminant, payload and callback ownership are one declaration. *)
Record variant := BuildVariant {
 tag_field : string; tag_value : json; payload_fields : schema;
 safe_fields : list string; callback_name : option Callback.callback_kind;
 variant_unique : unique_names (tag_field :: map field_name payload_fields) = true;
 callback_projection : SchemaProjection.program payload_fields (callback_coordinates callback_name)
}.
Definition declare_variant tag value body safe callback
 `{DistinctNames (tag :: map field_name body)}
 `{SchemaProjection.Available body (callback_coordinates callback)} :=
 BuildVariant tag value body safe callback names_distinct (SchemaProjection.declare body (callback_coordinates callback)).
Definition effect name body callback `{DistinctNames ("kind" :: map field_name body)}
 `{SchemaProjection.Available body (callback_coordinates callback)} :=
 declare_variant "kind" (JString name) body [] callback.
Definition from_branch (branch : DeclarationFields.branch) (safe : list string)
 (callback : option Callback.callback_kind)
 `{SchemaProjection.Available (DeclarationFields.shape (DeclarationFields.payload_fields branch)) (callback_coordinates callback)} : variant.
Proof.
 refine (BuildVariant (DeclarationFields.tag_field branch) (DeclarationFields.tag_value branch)
   (DeclarationFields.shape (DeclarationFields.payload_fields branch)) safe callback _ (SchemaProjection.declare _ _)).
 rewrite DeclarationFields.shape_names; exact (DeclarationFields.branch_distinct branch).
Defined.
Definition variant_key (declaration : variant) := TextJson.render_json (tag_value declaration).
(** Correlation coordinates are language-owned fields. Protocol declarations
    supply only their body; encoding always takes the coordinates from the
    installed request instance. *)
Inductive correlation := OwnedTicket (owner_field : string) | StandaloneIdentity (identity_field : string).
Definition correlation_fields (shape : correlation) := match shape with
 | OwnedTicket owner => [Field owner KNatural; Field "ticket" KNatural]
 | StandaloneIdentity identity => [Field identity KNatural] end.
Record request_variant := BuildRequestVariant {
 request_name : string;
 request_correlation : correlation;
 request_body : schema;
 request_callback : Callback.callback_kind;
 request_unique : unique_names ("kind" :: map field_name (correlation_fields request_correlation ++ request_body)) = true;
 request_projection : SchemaProjection.program (correlation_fields request_correlation)
   (Callback.coordinates request_callback)
}.
Definition declare_request name shape body callback
 `{DistinctNames ("kind" :: map field_name (correlation_fields shape ++ body))}
 `{SchemaProjection.Available (correlation_fields shape) (Callback.coordinates callback)} :=
 BuildRequestVariant name shape body callback names_distinct
   (SchemaProjection.declare (correlation_fields shape) (Callback.coordinates callback)).
Definition request_body_fields (request : request_variant) := request_body request.
Definition request_variant_view (request : request_variant) :=
 BuildVariant "kind" (JString (request_name request))
   (correlation_fields (request_correlation request) ++ request_body_fields request)
   [] (Some (request_callback request)) (request_unique request)
   (SchemaProjection.prefix (request_body request) (request_projection request)).
Definition request_fields (request : request_variant) (owner identity : N)
 (body : fields (request_body_fields request))
 : fields (payload_fields (request_variant_view request)) :=
 match request_correlation request as shape
   return fields (correlation_fields shape ++ request_body_fields request) with
 | OwnedTicket name => @FCons (Field name KNatural)
     (Field "ticket" KNatural :: request_body_fields request) owner
     (@FCons (Field "ticket" KNatural) (request_body_fields request) identity body)
 | StandaloneIdentity name => @FCons (Field name KNatural) (request_body_fields request) identity body end.
Definition encode (declaration : variant) (values : fields declaration.(payload_fields)) :=
 JObject ((declaration.(tag_field),declaration.(tag_value)) :: encode_fields values).
Record packet := Packet { packet_declaration : variant; packet_fields : fields (payload_fields packet_declaration) }.
Definition pack declaration (values : Schema.tuple (payload_fields declaration)) :=
 Packet declaration (Schema.of_tuple _ values).
Definition encode_packet value := encode (packet_declaration value) (packet_fields value).
Definition matches declaration source := match Json.field (tag_field declaration) source with
 | Some value => Json.equal value (tag_value declaration) | None => false end.
Definition decode declaration source := match source with
 | JObject members => if matches declaration source then
   Schema.decode (payload_fields declaration) (JObject (Json.remove_field (tag_field declaration) members)) else None
 | _ => None end.
Record decoder (A : Type) := Decoder {
 decoder_declaration : variant; decoder_construct : fields (payload_fields decoder_declaration) -> option A
}.
Arguments Decoder {A} _ _.
Arguments decoder_declaration {A} _.
Arguments decoder_construct {A} _ _.
Definition decode_cases {A} (cases : list (decoder A)) source :=
 match find (fun entry => matches (decoder_declaration entry) source) cases with
 | Some entry => match decode (decoder_declaration entry) source with
   | Some values => decoder_construct entry values | None => None end
 | None => None end.
Fixpoint kind_json (kind : kind) : json := match kind with
 | KText => JString "text" | KBool => JString "boolean" | KNatural => JString "natural"
 | KInteger => JString "integer" | KDecimal => JString "decimal" | KJson => JString "json"
 | KArray item => JObject [("array",kind_json item)]
 | KOptional item => JObject [("optional",kind_json item)]
 | KEnum first rest => JObject [("enum",JArray (map JString (first::rest)))] end.
Definition fields_json (fields : schema) := JArray (map (fun field => JObject [
 ("name",JString field.(field_name));("type",kind_json field.(field_kind));("omittable",JBool field.(field_omittable))]) fields).
Definition variant_json (declaration : variant) := JObject [("tag_field",JString declaration.(tag_field));
 ("tag",declaration.(tag_value));("fields",fields_json declaration.(payload_fields));
 ("safe_fields",JArray (map JString declaration.(safe_fields)));
 ("callback",match declaration.(callback_name) with Some name => JString (Callback.callback_text name) | None => JNull end)].

Definition declare_union (label : string) (entries : list variant)
 `{DistinctNames (map variant_key entries)} :=
 (label,DeclarationRegistry.declare variant_key entries).
