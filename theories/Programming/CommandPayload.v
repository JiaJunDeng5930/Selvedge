From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema Arguments.

(** A proposal retains the wire shape needed by editors; an admitted payload
    retains the declaration's values. Only admitted values reach execution. *)
Record t (shape : schema) (declaration : list argument_spec) (admitted : bool) := Payload {
 values : if admitted then parsed_arguments declaration else fields shape
}.
Arguments Payload {shape declaration admitted}.
Arguments values {shape declaration admitted}.
Definition admit {shape declaration} (value : parsed_arguments declaration) : t shape declaration true := @Payload shape declaration true value.
Definition propose {shape declaration} (value : fields shape) : t shape declaration false := @Payload shape declaration false value.
Definition encode {declaration admitted} (command : command_spec)
 : t (command_fields command) declaration admitted -> json :=
 match admitted as admitted return t (command_fields command) declaration admitted -> json with
 | true => fun payload => encode_arguments declaration (values payload)
 | false => fun payload => encode_declared command (values payload)
 end.
