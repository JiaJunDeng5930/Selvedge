From Stdlib Require Import Ascii String List Bool.
From Selvedge.Foundation Require TextJson.
Import ListNotations.
Open Scope string_scope.

Definition native_symbols : list (string * string) := [
 ("read_process","scroll-text"); ("write_process","keyboard"); ("read_image","image");
 ("discover_tools","binoculars"); ("create_task","file-plus-2");
 ("fork_task","git-pull-request-create"); ("search_history","history"); ("read_task","notebook-text");
 ("read_current_task","scan-text"); ("send_message_to_task","send-horizontal");
 ("archive_task","archive"); ("cancel_operation","circle-stop");
 ("choose_workflow_connection","route"); ("create_task_graph","network");
 ("update_task_graph","pencil-ruler"); ("delete_task_graph","unlink");
 ("list_task_graphs","list-ordered"); ("read_task_graph","workflow");
 ("create_work","briefcase-business"); ("rename_work","case-sensitive");
 ("create_work_task","clipboard-plus"); ("list_works","layers-3"); ("read_work","folder-open");
 ("read_work_ui","panels-top-left"); ("apply_work_ui_patch","square-pen")
].

Definition shell_symbols : list (list string * string) := [
 (["ls";"eza"],"list-tree"); (["cat";"head";"tail";"less"],"file-text");
 (["python";"python3"],"braces"); (["git"],"git-branch"); (["cd";"pwd"],"folder-symlink");
 (["rg";"grep";"find"],"search"); (["mkdir"],"folder-plus"); (["cp"],"copy");
 (["mv"],"move"); (["rm"],"trash-2"); (["sed";"awk"],"list-filter");
 (["curl";"wget"],"globe"); (["node";"bun";"deno"],"hexagon");
 (["npm";"pip";"pip3";"brew"],"package"); (["make";"just"],"hammer");
 (["docker";"podman"],"container")
].

(* This reads the first executable token for presentation. It does not
   interpret shell expansions or guess the result of a wrapper command. *)
Fixpoint executable (command:string) (started:bool) (reversed:list ascii) : string :=
 match command with
 | EmptyString => TextJson.finish_string reversed
 | String char rest =>
   if TextJson.whitespace char then
     if started then TextJson.finish_string reversed else executable rest false []
   else if existsb (Ascii.eqb char) [";"%char; "|"%char; "&"%char; "("%char; ">"%char; "<"%char]
   then TextJson.finish_string reversed
   else if Ascii.eqb char "/"%char then executable rest true []
   else executable rest true (char::reversed)
 end.

Definition shell_symbol command :=
 let name:=executable command false [] in
 match find (fun entry=>existsb (String.eqb name) (fst entry)) shell_symbols with
 | Some entry=>snd entry | None=>"terminal" end.

Definition native_symbol name :=
 option_map snd (find (fun entry=>String.eqb (fst entry) name) native_symbols).

