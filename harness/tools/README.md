# Native harness tools

[SYNTAX.bend](SYNTAX.bend) is the controlled syntax for existing harness
capabilities and their argument bindings. [MODEL.bend](MODEL.bend) derives the
input schema and checks the actual descriptor before constructing typed membership
in the intersection of correspondence and admissibility. Correspondence binds
the declaration, arguments, capability and execution; admissibility requires
nonempty names and descriptions and a supported schema.
The default six tools are definitions in `catalog`.

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
