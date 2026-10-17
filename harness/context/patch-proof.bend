import Base
import ./MODEL.bend as C
import ./CONTRACT.bend as Spec
import ../../bendlib/logic-proof.bend as Logic

def settled_change(+same: Bool, +change: Maybe<&2, C.Change>) ->
  {C.resolution_change(C.settled_observation(same, change)) == change : Maybe<&2, C.Change>}:
  match same change:
    case _ Some{change}: {==}
    case True{} None{}: {==}
    case False{} None{}: {==}

def settled_accepted(+same: Bool, +change: Maybe<&2, C.Change>, +observed: C.Snapshot,
  accepted: Spec.AcceptedObservation(change, observed)) ->
  Spec.AcceptedObservation(C.resolution_change(C.settled_observation(same, change)), observed):
  match same change:
    case _ Some{change}: accepted
    case True{} None{}: Unit{}
    case False{} None{}: Unit{}

def settled_patch(+same: Bool, +change: Maybe<&2, C.Change>, +previous: C.Value, +observed: C.Value,
  matches: {Spec.amendment_patch(change, previous, observed) == True{} : Bool}) ->
  {Spec.amendment_patch(C.resolution_change(C.settled_observation(same, change)), previous, observed) == True{} : Bool}:
  Equal.trans(Bool,
    Spec.amendment_patch(C.resolution_change(C.settled_observation(same, change)), previous, observed),
    Spec.amendment_patch(change, previous, observed), True{},
    Equal.cong(Maybe<&2, C.Change>, Bool, result => Spec.amendment_patch(result, previous, observed),
      C.resolution_change(C.settled_observation(same, change)), change, settled_change(same, change)), matches)

def settled_origin(+same: Bool, +change: Maybe<&2, C.Change>, +key: C.Key, +base: String, +revision: String, +patch: C.Patch,
  origin: Spec.AmendmentOrigin(change, key, base, revision, patch)) ->
  Spec.AmendmentOrigin(C.resolution_change(C.settled_observation(same, change)), key, base, revision, patch):
  match same change:
    case _ Some{change}: origin
    case True{} None{}: Unit{}
    case False{} None{}: Unit{}

def checked_amendment(+valid: Bool, +keys: Bool, +changed: Bool, +revision: Bool, +editable: Bool, +matches: Bool,
  +key: C.Key, +base: String, +observed: C.Snapshot, +patch: C.Patch,
  checked: {C.valid_snapshot(observed) == valid : Bool}) ->
  Spec.AcceptedObservation(C.amend_checked(valid && keys && changed && revision && editable && matches, key, base, observed, patch), observed):
  match valid keys changed revision editable matches:
    case False{} _ _ _ _ _: Unit{}
    case True{} False{} _ _ _ _: Unit{}
    case True{} True{} False{} _ _ _: Unit{}
    case True{} True{} True{} False{} _ _: Unit{}
    case True{} True{} True{} True{} False{} _: Unit{}
    case True{} True{} True{} True{} True{} False{}: Unit{}
    case True{} True{} True{} True{} True{} True{}: checked

# The accepted branch checks the complete declaration-specific source relation,
# including identity-projected fields, before storing the proposed patch.
def accepted_checked(+valid: Bool, +previous: Maybe<&2, C.Snapshot>, +observed: C.Snapshot, +patch: C.Patch,
  checked: {C.valid_snapshot(observed) == valid : Bool}) ->
  Spec.AcceptedObservation(C.observed_checked(previous, observed, patch, valid, checked), observed):
  match valid previous:
    case False{} _: Unit{}
    case True{} None{}: checked
    case True{} Some{C.Snapshot{+key, +base, +value}}:
      settled_accepted(C.same_key(key, C.snapshot_key(observed)) && C.same_value(value, C.snapshot_value(observed)),
        C.amend_checked(C.same_key(key, C.snapshot_key(observed)) && Bool.not(C.same_value(value, C.snapshot_value(observed))) &&
          Bool.not(String.eq(base, C.snapshot_revision(observed))) && C.valid_patch(key, patch) && C.patch_matches(C.apply_patch(value, patch), C.snapshot_value(observed)), key, base, observed, patch), observed,
      checked_amendment(True{}, C.same_key(key, C.snapshot_key(observed)),
        Bool.not(C.same_value(value, C.snapshot_value(observed))), Bool.not(String.eq(base, C.snapshot_revision(observed))), C.valid_patch(key, patch),
        C.patch_matches(C.apply_patch(value, patch), C.snapshot_value(observed)), key, base, observed, patch, checked))