(** Lucide 1.17.0 icon artwork in its original 24-unit coordinate system.
    Paths combine the original shapes so the native document renderer can share
    one outline renderer across the two icon sets. Source: https://lucide.dev.

ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

---

The following Lucide icons are derived from the Feather project:


The MIT License (MIT) (for the icons listed above)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*)
Definition paths : list (string * string) := [
 ("archive", "M3 3h18a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1h-18a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1Z M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8 M10 12h4");
 ("binoculars", "M10 10h4 M19 7V4a1 1 0 0 0-1-1h-2a1 1 0 0 0-1 1v3 M20 21a2 2 0 0 0 2-2v-3.851c0-1.39-2-2.962-2-4.829V8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v11a2 2 0 0 0 2 2z M 22 16 L 2 16 M4 21a2 2 0 0 1-2-2v-3.851c0-1.39 2-2.962 2-4.829V8a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v11a2 2 0 0 1-2 2z M9 7V4a1 1 0 0 0-1-1H6a1 1 0 0 0-1 1v3");
 ("braces", "M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1 M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1");
 ("brain", "M12 18V5 M15 13a4.17 4.17 0 0 1-3-4 4.17 4.17 0 0 1-3 4 M17.598 6.5A3 3 0 1 0 12 5a3 3 0 1 0-5.598 1.5 M17.997 5.125a4 4 0 0 1 2.526 5.77 M18 18a4 4 0 0 0 2-7.464 M19.967 17.483A4 4 0 1 1 12 18a4 4 0 1 1-7.967-.517 M6 18a4 4 0 0 1-2-7.464 M6.003 5.125a4 4 0 0 0-2.526 5.77");
 ("briefcase-business", "M12 12h.01 M16 6V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2 M22 13a18.15 18.15 0 0 1-20 0 M4 6h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-16a2 2 0 0 1-2-2v-10a2 2 0 0 1 2-2Z");
 ("case-sensitive", "m2 16 4.039-9.69a.5.5 0 0 1 .923 0L11 16 M22 9v7 M3.304 13h6.392 M22 12.5a3.5 3.5 0 1 1-7 0a3.5 3.5 0 1 1 7 0Z");
 ("circle-stop", "M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0Z M10 9h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z");
 ("clipboard-plus", "M9 2h6a1 1 0 0 1 1 1v2a1 1 0 0 1-1 1h-6a1 1 0 0 1-1-1v-2a1 1 0 0 1 1-1Z M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2 M9 14h6 M12 17v-6");
 ("container", "M22 7.7c0-.6-.4-1.2-.8-1.5l-6.3-3.9a1.72 1.72 0 0 0-1.7 0l-10.3 6c-.5.2-.9.8-.9 1.4v6.6c0 .5.4 1.2.8 1.5l6.3 3.9a1.72 1.72 0 0 0 1.7 0l10.3-6c.5-.3.9-1 .9-1.5Z M10 21.9V14L2.1 9.1 m10 14 11.9-6.9 M14 19.8v-8.1 M18 17.5V9.4");
 ("copy", "M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-10a2 2 0 0 1-2-2v-10a2 2 0 0 1 2-2Z M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2");
 ("file-plus-2", "M11.35 22H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.706.706l3.588 3.588A2.4 2.4 0 0 1 20 8v5.35 M14 2v5a1 1 0 0 0 1 1h5 M14 19h6 M17 16v6");
 ("file-text", "M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z M14 2v5a1 1 0 0 0 1 1h5 M10 9H8 M16 13H8 M16 17H8");
 ("folder-open", "m6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2");
 ("folder-plus", "M12 10v6 M9 13h6 M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z");
 ("folder-symlink", "M2 9.35V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H20a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h7 m8 16 3-3-3-3");
 ("git-branch", "M15 6a9 9 0 0 0-9 9V3 M21 6a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M9 18a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z");
 ("git-pull-request-create", "M9 6a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M6 9v12 M13 6h3a2 2 0 0 1 2 2v3 M18 15v6 M21 18h-6");
 ("globe", "M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0Z M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20 M2 12h20");
 ("hammer", "m15 12-9.373 9.373a1 1 0 0 1-3.001-3L12 9 m18 15 4-4 m21.5 11.5-1.914-1.914A2 2 0 0 1 19 8.172v-.344a2 2 0 0 0-.586-1.414l-1.657-1.657A6 6 0 0 0 12.516 3H9l1.243 1.243A6 6 0 0 1 12 8.485V10l2 2h1.172a2 2 0 0 1 1.414.586L18.5 14.5");
 ("hexagon", "M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z");
 ("history", "M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8 M3 3v5h5 M12 7v5l4 2");
 ("image", "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-14a2 2 0 0 1-2-2v-14a2 2 0 0 1 2-2Z M11 9a2 2 0 1 1-4 0a2 2 0 1 1 4 0Z m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21");
 ("keyboard", "M10 8h.01 M12 12h.01 M14 8h.01 M16 12h.01 M18 8h.01 M6 8h.01 M7 16h10 M8 12h.01 M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-16a2 2 0 0 1-2-2v-12a2 2 0 0 1 2-2Z");
 ("layers-3", "M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12 M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17");
 ("list-filter", "M2 5h20 M6 12h12 M9 19h6");
 ("list-ordered", "M11 5h10 M11 12h10 M11 19h10 M4 4h1v5 M4 9h2 M6.5 20H3.4c0-1 2.6-1.925 2.6-3.5a1.5 1.5 0 0 0-2.6-1.02");
 ("list-tree", "M8 5h13 M13 12h8 M13 19h8 M3 10a2 2 0 0 0 2 2h3 M3 5v12a2 2 0 0 0 2 2h3");
 ("move", "M12 2v20 m15 19-3 3-3-3 m19 9 3 3-3 3 M2 12h20 m5 9-3 3 3 3 m9 5 3-3 3 3");
 ("network", "M17 16h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z M3 16h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z M10 2h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z M5 16v-3a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v3 M12 12V8");
 ("notebook-text", "M2 6h4 M2 10h4 M2 14h4 M2 18h4 M6 2h12a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2h-12a2 2 0 0 1-2-2v-16a2 2 0 0 1 2-2Z M9.5 8h5 M9.5 12H16 M9.5 16H14");
 ("package", "M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z M12 22V12 M3.29 7 12 12 20.71 7 m7.5 4.27 9 5.15");
 ("panels-top-left", "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-14a2 2 0 0 1-2-2v-14a2 2 0 0 1 2-2Z M3 9h18 M9 21V9");
 ("pencil-ruler", "M13 7 8.7 2.7a2.41 2.41 0 0 0-3.4 0L2.7 5.3a2.41 2.41 0 0 0 0 3.4L7 13 m8 6 2-2 m18 16 2-2 m17 11 4.3 4.3c.94.94.94 2.46 0 3.4l-2.6 2.6c-.94.94-2.46.94-3.4 0L11 17 M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z m15 5 4 4");
 ("plug", "M12 22v-5 M15 8V2 M17 8a1 1 0 0 1 1 1v4a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V9a1 1 0 0 1 1-1z M9 8V2");
 ("route", "M9 19a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15 M21 5a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z");
 ("scan-text", "M3 7V5a2 2 0 0 1 2-2h2 M17 3h2a2 2 0 0 1 2 2v2 M21 17v2a2 2 0 0 1-2 2h-2 M7 21H5a2 2 0 0 1-2-2v-2 M7 8h8 M7 12h10 M7 16h6");
 ("scroll-text", "M15 12h-5 M15 8h-5 M19 17V5a2 2 0 0 0-2-2H4 M8 21h12a2 2 0 0 0 2-2v-1a1 1 0 0 0-1-1H11a1 1 0 0 0-1 1v1a2 2 0 1 1-4 0V5a2 2 0 1 0-4 0v2a1 1 0 0 0 1 1h3");
 ("search", "m21 21-4.34-4.34 M19 11a8 8 0 1 1-16 0a8 8 0 1 1 16 0Z");
 ("send-horizontal", "M3.714 3.048a.498.498 0 0 0-.683.627l2.843 7.627a2 2 0 0 1 0 1.396l-2.842 7.627a.498.498 0 0 0 .682.627l18-8.5a.5.5 0 0 0 0-.904z M6 12h16");
 ("square-pen", "M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7 M18.375 2.625a1 1 0 0 1 3 3l-9.013 9.014a2 2 0 0 1-.853.505l-2.873.84a.5.5 0 0 1-.62-.62l.84-2.873a2 2 0 0 1 .506-.852z");
 ("terminal", "M12 19h8 m4 17 6-6-6-6");
 ("trash-2", "M10 11v6 M14 11v6 M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6 M3 6h18 M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2");
 ("unlink", "m18.84 12.25 1.72-1.71h-.02a5.004 5.004 0 0 0-.12-7.07 5.006 5.006 0 0 0-6.95 0l-1.72 1.71 m5.17 11.75-1.71 1.71a5.004 5.004 0 0 0 .12 7.07 5.006 5.006 0 0 0 6.95 0l1.71-1.71 M8 2L8 5 M2 8L5 8 M16 19L16 22 M19 16L22 16");
 ("workflow", "M5 3h4a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2Z M7 11v4a2 2 0 0 0 2 2h4 M15 13h4a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2Z")
].

Definition path name := option_map snd (find (fun entry=>String.eqb (fst entry) name) paths).
