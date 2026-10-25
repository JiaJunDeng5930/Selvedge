From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain NativeTools ToolArguments.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(* A misspelled command binding must fail checking instead of silently removing
   a builtin through binding_entry's failed command lookup. *)
Theorem native_catalog_contains_every_declared_tool : forall maximum,
 map Domain.tool_name (NativeTools.catalog maximum) =
 "discover_tools" :: map ToolArguments.tool_name [Bash;ReadProcess;WriteProcess;ReadImage] ++
 map NativeTools.binding_tool NativeTools.bindings.
Proof. intros; reflexivity. Qed.
