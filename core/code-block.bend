import Base
import ./ui-identity.bend as UIIdentity

type Source is Data:
  Message{task: Nat, message: Nat}
  StreamingPart{task: Nat, operation: Nat, part: Nat}

type Identity is Data:
  Identity{source: Source, ordinal: Nat}

type Block is Data:
  Block{identity: Identity, source: String, view: CodeView, next: Nat}

type Input is Data:
  SourceChanged{source: String}
  ToggleWrap{}
  Copy{}
  Copied{ticket: Nat, success: Bool}
  ExpireFeedback{ticket: Nat}

type Effect is Data:
  WriteClipboard{ticket: Nat, text: String}
  ScheduleFeedbackExpiry{ticket: Nat, delay_ms: Nat}

type Decision is Data:
  Decision{block: Block, effects: +List<Effect>}

type CopyState is Data:
  CopyIdle{}
  CopyPending{ticket: Nat}
  CopySucceeded{ticket: Nat}
  CopyFailed{ticket: Nat}

type CodeView is Data:
  CodeView{wrap: Bool, copy: CopyState}

type Control is Data:
  CopyControl{}
  WrapControl{}

type Scene is Data:
  Scene{identity: Identity, literal: String, wrap: Bool, copy: CopyState, copy_enabled: Bool, controls: +List<Control>}

def source_key(source: Source) -> String:
  match source:
    case Message{task, message}: "task/" ++ Nat.show(task) ++ "/message/" ++ Nat.show(message)
    case StreamingPart{task, operation, part}: "task/" ++ Nat.show(task) ++ "/stream/" ++ Nat.show(operation) ++ "/part/" ++ Nat.show(part)

def key(identity: Identity) -> String:
  Identity{source, ordinal} = identity
  source_key(source) ++ "/code/" ++ Nat.show(ordinal)

def ui_identity(identity: Identity) -> UIIdentity.Key:
  UIIdentity.Entity{UIIdentity.Place{"code-block"}, "block", key(identity)}

def dom_key(identity: Identity) -> String:
  UIIdentity.encode(ui_identity(identity))

def same(left: Identity, right: Identity) -> Bool:
  String.eq(key(left), key(right))

def belongs(identity: Identity, source: Source) -> Bool:
  Identity{owner, ordinal} = identity
  String.eq(source_key(owner), source_key(source))

def same_ticket(copy: CopyState, ticket: Nat) -> Bool:
  match copy:
    case CopyPending{current}: Nat.is_eq(current, ticket)
    case _: False{}

def feedback_ticket(copy: CopyState, ticket: Nat) -> Bool:
  match copy:
    case CopySucceeded{current}: Nat.is_eq(current, ticket)
    case CopyFailed{current}: Nat.is_eq(current, ticket)
    case _: False{}

def finish_code_copy(view: CodeView, ticket: Nat, ok: Bool) -> CodeView:
  CodeView{wrap, copy} = view
  match ok:
    case True{}: CodeView{wrap, CopySucceeded{ticket}}
    case False{}: CodeView{wrap, CopyFailed{ticket}}

def copy_result(owned: Bool, +ticket: Nat, success: Bool, block: Block) -> Decision:
  match owned:
    case False{}: Decision{block, Nil{}}
    case True{}:
      Block{identity, source, view, next} = block
      Decision{Block{identity, source, finish_code_copy(view, ticket, success), next}, [ScheduleFeedbackExpiry{ticket, 1800n}]}

def begin_code_copy(view: CodeView, ticket: Nat) -> CodeView:
  CodeView{wrap, copy} = view
  CodeView{wrap, CopyPending{ticket}}

def begin(allowed: Bool, block: Block) -> Decision:
  match allowed:
    case False{}: Decision{block, Nil{}}
    case True{}:
      Block{identity, +source, view, +next} = block
      Decision{Block{identity, source, begin_code_copy(view, next), (next + 1n : Nat)}, [WriteClipboard{next, source}]}

def source_changed(same: Bool, source: String, block: Block) -> Decision:
  match same:
    case True{}: Decision{block, Nil{}}
    case False{}:
      Block{identity, previous, CodeView{wrap, copy}, next} = block
      Decision{Block{identity, source, CodeView{wrap, CopyIdle{}}, next}, Nil{}}

def toggle_code_wrap(view: CodeView) -> CodeView:
  CodeView{wrap, copy} = view
  CodeView{Bool.not(wrap), copy}

def code_can_copy(view: CodeView) -> Bool:
  match view:
    case CodeView{wrap, CopyPending{ticket}}: False{}
    case _: True{}

def expire_code_feedback(owned: Bool, block: Block) -> Decision:
  match owned:
    case False{}: Decision{block, Nil{}}
    case True{}:
      Block{identity, source, CodeView{wrap, copy}, next} = block
      Decision{Block{identity, source, CodeView{wrap, CopyIdle{}}, next}, Nil{}}

def step(block: Block, input: Input) -> Decision:
  Block{identity, +source, CodeView{+wrap, +copy}, next} = block
  match input:
    case SourceChanged{+current}: source_changed(String.eq(source, current), current, Block{identity, source, CodeView{wrap, copy}, next})
    case ToggleWrap{}: Decision{Block{identity, source, toggle_code_wrap(CodeView{wrap, copy}), next}, Nil{}}
    case Copy{}: begin(code_can_copy(CodeView{wrap, copy}), Block{identity, source, CodeView{wrap, copy}, next})
    case Copied{+ticket, success}: copy_result(same_ticket(copy, ticket), ticket, success, Block{identity, source, CodeView{wrap, copy}, next})
    case ExpireFeedback{ticket}: expire_code_feedback(feedback_ticket(copy, ticket), Block{identity, source, CodeView{wrap, copy}, next})

def initial_code_view() -> CodeView:
  CodeView{False{}, CopyIdle{}}

def observe(block: Block) -> Scene:
  Block{identity, source, CodeView{+wrap, +copy}, next} = block
  Scene{identity, source, wrap, copy, code_can_copy(CodeView{wrap, copy}), [CopyControl{}, WrapControl{}]}

def choose_block(same: Bool, block: Block, fallback: Block) -> Block:
  match same:
    case True{}: block
    case False{}: fallback


def find_block(blocks: +List<Block>, +identity: Identity) -> Block:
  match blocks:
    case Nil{}: Block{identity, "", initial_code_view(), 0n}
    case Con{Block{+key, source, view, next}, rest}:
      choose_block(same(key, identity), Block{key, source, view, next}, find_block(rest, identity))


def replace_block(same: Bool, old: Block, rest: +List<Block>, current: Block, fallback: +List<Block>) -> +List<Block>:
  match same:
    case True{}: current <> rest
    case False{}: old <> fallback


def save_block(blocks: +List<Block>, +identity: Identity, +current: Block) -> +List<Block>:
  match blocks:
    case Nil{}: [current]
    case Con{Block{+key, source, view, next}, +rest}:
      replace_block(same(key, identity), Block{key, source, view, next}, rest, current, save_block(rest, identity, current))
