From Stdlib Require Import String NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction Require CardDecisions.
From Selvedge.Interaction.Experience Require Read.
Open Scope string_scope.

Inductive request :=
| Information (subject : Read.observation_request)
| CardChoices (card : N).

Definition decode_request (source : json) : option request :=
 if String.eqb (text "kind" source) "card-decisions"
 then option_map CardChoices (natural_field "id" source)
 else option_map Information (Read.decode_request source).

Definition observe (snapshot : json) (selection : request) : option json :=
 match selection with
 | Information subject => Read.describe snapshot subject
 | CardChoices card =>
   option_map CardDecisions.encode_opportunity (CardDecisions.observe snapshot card)
 end.
