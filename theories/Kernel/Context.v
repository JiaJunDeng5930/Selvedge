From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction.Interactive Require Import Vocabulary.
From Selvedge.Kernel Require Import Numbers.
Import ListNotations.
Open Scope string_scope.

From Selvedge.Kernel Require Export ContextTypes.
Definition excluded := [".git"; ".hg"; ".svn"; "node_modules"; "vendor"; ".build";
 "dist"; "build"; "target"; ".next"; ".cache"; ".workpad"; "__pycache__";
 ".venv"; "venv"; ".agents"; ".claude"].
Definition discovery (files dirs : list string) :=
 DiscoveryPolicy files dirs [".git"] excluded 10000 100000 1024 262144.
Definition policy_source_path (policy : discovery_policy) (root path : string) :=
 existsb (fun file => String.eqb path
  (if String.eqb root "/" then String.append root file else String.append root (String.append "/" file)))
  (discovery_files policy).
Definition guidance_policy := discovery ["AGENTS.override.md"; "AGENTS.md"] [].
Definition home_skills_policy := discovery ["SKILL.md"] ["skills"; ".agents/skills"].
Definition workspace_skills_policy := discovery ["SKILL.md"] [".agents/skills"; ".claude/skills"].
Definition text_fields := [ValueField "content" Body false].
Definition applicability_fields := [ValueField "applies_to" (ObservationField "applies_to") true;
 ValueField "precedence" (ObservationField "precedence") true].
Definition skill_fields := [ValueField "name" (Metadata "name") true;
 ValueField "description" (Metadata "description") true;
 ValueField "path" (IdentityValue "path") false].
Definition configured := ContextDefinition "configured_instruction"
 "Follow these instructions while carrying out this task." Global (ConfigText "instructions")
 [IdentityField "origin" (Constant "configured") true] text_fields.
Definition global_guidance := ContextDefinition "global_agents"
 "Apply these instructions throughout this task, including work outside the selected workspace."
 Global (HomeGuidance guidance_policy) [IdentityField "path" SourcePath true] text_fields.
Definition project_guidance := ContextDefinition "project_guidance"
 "Apply these instructions within applies_to. The precedence directory orders guidance by ancestry: descendant directories take priority over ancestors; AGENTS.override.md takes priority over AGENTS.md in the same directory. Scope does not change execution permissions."
 PrimaryWorkspace (PrimaryGuidance guidance_policy) [IdentityField "workspace" WorkspaceRoot true]
 (text_fields ++ ValueField "path" (ObservationField "path") true :: applicability_fields).
Definition directory_guidance := ContextDefinition "directory_guidance"
 "Apply these instructions only within applies_to. The precedence directory orders guidance by ancestry: descendant directories take priority over ancestors; AGENTS.override.md takes priority over AGENTS.md in the same directory. Scope does not change execution permissions."
 EveryWorkspace (WorkspaceGuidance guidance_policy)
 [IdentityField "workspace" WorkspaceRoot true; IdentityField "path" SourcePath true]
 (text_fields ++ ValueField "path" (IdentityValue "path") false :: applicability_fields).
Definition configured_skill := ContextDefinition "skill_information"
 "Use this name and description to decide whether the skill applies. Read the listed path through an ordinary tool before using the skill. Its body is not tracked context."
 Global (ConfigFiles "skills") [IdentityField "path" SourcePath true] skill_fields.
Definition home_skill := ContextDefinition "user_skill_information"
 "Use this name and description to decide whether the skill applies. Skills in a more specific applicable directory take priority over ancestors; explicitly configured skills are preferred when names conflict. Read the listed path through an ordinary tool before using the skill. Its body is not tracked context."
 Global (HomeSkills home_skills_policy)
 [IdentityField "installation" HomeRoot true; IdentityField "path" SourcePath true]
 (skill_fields ++ applicability_fields).
Definition workspace_skill := ContextDefinition "workspace_skill_information"
 "Use this name and description only within applies_to. The precedence directory orders matching skills by ancestry, with descendant directories taking priority over ancestors; explicitly configured skills are preferred when names conflict. Read the listed path through an ordinary tool before using the skill. Its body is not tracked context."
 EveryWorkspace (WorkspaceSkills workspace_skills_policy)
 [IdentityField "workspace" WorkspaceRoot true; IdentityField "path" SourcePath true]
 (skill_fields ++ applicability_fields).

