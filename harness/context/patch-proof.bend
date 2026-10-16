import Base
import ./MODEL.bend as C
import ./CONTRACT.bend as Spec

# Rejected observations carry no amendment; accepted amendments must reconstruct
# the observed value using the patch that is actually stored in their history.
def checked_patch(+prefix: Bool, +matches: Bool, +key: C.Key, +base: String,
  +previous: C.Value, +observed: C.Snapshot, +patch: C.Patch,
  matching: {C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed)) == matches : Bool}) ->
  {Spec.amendment_patch(C.amend_checked(prefix && matches, key, base, observed, patch), previous, C.snapshot_value(observed)) == True{} : Bool}:
  match prefix matches:
    case False{} _: {==}
    case True{} False{}: {==}
    case True{} True{}: matching

def observed_amendment_patch(+key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch) ->
  {Spec.amendment_patch(C.observed_change(Some{C.Snapshot{key, base, previous}}, observed, patch), previous, C.snapshot_value(observed)) == True{} : Bool}:
  checked_patch(C.valid_snapshot(observed) && C.same_key(key, C.snapshot_key(observed)) &&
      Bool.not(C.same_value(previous, C.snapshot_value(observed))) && Bool.not(String.eq(base, C.snapshot_revision(observed))),
    C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed)), key, base, previous, observed, patch, {==})

def checked_origin(+valid: Bool, +key: C.Key, +base: String, +observed: C.Snapshot, +patch: C.Patch) ->
  Spec.AmendmentOrigin(C.amend_checked(valid, key, base, observed, patch), key, base, C.snapshot_revision(observed), patch):
  match valid:
    case False{}: Unit{}
    case True{}: {==}

def observed_amendment_origin(+key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch) ->
  Spec.AmendmentOrigin(C.observed_change(Some{C.Snapshot{key, base, previous}}, observed, patch), key, base, C.snapshot_revision(observed), patch):
  checked_origin(C.valid_snapshot(observed) && C.same_key(key, C.snapshot_key(observed)) &&
    Bool.not(C.same_value(previous, C.snapshot_value(observed))) && Bool.not(String.eq(base, C.snapshot_revision(observed))) &&
    C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed)), key, base, observed, patch)

def reject_unchanged(+prefix: Bool, +revision_changed: Bool, +matches: Bool,
  +key: C.Key, +base: String, +observed: C.Snapshot, +patch: C.Patch) ->
  {C.amend_checked(prefix && Bool.not(True{}) && revision_changed && matches, key, base, observed, patch) == None{} : Maybe<&2, C.Change>}:
  match prefix:
    case False{}: {==}
    case True{}: {==}

def unchanged_observation(+key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch,
  same: {C.same_value(previous, C.snapshot_value(observed)) == True{} : Bool}) ->
  {C.observed_change(Some{C.Snapshot{key, base, previous}}, observed, patch) == None{} : Maybe<&2, C.Change>}:
  +prefix = C.valid_snapshot(observed) && C.same_key(key, C.snapshot_key(observed))
  +revision_changed = Bool.not(String.eq(base, C.snapshot_revision(observed)))
  +matches = C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed))
  Equal.trans(Maybe<&2, C.Change>,
    C.observed_change(Some{C.Snapshot{key, base, previous}}, observed, patch),
    C.amend_checked(prefix && Bool.not(True{}) && revision_changed && matches, key, base, observed, patch),
    None{},
    Equal.cong(Bool, Maybe<&2, C.Change>,
      (equal => C.amend_checked(prefix && Bool.not(equal) && revision_changed && matches, key, base, observed, patch)),
      C.same_value(previous, C.snapshot_value(observed)), True{}, same),
    reject_unchanged(prefix, revision_changed, matches, key, base, observed, patch))

# This connects accepted patch execution to the real write operation, rather
# than only checking that the proposed patch would produce a matching value.
def apply_amendment(+bindings: +List<C.Snapshot>, +key: C.Key, +base: String,
  +previous_revision: String, +previous: C.Value, +revision: String, +patch: C.Patch, +value: C.Value,
  found: {C.find(bindings, key) == Some{C.Snapshot{key, previous_revision, previous}} : Maybe<&2, C.Snapshot>},
  base_matches: {String.eq(previous_revision, base) == True{} : Bool},
  patched: {C.apply_patch(previous, patch) == Some{value} : Maybe<&2, C.Value>}) ->
  {C.apply_change(C.Amend{key, base, revision, patch}, bindings) == (C.Snapshot{key, revision, value} <> C.remove_binding(bindings, key)) : +List<C.Snapshot>}:
  Equal.trans(+List<C.Snapshot>,
    C.apply_change(C.Amend{key, base, revision, patch}, bindings),
    C.replace_patched(Some{C.Snapshot{key, previous_revision, previous}}, key, base, revision, patch, bindings),
    C.put(C.Snapshot{key, revision, value}, bindings),
    Equal.cong(Maybe<&2, C.Snapshot>, +List<C.Snapshot>,
      (prior => C.replace_patched(prior, key, base, revision, patch, bindings)),
      C.find(bindings, key), Some{C.Snapshot{key, previous_revision, previous}}, found),
    Equal.trans(+List<C.Snapshot>,
      C.replace_checked(String.eq(previous_revision, base), C.apply_patch(previous, patch), key, revision, bindings),
      C.replace_checked(True{}, C.apply_patch(previous, patch), key, revision, bindings),
      C.put(C.Snapshot{key, revision, value}, bindings),
      Equal.cong(Bool, +List<C.Snapshot>,
        (valid => C.replace_checked(valid, C.apply_patch(previous, patch), key, revision, bindings)),
        String.eq(previous_revision, base), True{}, base_matches),
      Equal.cong(Maybe<&2, C.Value>, +List<C.Snapshot>,
        (result => C.replace_checked(True{}, result, key, revision, bindings)),
        C.apply_patch(previous, patch), Some{value}, patched)))