def accepted_snapshot(+previous: Maybe<&2, C.Snapshot>, +observed: C.Snapshot, +patch: C.Patch) ->
  Spec.AcceptedObservation(C.observed_change(previous, observed, patch), observed):
  accepted_checked(C.valid_snapshot(observed), previous, observed, patch, {==})

def invalid_checked(+valid: Bool, +previous: Maybe<&2, C.Snapshot>, +observed: C.Snapshot, +patch: C.Patch,
  checked: {C.valid_snapshot(observed) == valid : Bool}, invalid: {C.valid_snapshot(observed) == False{} : Bool}) ->
  {C.observed_resolution_checked(previous, observed, patch, valid, checked) == C.rejected_observation() : C.ObservationResolution}:
  match valid:
    case False{}: {==}
    case True{}: Logic.impossible(
      {C.observed_resolution_checked(previous, observed, patch, True{}, checked) == C.rejected_observation() : C.ObservationResolution},
      Equal.trans(Bool, False{}, C.valid_snapshot(observed), True{}, Equal.sym(Bool, C.valid_snapshot(observed), False{}, invalid), checked))

def invalid_snapshot_rejected(+previous: Maybe<&2, C.Snapshot>, +observed: C.Snapshot, +patch: C.Patch,
  invalid: {C.valid_snapshot(observed) == False{} : Bool}) ->
  {C.observed_resolution(previous, observed, patch) == C.rejected_observation() : C.ObservationResolution}:
  invalid_checked(C.valid_snapshot(observed), previous, observed, patch, {==}, invalid)

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

def amendment_patch_checked(+valid: Bool, +key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch, checked: {C.valid_snapshot(observed) == valid : Bool}) ->
  {Spec.amendment_patch(C.observed_checked(Some{C.Snapshot{key, base, previous}}, observed, patch, valid, checked), previous, C.snapshot_value(observed)) == True{} : Bool}:
  match valid:
    case False{}: {==}
    case True{}: settled_patch(C.same_key(key, C.snapshot_key(observed)) && C.same_value(previous, C.snapshot_value(observed)),
      C.amend_checked(C.same_key(key, C.snapshot_key(observed)) && Bool.not(C.same_value(previous, C.snapshot_value(observed))) &&
        Bool.not(String.eq(base, C.snapshot_revision(observed))) && C.valid_patch(key, patch) && C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed)), key, base, observed, patch), previous, C.snapshot_value(observed),
    checked_patch(C.same_key(key, C.snapshot_key(observed)) &&
      Bool.not(C.same_value(previous, C.snapshot_value(observed))) && Bool.not(String.eq(base, C.snapshot_revision(observed))) && C.valid_patch(key, patch),
    C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed)), key, base, previous, observed, patch, {==}))

def observed_amendment_patch(+key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch) ->
  {Spec.amendment_patch(C.observed_change(Some{C.Snapshot{key, base, previous}}, observed, patch), previous, C.snapshot_value(observed)) == True{} : Bool}:
  amendment_patch_checked(C.valid_snapshot(observed), key, base, previous, observed, patch, {==})

def checked_origin(+valid: Bool, +key: C.Key, +base: String, +observed: C.Snapshot, +patch: C.Patch) ->
  Spec.AmendmentOrigin(C.amend_checked(valid, key, base, observed, patch), key, base, C.snapshot_revision(observed), patch):
  match valid:
    case False{}: Unit{}
    case True{}: {==}

def amendment_origin_checked(+valid: Bool, +key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch, checked: {C.valid_snapshot(observed) == valid : Bool}) ->
  Spec.AmendmentOrigin(C.observed_checked(Some{C.Snapshot{key, base, previous}}, observed, patch, valid, checked), key, base, C.snapshot_revision(observed), patch):
  match valid:
    case False{}: Unit{}
    case True{}: settled_origin(C.same_key(key, C.snapshot_key(observed)) && C.same_value(previous, C.snapshot_value(observed)),
      C.amend_checked(C.same_key(key, C.snapshot_key(observed)) && Bool.not(C.same_value(previous, C.snapshot_value(observed))) &&
        Bool.not(String.eq(base, C.snapshot_revision(observed))) && C.valid_patch(key, patch) && C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed)), key, base, observed, patch), key, base, C.snapshot_revision(observed), patch,
    checked_origin(C.same_key(key, C.snapshot_key(observed)) &&
      Bool.not(C.same_value(previous, C.snapshot_value(observed))) && Bool.not(String.eq(base, C.snapshot_revision(observed))) && C.valid_patch(key, patch) &&
      C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed)), key, base, observed, patch))