Definition interactive_markdown_guidance : string := "Interactive Markdown v1 is available in ordinary assistant replies. Use normal Markdown freely. To create local interactive content, emit a fenced code block whose entire info string is exactly selvedge-ui. Do not call a tool just to print conversation UI. For the persistent shared UI belonging to a Work, use read_work_ui and apply_work_ui_patch instead: these infer the calling Task's Work and read or edit the same DSL as raw source, without Markdown fences. They are separate from emitting a streaming conversation interface. Do not emit JavaScript, HTML, CSS, event callbacks, or scripts. Other fences and Markdown retain their ordinary meaning.
The fence contains exactly one <ui id=""name""> root. IDs match [A-Za-z][A-Za-z0-9_-]{0,63}; every component requires a unique lexical id. Declaration IDs for state/derive/source/dataset and template variable names must additionally be expression identifiers [A-Za-z][A-Za-z0-9_]{0,63}, without hyphens; true, false and null are reserved literals and cannot be binding names. Attributes are JSON-quoted strings or {expressions}; no text nodes, comments, duplicate attributes, spread props, or arbitrary tags. Leaves self-close; containers close with the matching name. You may stream complete declarations/components progressively. Never change earlier declarations. Keep blocks small.
Before the first visual child declare root values: <state id=""seats"" type=""integer"" initial={8} min={1} max={50} />; supported types integer, number, boolean, string, enum. Enum uses literal options={[""a"",""b""]}; string accepts max-length (default 4096, max 16384). Numeric step is positive, min/max optional except slider requires both. State initial/bounds/options are literals. <derive id=""cost"" value={seats * 29} /> references only earlier bindings. <source id=""workflow"" kind=""task-graph"" graph-id={42} mode=""live"" /> binds a real task graph ID returned by the graph creation/read tool; never invent IDs. <dataset id=""sales"" columns={[""id"",""month"",""amount""]} /> declares append-only data. Declarations share one namespace and cannot be repeated or nested. <row dataset=""sales"" key=""jan"" value={{id:""jan"",month:""Jan"",amount:200}} /> is the only declaration allowed after visual children; each row is a literal record with exactly the dataset columns and unique key.
Expressions support null, booleans, bounded decimals, strings, lists, records, earlier identifiers, record.field, list[index], parentheses, !, unary -, + - * / %, < <= > >= == !=, lazy && || and condition ? yes : no. No assignment, loops, functions, methods, imports, globals, coercion, or executable predicates. Numbers have at most 6 decimal places and magnitude <=1000000000. Arithmetic overflow/division by zero is an error. + joins two strings or adds two numbers; use text(number) to convert explicitly.
Component vocabulary is supplied below from the runtime declarations.
Inputs bind only root state by literal bind=""stateId"": slider, number-input, text-input, textarea, checkbox, select. Every input has nonempty label. State survives stream appends and source updates. Invalid edits retain last valid value with validation. Buttons require label and action: set(target,value), reset, draft(message), submit(message), copy(value), openUrl(url). draft places text in the current task composer only if empty; submit explicitly sends a captured message through ordinary task admission and must have an explicit Send label. External model actions stay disabled until the whole reply completes successfully; inherited UI in another task remains locally interactive but cannot run model external actions. Rendering/source changes/restoration never trigger actions. All model-authored external actions require every declared live source to be ready and fresh.
when(test bool) conditionally contains visual components. each(items list,item=""node"",key=""identity"") repeats a visual template with stable unique scalar record keys. Template variables cannot shadow declarations or other template variables; no declarations in templates. Root state is shared by repeated input bindings. table(rows list or dataset,row-key=""id"",sortable={true}) has 1..16 column children(id,field,label,optional format). Tables paginate above 100 rows. line-chart/bar-chart(data,row-key,x,y,optional label/x-label/y-label) plot up to 512 records in collection order and show truncation; y must be numeric and missing data is an error. No implicit line sorting.
A live source handle is {status,fresh,sequence,value}; status loading|ready|missing|forbidden|error and value is a graph or null. Use <resource-view id=""resource"" source=""workflow"" let=""graph""> to bind an available graph, including stale authorized data. The authored wrapper displays freshness and errors. Graph={id,name,nodes,edges}; node={identity,key,taskId,task}; task is null or {id,title,control,phase,working,awaitingHuman,pendingMessages,operations,statusLabel}. Edge={identity,ruleKey,sourceIdentity,targetIdentity,actionKind}. Use <graph-view id=""diagram"" nodes={graph.nodes} edges={graph.edges} node-key=""identity"" layout=""stable"" select=""selected""> with optional <node-template item=""node""><task-node id=""task"" label={node.key} task={node.task} motion={workflow.fresh && working(node.task) ? ""pulse"" : ""none""} /></node-template>. selected is an optional declared string state. Graph pan/zoom/selection are local. Task idle/Ready never means successful completion. Task phases and approvals may coexist. Graph edges describe forwarding rules, not proof of current transfer. Live snapshots show current state, not every intervening event. Live changes do not automatically enter model context.
Limits and built-in function arities are supplied below by the executable declarations. Keep definitions concise and include explicit empty states. Malformed blocks preserve accepted controls and source; other Markdown continues.
Calculator example:
```selvedge-ui
<ui id=""team-cost"">
  <state id=""seats"" type=""integer"" initial={8} min={1} max={50} />
  <derive id=""monthly"" value={seats * 29} />
  <stack id=""layout"" gap=""md"">
    <slider id=""seat-input"" label=""人数"" bind=""seats"" />
    <metric id=""price"" label=""每月费用"" value={monthly} format=""currency:USD"" />
    <button id=""continue"" label=""填入输入框"" action=""draft"" message={""按 "" + text(seats) + "" 个席位继续分析""} />
  </stack>
</ui>
```
Table/chart example:
```selvedge-ui
<ui id=""sales-report"">
  <dataset id=""sales"" columns={[""id"",""month"",""amount""]} />
  <table id=""details"" rows={sales} row-key=""id""><column id=""month"" field=""month"" label=""月份"" /><column id=""amount"" field=""amount"" label=""收入"" format=""currency:CNY"" /></table>
  <bar-chart id=""trend"" data={sales} row-key=""id"" x=""month"" y=""amount"" label=""月收入"" />
  <row dataset=""sales"" key=""jan"" value={{id:""jan"",month:""Jan"",amount:200}} />
</ui>
```
Task graph example (replace42 with the real returned graph ID):
```selvedge-ui
<ui id=""workflow-monitor"">
  <state id=""selected"" type=""string"" initial="""" />
  <source id=""workflow"" kind=""task-graph"" graph-id={42} mode=""live"" />
  <resource-view id=""resource"" source=""workflow"" let=""graph"">
    <graph-view id=""diagram"" nodes={graph.nodes} edges={graph.edges} node-key=""identity"" layout=""stable"" select=""selected"" />
  </resource-view>
</ui>
```".
Definition interactive_markdown_text := String.append interactive_markdown_guidance
 (String.append "
Runtime component declarations: " (String.concat (String (Ascii.ascii_of_nat 10) EmptyString)
 [Vocabulary.registry_text; Vocabulary.declarations_text; Vocabulary.builtin_text; Vocabulary.limits_text])).
