From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Browser Require DOM.
Import ListNotations.

(** Interpret the typed DOM directly with native constructors. The element
    description contains only its own properties and bindings. Its children
    are native handles, never serialized descendants. *)
Record algebra (native : Type) := Algebra {
  text_node : string -> native;
  element_node : json -> list native -> native;
  markdown_node : json -> native;
  mount_nodes : string -> list native -> native
}.
Arguments text_node {native}.
Arguments element_node {native}.
Arguments markdown_node {native}.
Arguments mount_nodes {native}.

Fixpoint materialize {native} (operations : algebra native) (node : DOM.node) : native :=
  match node with
  | DOM.Text value => text_node operations value
  | DOM.Element key tag attributes styles events metadata children =>
    element_node operations
      (DOM.encode_node (DOM.Element key tag attributes styles events metadata []))
      (map (materialize operations) children)
  | DOM.Markdown key value complete metadata =>
    markdown_node operations (DOM.encode_node (DOM.Markdown key value complete metadata))
  | DOM.Mount target children => mount_nodes operations target (map (materialize operations) children)
  end.

Definition materialize_roots {native : Type}
    (text : string -> native) (element : json -> list native -> native)
    (markdown : json -> native) (mount : string -> list native -> native)
    (roots : list DOM.node) : list native :=
  map (materialize (Algebra native text element markdown mount)) roots.
