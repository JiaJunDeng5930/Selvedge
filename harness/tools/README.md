# Native harness tools

[SYNTAX.bend](SYNTAX.bend) is the controlled syntax for existing harness
capabilities and their argument bindings. [MODEL.bend](MODEL.bend) derives the
input schema and checks the actual descriptor before constructing typed membership
in the intersection of correspondence and admissibility. Correspondence binds
the declaration, arguments, capability and execution; admissibility requires
nonempty names and descriptions and a supported schema.
The default seven task and process tools are definitions in `catalog`.
The feature assembly appends its own constructed tools from its command specifications.

For example, a new tool over the existing task observation needs only:

```bend
Tools.construct(Tools.Request{"list_tasks", "List the current tasks.",
  Native.Observe{Native.Tasks{}}})
```

The result is `Maybe<&1, Categories.Membership<Tools.Observation, Tools.authored>>`.
A `Some` carries evidence for the actual descriptor; `Tools.constructed_tool`
extracts it after the caller handles the result. A `None` rejects an invalid
definition and carries no authored evidence. This definition adds no tool
identity enum, dispatch case or instance proof. Constants, argument names and defaults can vary within the
same capability syntax. `journal_authored` and `external_authored` expose family
inclusions; `Categories.extend_instance` adds independent instance membership.

`Create` uses the ordinary Task creation settings schema and command resolver.
Model-created Tasks must remain within the caller's workspace and permissions,
as model-created forks do. An explicit workspace can use exact directory roots
already observed in the caller, current environment or registered projects.
Observe a new directory through the public command's host entry before selecting
it from a model tool; model arguments cannot supply root guidance. Omitted
settings retain ordinary creation defaults, including registered project
selection. Creation keeps the ordinary independent Task identity; it does not
acquire fork ancestry or branching limits.

`Feature{operation, schema}` freezes an assembled command specification. Its tool
schema derives from that same command schema with the fixed `op` binding removed;
the caller cannot select another command through an argument. Invocation requires
the installed specification to have the frozen schema, checks the original
command codec and delegated Task settings, then uses the ordinary command
resolver. Queries use the same capability. Unsupported, changed or refused
feature operations settle an already accepted tool call with its error result.
This capability introduces no dependency from the core tool grammar to concrete
features and requires no interpreter branch for an authored workflow.

Construction certifies the declared bindings and checks supported schema shapes,
unique argument names, required declarations and numeric bounds. It rejects
empty names or descriptions, duplicate argument bindings and unsupported or
invalid schemas. `catalog_entry` includes only accepted descriptors; configuration
limits constrain `max_fork` to `1..4294967295` before the native catalog is built.
Catalog-wide tool name uniqueness remains a harness invariant. Command
authorization, completion correlation and committed state laws remain obligations of the harness command
and protocol owners. A new semantic primitive needs its own specification and
production proof. `Process` crosses the external host boundary: sandboxing,
execution ordering and unknown outcomes still require that boundary's evidence.