Definition interactive_markdown := ContextDefinition "interactive_markdown_v1"
 "The runtime supports the following assistant output capability." Global
 (NativeText "3" interactive_markdown_text)
 [IdentityField "capability" (Constant "interactive-markdown-v1") true] text_fields.
Definition definitions := [configured; global_guidance; project_guidance; directory_guidance;
 configured_skill; home_skill; workspace_skill; interactive_markdown].
Definition scope_json (value : scope) := JString
 (match value with Global => "global" | PrimaryWorkspace => "primary_workspace" | EveryWorkspace => "workspace" end).
Definition policy_json (value : discovery_policy) := JObject [
 ("files", JArray (map JString (discovery_files value)));
 ("directories", JArray (map JString (discovery_directories value)));
 ("repository_markers", JArray (map JString (discovery_markers value)));
 ("excluded", JArray (map JString (discovery_excluded value)));
 ("max_directories", number (discovery_max_directories value));
 ("max_entries", number (discovery_max_entries value));
 ("max_sources", number (discovery_max_sources value));
 ("max_bytes", number (discovery_max_bytes value))].
Definition observer_json (value : observer) :=
 match value with
 | NativeState => JObject [("type", JString "native_state")]
 | NativeText revision content => JObject [("type", JString "native_text"); ("revision", JString revision); ("content", JString content)]
 | ConfigText setting => JObject [("type", JString "config_text"); ("setting", JString setting)]
 | ConfigFiles setting => JObject [("type", JString "config_files"); ("setting", JString setting)]
 | HomeFile relative => JObject [("type",JString "home_file");("relative",JString relative)]
 | WorkspaceFile relative => JObject [("type",JString "workspace_file");("relative",JString relative)]
 | HomeGuidance policy | PrimaryGuidance policy | WorkspaceGuidance policy
 | HomeSkills policy | WorkspaceSkills policy =>
   JObject [("type", JString (match value with
   | HomeGuidance _ => "home_guidance" | PrimaryGuidance _ => "primary_guidance"
   | WorkspaceGuidance _ => "workspace_guidance" | HomeSkills _ => "home_skills"
   | _ => "workspace_skills" end)); ("policy", policy_json policy)]
 end.
