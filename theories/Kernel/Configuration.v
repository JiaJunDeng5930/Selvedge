From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema JsonSchema Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec Workspace NativeTools Limits State Capabilities PluginProtocol ContextUpdates.
Import ListNotations.
Open Scope string_scope.

Definition valid_reference (source : json) :=
 match Schema.decode PluginProtocol.reference_schema source with
 | None => false | Some values => let name := head values in let revision := head (tail values) in
   nonempty name && nonempty revision && Nat.leb (String.length name) 128 && Nat.leb (String.length revision) 128 end.
Definition valid_plugin (source : json) :=
 match Schema.decode [Field "reference" KJson; Field "before_tool" KBool; Field "after_tool" KBool; Field "events" (KArray KText)] source with
 | None => false | Some values =>
   let events := head (tail (tail (tail values))) in
   valid_reference (head values) && Schema.unique_names events &&
   forallb (fun event => existsb (String.eqb event) Limits.plugin_events) events end.
Definition valid_global_instructions (source : json) := match source with JNull => true | _ =>
 match Schema.decode [Field "path" KText; Field "revision" KText; Field "content" KText] source with
 | None => false | Some values => match ContextUpdates.global_guidance_snapshot source with
   | None => false | Some _ => Workspace.valid_path (head values) &&
     Utf8.no_nul (head (tail (tail values))) && Nat.leb (String.length (head (tail (tail values)))) 32768
   end end end.
Definition parse_instructions source :=
 match Schema.decode [Field "configured" KText; Field "global" (KOptional KJson)] source with
 | None => None | Some values =>
   let configured := head values in let global := head (tail values) in
   if Utf8.no_nul configured && Nat.leb (String.length configured) 32768 &&
      valid_global_instructions (match global with Some value => value | None => JNull end)
   then Some (configured,global) else None end.
Definition valid_instructions source := match parse_instructions source with Some _ => true | None => false end.
Definition valid_route (plugins : list json) (source : json) :=
 let name := text_default "name" source "" in
 let remote := text_default "remote" source "" in
 nonempty remote &&
 match field "plugin" source with
 | None | Some JNull => String.prefix "mcp__" name && nonempty (text_default "server" source "")
 | Some plugin => valid_reference plugin && Capabilities.plugin_present plugin plugins &&
   String.eqb name (String.append "plugin__" (String.append (text_default "name" plugin "") (String.append "__" remote)))
 end.
Definition environment_schema :=
 [Field "profiles" (KArray KJson); Field "tools" (KArray KJson); Field "plugins" (KOptional (KArray KJson));
  Field "max_fork" KNatural;Field "max_descendants" KNatural;Field "project" (KOptional KJson);Field "instructions" KJson].
Definition environment_of_fields (values : Schema.fields environment_schema) : option environment :=
 let profiles := head values in let values := tail values in
 let raw_tools := head values in let values := tail values in
 let plugins := match head values with Some plugins => plugins | None => [] end in let values := tail values in
 let max_fork := head values in let values := tail values in
 let max_descendants := head values in let values := tail values in
 let project := match head values with Some project => project | None => JNull end in
 match traverse parse_profile profiles, traverse parse_tool raw_tools, parse_instructions (head (tail values)) with
 | Some profiles, Some tools, Some (configured,global) =>
   let catalog := (NativeTools.catalog max_fork ++ tools)%list in
   if Schema.unique_names (map profile_key profiles) && Schema.unique_names (map tool_name catalog) &&
      forallb valid_plugin plugins && Nat.leb (List.length plugins) 16 &&
      Schema.unique_names (map (fun plugin => text_default "name" (value_or_null "reference" plugin) "") plugins) &&
      forallb (valid_route plugins) raw_tools &&
      ((0 <? max_fork) && (max_fork <=? 4294967295) && (0 <? max_descendants) && (max_descendants <=? 4294967295))%N &&
      valid_guidance project
   then Some (Environment profiles catalog max_fork max_descendants project plugins configured global) else None
 | _,_,_ => None end.
Definition parse_environment source := match source with
 | JObject source => match Schema.decode_fields environment_schema source with
   | Some values => environment_of_fields values | None => None end
 | _ => None end.
Definition configure (source : json) (value : world) :=
 match parse_environment source with
 | Some environment => accept (JObject [("configured",JBool true)]) (with_environment environment value) []
  | None => reject "invalid_input" "Malformed environment: profiles and tool routes must be unique, tool contracts valid, plugins valid, and limits positive" value
 end.
