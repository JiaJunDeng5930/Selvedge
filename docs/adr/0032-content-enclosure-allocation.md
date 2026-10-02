# ADR 0032: Content allocation belongs to its enclosing surface

## Reason

A background can enclose content even when its border is zero. Keeping content
insets separate from border paint prevents borderless rows and actions from
losing their local space. The same allocation survives selection and pointer
states; dialog partitions own their space without duplicating outer padding.

Appearance and specialized document rendering consume the same named allocation.
Proof queries use the final ordered property list with the host's last-write
semantics, so an earlier value cannot hide a later override. Browser layout and
viewport capacity remain external boundaries.
