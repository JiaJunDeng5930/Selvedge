import Base
import ../../harness/features/MODEL.bend as F
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ./MODEL.bend as B
import ../../harness/MODEL.bend as M
import ./CONTRACT.bend as A
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ./STATE.bend as S
import ./resolution.bend as R
import ../../bendlib/json.bend as J

def archive_interruption(+archived:Bool, +working:Bool, +found:Maybe<&2, D.Task>, +decision:M.Decision()) ->
  {Actual.interrupt_found(archived && working, found, decision) == Spec.cancel_archived(archived, working, found, decision) : M.Decision()}:
  match archived working found decision:
    case False{} _ _ _: {==}
    case True{} False{} _ _: {==}
    case True{} True{} None{} _: {==}
    case True{} True{} Some{task} C.Decision{C.Frame{core, +board}, reply, effects}: {==}

def archive_saved(+id:Nat, +card:B.Card, +archived:Bool, +now:U32, +world:M.World()) ->
  {Actual.save(id, B.set_archive(archived, card, now), B.next_card(S.registry(world)), world) == Spec.archive_result(id, card, archived, now, world) : M.Decision()}:
  match card world:
    case B.Card{revision, draft, task, old_archive, created, updated, enrichment, error, pinned}
      C.Frame{core, +board}: {==}

def archive_meaning(+id:Nat, +card:B.Card, +archived:Bool, +now:U32, +world:M.World()) ->
  {Actual.archive(id, card, archived, now, world) == Spec.change(R.ArchiveCard{id, card, archived, now}, world) : M.Decision()}:
  +saved = Actual.save(id, B.set_archive(archived, card, now), B.next_card(S.registry(world)), world)
  +required = Spec.archive_result(id, card, archived, now, world)
  Equal.trans(M.Decision(), Actual.archive(id, card, archived, now, world),
    Spec.cancel_archived(archived, S.busy(S.task(card, world)), S.task(card, world), saved),
    Spec.change(R.ArchiveCard{id, card, archived, now}, world),
    archive_interruption(archived, S.busy(S.task(card, world)), S.task(card, world), saved),
    Equal.cong(M.Decision(), M.Decision(),
      (decision => Spec.cancel_archived(archived, S.busy(S.task(card, world)), S.task(card, world), decision)),
      saved, required, archive_saved(id, card, archived, now, world)))

def reposition_meaning(+id: Nat, +card: B.Card, +position: Nat, +board: B.State) ->
  {B.reposition(id, card, position, board) == Spec.reposition(id, card, position, board) : B.State}:
  match board:
    case B.State{cards, next_card, agents, next_agent, automatic, draft_profile}: {==}

def relocate_meaning(+id: Nat, +card: B.Card, +position: Nat, +world: M.World()) ->
  {Actual.change(R.Relocate{id, card, position}, world) == Spec.change(R.Relocate{id, card, position}, world) : M.Decision()}:
  Equal.cong(B.State, M.Decision(),
    value => C.Decision{S.store(value, world), D.success(Actual.card_result(id, B.revision(card))), Nil{}},
    B.reposition(id, card, position, S.registry(world)), Spec.reposition(id, card, position, S.registry(world)),
    reposition_meaning(id, card, position, S.registry(world)))

def A.change_meaning(change, world):
  match change world:
    case R.StoreCard{id, card, next} C.Frame{core, +board}: {==}
    case R.Relocate{id, card, position} _: relocate_meaning(id, card, position, world)
    case R.RemoveCard{id} C.Frame{core, +board}: {==}
    case R.ArchiveCard{id, card, archived, now} _: archive_meaning(id, card, archived, now, world)
    case R.Configure{automatic, profile} C.Frame{core, +board}: {==}
    case R.StoreAgent{id, agent, next} C.Frame{core, +board}: {==}
    case R.RemoveAgent{id} C.Frame{core, +board}: {==}
    case R.RequestText{id, card, profile, retitle, next} C.Frame{core, +board}: {==}

def A.birth_meaning(id, task, card, now, decision):
  C.Decision{C.Frame{core, +board}, reply, effects} = decision
  {==}

def accepted_meaning(+valid:Bool, +title:String, +description:String, +card:B.Card) ->
  {Actual.suggested(valid, Spec.requested_draft(title, description, card), card) == Spec.accepted_draft(valid, title, description, card) : B.Card}:
  match valid card:
    case False{} B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned}: {==}
    case True{} B.Card{revision, B.Draft{old_title, old_description, stage, priority, owner, project, labels, attachments}, task, archived, created, updated, enrichment, error, pinned}: {==}

def draft_meaning(+retitle:Bool, +title:String, +description:String, +card:B.Card) ->
  {Actual.suggestion_draft(retitle, title, description, B.draft(card)) == Spec.requested_draft(title, Spec.selected_description(retitle, description, card), card) : B.Draft}:
  match retitle card:
    case False{} B.Card{revision, B.Draft{old_title, old_description, stage, priority, owner, project, labels, attachments}, task, archived, created, updated, enrichment, error, pinned}: {==}
    case True{} B.Card{revision, B.Draft{old_title, old_description, stage, priority, owner, project, labels, attachments}, task, archived, created, updated, enrichment, error, pinned}: {==}

def A.text_meaning(outcome, retitle, card):
  match outcome:
    case B.SuggestionFailed{reason}:
      B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
      {==}
    case B.Suggested{+title, +description}:
      +selected = Spec.selected_description(retitle, description, card)
      +draft = Actual.suggestion_draft(retitle, String.trim(title), description, B.draft(card))
      +required = Spec.requested_draft(String.trim(title), selected, card)
      Equal.trans(B.Card, Actual.complete(B.Suggested{title, description}, retitle, card),
        Actual.suggested(B.valid_draft(required), required, card), Spec.complete(B.Suggested{title, description}, retitle, card),
        Equal.cong(B.Draft, B.Card, (value => Actual.suggested(B.valid_draft(value), value, card)),
          draft, required, draft_meaning(retitle, String.trim(title), description, card)),
        accepted_meaning(B.valid_draft(required), String.trim(title), selected, card))

def A.completion_meaning(id, card, outcome, retitle, world):
  C.Frame{core, +board} = world
  Equal.cong(B.Card, M.Decision(), (value => C.Decision{
    C.Frame{core, F.with_board(B.put(id, value, F.board(board), B.next_card(F.board(board))), board)},
    D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}),
    Actual.complete(outcome, retitle, card), Spec.complete(outcome, retitle, card), A.text_meaning(outcome, retitle, card))

def title_only(title:String, description:String, +draft:B.Draft) ->
  {B.description(Actual.suggestion_draft(True{}, title, description, draft)) == B.description(draft) : String}:
  B.Draft{old_title, old_description, stage, priority, owner, project, labels, attachments} = draft
  {==}

def A.board_boundary():
  A.BoardBoundary{
    (change => world => A.change_meaning(change, world)),
    (id => task => card => now => decision => A.birth_meaning(id, task, card, now, decision)),
    (id => card => outcome => retitle => world => A.completion_meaning(id, card, outcome, retitle, world)),
    (pending => revision => ticket => {==}),
    (revision => ticket => {==}),
    (expected => revision => retitle => current => ticket => {==}),
    (id => card => ticket => outcome => {==}),
    (title => description => draft => title_only(title, description, draft))}
