From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema JsonSchema Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec Workspace NativeTools Limits State Capabilities PluginProtocol ContextUpdates.
Import ListNotations.
Open Scope string_scope.

Definition valid_reference (source : json) :=
 match Schema.decode PluginProtocol.reference_schema source with
 | None => false
 | Some _ => let name := text_default "name" source "" in let revision := text_default "revision" source "" in
  nonempty name && nonempty revision && Nat.leb (String.length name) 128 && Nat.leb (String.length revision) 128
 end.
Definition valid_plugin (source : json) :=
 match Schema.decode [Field "reference" KJson; Field "before_tool" KBool; Field "after_tool" KBool; Field "events" (KArray KText)] source with
 | None => false
 | Some _ => valid_reference (value_or_null "reference" source) &&
   match strings (array_default "events" source) with
   | Some events => Schema.unique_names events && forallb (fun event => existsb (String.eqb event) Limits.plugin_events) events
   | None => false end
 end.
Definition valid_global_instructions (source : json) := match source with
 | JNull => true
 | _ => match Schema.decode [Field "path" KText; Field "revision" KText; Field "content" KText] source with
   | None => false
   | Some _ => match ContextUpdates.global_guidance_snapshot source with
     | None => false
     | Some _ => Workspace.valid_path (text_default "path" source "") &&
       Utf8.no_nul (text_default "content" source "") && Nat.leb (String.length (text_default "content" source "")) 32768
     end
   end end.
Definition valid_instructions (source : json) :=
 match Schema.decode [Field "configured" KText; Field "global" (KOptional KJson)] source with
 | None => false
 | Some _ => Utf8.no_nul (text_default "configured" source "") &&
   Nat.leb (String.length (text_default "configured" source "")) 32768 &&
   valid_global_instructions (value_or_null "global" source)
 end.
Definition valid_route (plugins : list json) (source : json) :=
 let name := text_default "name" source "" in
 let remote := text_default "remote" source "" in
 nonempty remote &&
 match field "plugin" source with
 | None | Some JNull => String.prefix "mcp__" name && nonempty (text_default "server" source "")
 | Some plugin => valid_reference plugin && Capabilities.plugin_present plugin plugins &&
   String.eqb name (String.append "plugin__" (String.append (text_default "name" plugin "") (String.append "__" remote)))
 end.
Definition parse_environment (source : json) : option environment :=
 match array_field "profiles" source, array_field "tools" source, (match field "plugins" source with None | Some JNull => Some [] | Some (JArray plugins) => Some plugins | _ => None end),
 natural_field "max_fork" source, natural_field "max_descendants" source with
 | Some profiles, Some tools, Some plugins, Some max_fork, Some max_descendants =>
   match traverse parse_profile profiles, traverse parse_tool tools with
   | Some profiles, Some tools =>
      let catalog := (NativeTools.catalog max_fork ++ tools)%list in
     if Schema.unique_names (map profile_key profiles) && Schema.unique_names (map tool_name catalog) &&
       forallb valid_plugin plugins && Nat.leb (List.length plugins) 16 &&
       Schema.unique_names (map (fun plugin => text_default "name" (value_or_null "reference" plugin) "") plugins) &&
        forallb (valid_route plugins) (array_default "tools" source) &&
       ((0 <? max_fork) && (max_fork <=? 4294967295) && (0 <? max_descendants) && (max_descendants <=? 4294967295))%N &&
       valid_guidance (value_or_null "project" source) && valid_instructions (value_or_null "instructions" source) then
     Some (Environment profiles catalog max_fork max_descendants (value_or_null "project" source) plugins
       (text_default "configured" (value_or_null "instructions" source) "")
       (match field "global" (value_or_null "instructions" source) with None | Some JNull => None | Some global => Some global end))
     else None
   | _,_ => None end
 | _,_,_,_,_ => None end.
Definition configure (source : json) (value : world) :=
 match parse_environment source with
 | Some environment => accept (JObject [("configured",JBool true)]) (with_environment environment value) []
  | None => reject "invalid_input" "Malformed environment: profiles and tool routes must be unique, tool contracts valid, plugins valid, and limits positive" value
 end.
