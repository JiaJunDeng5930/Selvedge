From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Browser Require DOM.
Import ListNotations.
Open Scope string_scope.

(** Interpret the typed DOM directly with native constructors. The element
    description contains only its own properties and bindings. Its children
    are native handles, never serialized descendants. *)
Record algebra (native : Type) := Algebra {
  text_node : string -> native;
  element_node : string -> json -> list native -> native;
  markdown_node : json -> native;
  mount_nodes : string -> list native -> native
}.
Arguments text_node {native}.
Arguments element_node {native}.
Arguments markdown_node {native}.
Arguments mount_nodes {native}.

Fixpoint materialize {native} (operations : algebra native) (path : string) (node : DOM.node) : native :=
  let children_at (key : string) := fix visit (children : list DOM.node) (index : nat) :=
    match children with
    | [] => []
    | child :: rest => materialize operations (key ++ "/" ++ show_nat index) child :: visit rest (S index)
    end in
  match node with
  | DOM.Text value => text_node operations value
  | DOM.Element key tag attributes styles events metadata children =>
    let identity := if String.eqb key "" then path else key in
    element_node operations identity
      (DOM.element_description key tag attributes styles events metadata)
      (children_at identity children 0)
  | DOM.Markdown key value complete metadata =>
    markdown_node operations (DOM.markdown_description key value complete metadata)
  | DOM.Mount target children => mount_nodes operations target (children_at target children 0)
  end.

Definition materialize_roots {native : Type}
    (text : string -> native) (element : string -> json -> list native -> native)
    (markdown : json -> native) (mount : string -> list native -> native)
    (roots : list DOM.node) : list native :=
  let operations := Algebra native text element markdown mount in
  match roots with
  | [root] => [materialize operations "@root" root]
  | _ => map (fun '(index, root) => materialize operations ("@root/" ++ show_nat index) root)
      (combine (seq 0 (List.length roots)) roots)
  end.
