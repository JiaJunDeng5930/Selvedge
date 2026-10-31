From Selvedge.Programming Require Variant.
From Selvedge.Programming Require Import RequestEnvelope Receiver Schema.
From Selvedge.Features Require Import Domain.

(** An external request retains its typed input. The effect carries this same
    instance; protocol declarations cannot manufacture another effect or choose
    its correlation identity. Only protocol-specific wire data is supplied. *)
Inductive lifetime := Independent | TaskBound.
Record declaration (payload location : Type) := Declare {
 receiver : location;
 wire : Variant.request_variant;
 body : payload -> state -> Schema.fields (Variant.request_body_fields wire);
 request_lifetime : lifetime
}.
Arguments Declare {payload location}.
Arguments receiver {payload location}.
Arguments wire {payload location}.
Arguments body {payload location}.
Arguments request_lifetime {payload location}.
Definition Protocol {payload location} selected operation
 (fields : payload -> state -> Schema.fields (Variant.request_body_fields operation))
 : declaration payload location := Declare selected operation fields Independent.
Definition task_bound {payload location} (protocol : declaration payload location) :=
 Declare (receiver protocol) (wire protocol) (body protocol) TaskBound.
Definition protocol payload := declaration payload (Receiver.t state (RequestEnvelope.t payload)).
Definition located payload before := declaration payload (Receiver.located state (RequestEnvelope.t payload) before).
Definition release {payload before} (selected : located payload before) : protocol payload :=
 Declare (Receiver.path (receiver selected)) (wire selected) (body selected) (request_lifetime selected).
Record packet := Packet {
 payload : Type;
 definition : protocol payload;
 request : RequestEnvelope.t payload
}.
Arguments Packet {payload}.
Definition install (sent : packet) (before : state) :=
 Receiver.install (receiver (definition sent)) (request sent) before.
Definition encode_packet (sent : packet) (current : state) :=
 let declaration := wire (definition sent) in
 Variant.Packet (Variant.request_variant_view declaration)
   (Variant.request_fields declaration
     (Receiver.address (receiver (definition sent)) (request sent)) (RequestEnvelope.identity (request sent))
     (body (definition sent) (RequestEnvelope.input (request sent)) current)).
