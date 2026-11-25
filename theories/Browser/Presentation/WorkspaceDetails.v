From Stdlib Require Import String List.
From Selvedge.Kernel Require Domain.
From Selvedge.Interaction.Experience Require Model.
From Selvedge.Browser.Session Require Input.
From Selvedge.Browser.Scene Require Import Surface Construction.
From Selvedge.Browser.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.
Module UX := Selvedge.Interaction.Experience.Model.

Definition directory_details parent identity label path : node Input.input :=
 let key:=part parent identity in
 region key "directory-path-entry" "" Roles.Content
   [Node key "directory-path" (label++" · "++UX.directory_basename path) Roles.Content ContentDisclosure
     [Node (part key "path") "directory-path-value" "" Roles.Content (Fact path) []];
    declared key Roles.Button(secondary "copy-path" ("复制"++label++"路径")(Input.CopyPath path))].
Definition workspace_directory_details parent single_label workspace : list (node Input.input) :=
 let roots:=Domain.workspace_roots workspace in
 match roots with
 |[]=>[information parent "working-directory" Information.Description "未设置工作目录"]
 |[path]=>[directory_details parent "working-directory" single_label path]
 |_=>[region parent "workspace-directories" "" Roles.Content
   (map (fun path=>directory_details parent ("directory/"++path)
      (match Domain.workspace_primary workspace with
       |Some primary=>if String.eqb primary path then "主目录" else "附加目录"
       |None=>"附加目录" end) path) roots)]
 end.
