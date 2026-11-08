From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction Require CardDecisions ObjectDecisions.
From Selvedge.Interaction.Experience Require Read.
Open Scope string_scope.

Inductive request :=
| Information (subject : Read.observation_request)
| ObjectChoices (subject : object_subject)
| CardChoices (card : N).

Definition decode_request (source : json) : option request :=
 let id := natural_field "id" source in
 let choices kind := option_map (fun value => ObjectChoices (kind value)) id in
 match text "kind" source with
 | "task-actions" => choices TaskActions
 | "project-actions" => choices ProjectActions
 | "card-actions" => choices CardActions
 | "agent-actions" => choices AgentActions
 | "graph-actions" => choices GraphActions
 | "card-decisions" => option_map CardChoices id
 | _ => option_map Information (Read.decode_request source)
 end.

Definition observe (snapshot : json) (clock : option N) (selection : request) : option json :=
 match selection with
 | Information subject => Read.describe snapshot subject
 | ObjectChoices subject =>
   if ObjectDecisions.subject_exists snapshot subject then
     let choices := ObjectDecisions.decisions snapshot clock subject in
     let reading := match subject with
       | TaskActions task => ObjectDecisions.reading_decisions snapshot task
       | _ => nil
       end in
     Some (Read.encode_list ObjectDecisions.encode_decision (choices ++ reading)%list)
   else None
 | CardChoices card =>
   option_map CardDecisions.encode_opportunity (CardDecisions.observe snapshot card)
 end.