Definition identity_json (value : identity_field) := JObject [
 ("name", JString (identity_name value)); ("source", match identity_from value with
 | Constant text => JObject [("type", JString "constant"); ("value", JString text)]
 | SourcePath => JObject [("type", JString "source_path")]
 | WorkspaceRoot => JObject [("type", JString "workspace_root")]
 | HomeRoot => JObject [("type", JString "home_root")] end);
 ("required", JBool (identity_required value))].
Definition value_json (value : value_field) := JObject
 ([("name", JString (value_name value)); ("source", match value_from value with
 | Body => JObject [("type", JString "body")]
 | Metadata name => JObject [("type", JString "metadata"); ("field", JString name)]
 | ObservationField name => JObject [("type", JString "observation_field"); ("field", JString name)]
 | IdentityValue name => JObject [("type", JString "identity"); ("field", JString name)] end)] ++
 match value_from value with IdentityValue _ => [] | _ => [("required", JBool (value_required value))] end).
Definition definition_json (value : definition) := JObject [
 ("kind", JString (definition_kind value)); ("semantics", JString (definition_semantics value));
 ("scope", scope_json (definition_scope value)); ("observer", observer_json (definition_observer value));
 ("identity", JArray (map identity_json (definition_identity value)));
 ("fields", JArray (map value_json (definition_fields value)))].
Definition definitions_json := JArray (map definition_json definitions).

Definition project_limit : N := 32768.

Definition fields_json (fields : list (string * string)) := JObject (map (fun field => (fst field,JString (snd field))) fields).
Definition key_json (key : context_key) := JObject [
 ("type", JString (definition_kind (key_definition key)));
 ("definition", definition_json (key_definition key)); ("identity", fields_json (key_identity key))].
Definition snapshot_json (value : snapshot) := JObject [
 ("key", key_json (snapshot_key value)); ("revision", JString (snapshot_revision value));
 ("value", JObject [("type", JString (definition_kind (key_definition (snapshot_key value))));
   ("fields", fields_json (snapshot_fields value))])].
Definition edit_json (value : text_edit) := JObject [
 ("start", number (edit_start value)); ("removed", JString (edit_removed value)); ("inserted", JString (edit_inserted value))].
Definition patch_json (patches : list field_patch) := JObject [
 ("type", JString "field_edits"); ("fields", JArray (map (fun patch => JObject [
 ("field", JString (patch_field patch)); ("edits", JArray (map edit_json (patch_edits patch)))]) patches))].
Definition change_json (value : context_change) := match value with
 | Introduce value => JObject [("type", JString "introduce"); ("snapshot", snapshot_json value)]
 | Amend key base revision patches => JObject [("type", JString "amend"); ("key", key_json key);
   ("base_revision", JString base); ("revision", JString revision); ("patch", patch_json patches)]
 | Remove key base => JObject [("type", JString "remove"); ("key", key_json key); ("base_revision", JString base)] end.