def observed_amendment_origin(+key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch) ->
  Spec.AmendmentOrigin(C.observed_change(Some{C.Snapshot{key, base, previous}}, observed, patch), key, base, C.snapshot_revision(observed), patch):
  amendment_origin_checked(C.valid_snapshot(observed), key, base, previous, observed, patch, {==})

def reject_unchanged(+prefix: Bool, +revision_changed: Bool, +editable: Bool, +matches: Bool,
  +key: C.Key, +base: String, +observed: C.Snapshot, +patch: C.Patch) ->
  {C.amend_checked(prefix && Bool.not(True{}) && revision_changed && editable && matches, key, base, observed, patch) == None{} : Maybe<&2, C.Change>}:
  match prefix:
    case False{}: {==}
    case True{}: {==}

def unchanged_valid_observation(+key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch,
  valid: {C.valid_snapshot(observed) == True{} : Bool},
  same: {C.same_value(previous, C.snapshot_value(observed)) == True{} : Bool}) ->
  {C.observed_checked(Some{C.Snapshot{key, base, previous}}, observed, patch, True{}, valid) == None{} : Maybe<&2, C.Change>}:
  +prefix = C.same_key(key, C.snapshot_key(observed))
  +revision_changed = Bool.not(String.eq(base, C.snapshot_revision(observed)))
  +editable = C.valid_patch(key, patch)
  +matches = C.patch_matches(C.apply_patch(previous, patch), C.snapshot_value(observed))
  Equal.trans(Maybe<&2, C.Change>,
    C.observed_checked(Some{C.Snapshot{key, base, previous}}, observed, patch, True{}, valid),
    C.amend_checked(prefix && Bool.not(C.same_value(previous, C.snapshot_value(observed))) && revision_changed && editable && matches, key, base, observed, patch), None{},
    settled_change(prefix && C.same_value(previous, C.snapshot_value(observed)),
      C.amend_checked(prefix && Bool.not(C.same_value(previous, C.snapshot_value(observed))) && revision_changed && editable && matches, key, base, observed, patch)),
  Equal.trans(Maybe<&2, C.Change>,
    C.amend_checked(prefix && Bool.not(C.same_value(previous, C.snapshot_value(observed))) && revision_changed && editable && matches, key, base, observed, patch),
    C.amend_checked(prefix && Bool.not(True{}) && revision_changed && editable && matches, key, base, observed, patch),
    None{},
    Equal.cong(Bool, Maybe<&2, C.Change>,
      (equal => C.amend_checked(prefix && Bool.not(equal) && revision_changed && editable && matches, key, base, observed, patch)),
      C.same_value(previous, C.snapshot_value(observed)), True{}, same),
    reject_unchanged(prefix, revision_changed, editable, matches, key, base, observed, patch)))

def unchanged_checked(+valid: Bool, +key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch, checked: {C.valid_snapshot(observed) == valid : Bool},
  same: {C.same_value(previous, C.snapshot_value(observed)) == True{} : Bool}) ->
  {C.observed_checked(Some{C.Snapshot{key, base, previous}}, observed, patch, valid, checked) == None{} : Maybe<&2, C.Change>}:
  match valid:
    case False{}: {==}
    case True{}: unchanged_valid_observation(key, base, previous, observed, patch, checked, same)

def unchanged_observation(+key: C.Key, +base: String, +previous: C.Value,
  +observed: C.Snapshot, +patch: C.Patch,
  same: {C.same_value(previous, C.snapshot_value(observed)) == True{} : Bool}) ->
  {C.observed_change(Some{C.Snapshot{key, base, previous}}, observed, patch) == None{} : Maybe<&2, C.Change>}:
  unchanged_checked(C.valid_snapshot(observed), key, base, previous, observed, patch, {==}, same)

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
