From Selvedge.Foundation Require Import RequestEnvelope Receiver Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
From Selvedge.Features Require Import Domain.

(** An external request retains its typed input. The effect carries this same
    instance; protocol declarations cannot manufacture another effect or choose
    its correlation identity. Only protocol-specific wire data is supplied. *)
Record declaration (payload location : Type) := Protocol {
 receiver : location;
 wire : ModelDeclarations.request_variant;
 body : payload -> state -> Schema.fields (ModelDeclarations.request_body_fields wire)
}.
Arguments Protocol {payload location}.
Arguments receiver {payload location}.
Arguments wire {payload location}.
Arguments body {payload location}.
Definition protocol payload := declaration payload (Receiver.t state (RequestEnvelope.t payload)).
Definition located payload before := declaration payload (Receiver.located state (RequestEnvelope.t payload) before).
Definition release {payload before} (selected : located payload before) : protocol payload :=
 Protocol (Receiver.path (receiver selected)) (wire selected) (body selected).
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
 ModelDeclarations.Packet (ModelDeclarations.request_variant_view declaration)
   (ModelDeclarations.request_fields declaration
     (Receiver.address (receiver (definition sent)) (request sent)) (RequestEnvelope.identity (request sent))
     (body (definition sent) (RequestEnvelope.input (request sent)) current)).
