# command-model

This crate defines the Selvedge command model API slice used to dispatch model calls and return completed API outputs to the router.

Use it to define model-call request correlation, dispatch request, output envelope, call error, and router ingress API message types.

This crate is not for network access, database access, filesystem access, provider execution, or task runtime mutation.
