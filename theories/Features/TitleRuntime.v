From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 Schema.
From Selvedge.Kernel Require Import Numbers Domain State Tasks.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Titles Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition entry (id:N) (value:world) := find (fun item=>N.eqb id (Selvedge.Features.Domain.title_task item)) (Selvedge.Features.Domain.feature_titles (world_features value)).
Definition store (id:N) (state:Selvedge.Features.Domain.title_state) (value:world) :=
 Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_titles (Selvedge.Features.Domain.TitleEntry id state :: filter (fun item=>negb (N.eqb id (Selvedge.Features.Domain.title_task item))) (Selvedge.Features.Domain.feature_titles (world_features value))) (world_features value)) value.
Definition configure (revision:N) (task_prompt agent_prompt:string) (value:world) :=
 if negb (Titles.valid_instructions task_prompt && Titles.valid_instructions agent_prompt) then
 Selvedge.Kernel.State.reject "invalid_title_settings" "Title prompts must be nonempty UTF-8 text of at most 4096 bytes" value
 else let current:=Selvedge.Features.Domain.feature_title_settings (world_features value) in
 if negb (N.eqb revision (Selvedge.Features.Domain.title_revision current)) then
 Selvedge.Kernel.State.reject "title_settings_conflict" "Title settings changed; reopen the settings before saving" value
 else let updated:=Selvedge.Features.Domain.TitleSettings (N.succ revision) task_prompt agent_prompt in
 Selvedge.Kernel.State.accept (Observation.title_settings_json updated) (Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_title_settings updated (world_features value)) value) [].
Definition query (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :option json := match command with
 | Selvedge.Generated.Commands.Cmd_read_title_settings _=>Some (Selvedge.Kernel.State.success (Observation.title_settings_json (Selvedge.Features.Domain.feature_title_settings (world_features value)))) | _=>None end.
Definition command (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :option decision := match command with
 | Selvedge.Generated.Commands.Cmd_configure_title_settings p=>Some (configure (Selvedge.Generated.Commands.configure_title_settings_revision p) (Selvedge.Generated.Commands.configure_title_settings_task_prompt p) (Selvedge.Generated.Commands.configure_title_settings_agent_prompt p) value) | _=>None end.
Definition first_request := Observation.first_request.
Fixpoint split_slash (text:string) (part:string) :list string := match text with
 | EmptyString=>[part] | String ch rest=>if Ascii.eqb ch "/"%char then part::split_slash rest "" else split_slash rest (String.append part (String ch "")) end.
Definition account_prefix (key:string) := match split_slash key "" with
 | "chatgpt"::account::_::_=>String.append "chatgpt/" (String.append account "/") | _=>"" end.
Definition capable (p:profile) := negb (String.eqb (profile_provider p) "echo").
Definition ordinary (p:profile) := capable p && match profile_policy p with FixedReasoning=>true | _=>false end.
Definition selected_profile (task:task) (value:world) :=
 let current:=task_current_profile task in
 let configured:=environment_profiles (world_environment value) in
 let fallback:=find (fun p=>String.eqb (profile_key current) (profile_key p) && capable p) configured in
 let prefix:=account_prefix (profile_key current) in
 match find (fun p=>String.eqb (profile_provider current) "chatgpt" && negb (String.eqb prefix "") && String.prefix prefix (profile_key p) && String.eqb (profile_provider p) "chatgpt" && String.eqb (profile_model p) "gpt-5.6-luna" && ordinary p) configured with
 | Some chosen=>Some chosen | None=>fallback end.
Definition prompt := Titles.prompt_with.
Definition accepts (task:task) := match task_lifecycle task with Running _ _|Frozen _ _=>true | _=>false end.
Definition start (id:N) (task:task) (result:decision) :decision :=
 let value:=decision_world result in
 match entry id value with Some _=>result | None=>
 let request:=first_request (task_history task) in
 if negb (accepts task && Utf8.nonblank request) then result else
 match selected_profile task value with None=>result | Some selected=>
 let '(ticket,allocated):=Selvedge.Kernel.State.allocate_ticket value in
 let source:=prompt (Selvedge.Features.Domain.title_agent_prompt (Selvedge.Features.Domain.feature_title_settings (world_features value))) request in
 Selvedge.Kernel.State.Decision (store id (Selvedge.Features.Domain.TitlePending ticket selected source) allocated) (decision_reply result)
 (decision_effects result ++ [Selvedge.Kernel.State.SuggestTitle id ticket selected source]) end end.
Definition after_transition (_before:world) (result:decision) :=
 fold_left (fun current pair=>start (fst pair) (snd pair) current) (indexed (fun id task=>(id,task)) 0 (world_tasks (decision_world result))) result.
Definition complete (id ticket:N) (ok:bool) (text:string) (value:world) :=
 let correlated:=match entry id value with Some item=>match Selvedge.Features.Domain.title_value item with Selvedge.Features.Domain.TitlePending expected _ _=>N.eqb ticket expected | _=>false end | None=>false end in
 let normalized:=Titles.normalize text in
 let next:=if correlated then store id (if ok && negb (String.eqb normalized "") then Selvedge.Features.Domain.Named normalized else Selvedge.Features.Domain.TitleFailed text) value else value in
 Selvedge.Kernel.State.accept (JObject [("accepted",JBool correlated)]) next [].
Definition completion (source:json) (value:world) :option (bool*bool*decision) :=
 match string_field "kind" source with Some "task_title"=>
 match natural_field "task_id" source,natural_field "ticket" source,bool_field "ok" source with
 | Some id,Some ticket,Some ok=>
 let declaration:=[Field "kind" KText;Field "task_id" KNatural;Field "ticket" KNatural;Field "ok" KBool;
 Field (if ok then "title" else "message") KText] in
 match Schema.decode declaration source with None=>None | Some _=>
 let supplied:=if ok then string_field "title" source else string_field "message" source in
 match supplied with None=>None | Some text=>
 if negb (N.leb (N.of_nat (String.length text)) Titles.response_title_bytes && Utf8.well_formed text) then None else
 Some (true,true,complete id ticket ok text value) end end
 | _,_,_=>None end | _=>None end.
Definition recover (value:world) := Selvedge.Kernel.State.with_features
 (Selvedge.Features.State.with_titles (map (fun item=>match Selvedge.Features.Domain.title_value item with
 | Selvedge.Features.Domain.TitlePending _ _ _=>Selvedge.Features.Domain.TitleEntry (Selvedge.Features.Domain.title_task item) (Selvedge.Features.Domain.TitleFailed "Interrupted before title generation completed")
 | _=>item end) (Selvedge.Features.Domain.feature_titles (world_features value))) (world_features value)) value.
