import Base

type Block is Data:
  Block{identity: String, source: String, view: CodeView, next: Nat, pending: Maybe<&2, Nat>}

type Input is Data:
  SourceChanged{source: String}
  ToggleWrap{}
  Copy{}
  Copied{ticket: Nat, success: Bool}
  ExpireFeedback{}

type Effect is Data:
  WriteClipboard{ticket: Nat, text: String}

type Decision is Data:
  Decision{block: Block, effects: +List<Effect>}

type CopyState is Data:
  CopyIdle{}
  CopyPending{}
  CopySucceeded{}
  CopyFailed{}

type CodeView is Data:
  CodeView{wrap: Bool, copy: CopyState}

type Control is Data:
  CopyControl{}
  WrapControl{}

type Scene is Data:
  Scene{identity: String, literal: String, wrap: Bool, copy: CopyState, copy_enabled: Bool, controls: +List<Control>}

def same_ticket(pending: Maybe<&2, Nat>, ticket: Nat) -> Bool:
  match pending:
    case None{}: False{}
    case Some{current}: Nat.is_eq(current, ticket)

def finish_code_copy(view: CodeView, ok: Bool) -> CodeView:
  CodeView{wrap, copy} = view
  match ok:
    case True{}: CodeView{wrap, CopySucceeded{}}
    case False{}: CodeView{wrap, CopyFailed{}}

def copy_result(owned: Bool, success: Bool, block: Block) -> Decision:
  match owned:
    case False{}: Decision{block, Nil{}}
    case True{}:
      Block{identity, source, view, next, pending} = block
      Decision{Block{identity, source, finish_code_copy(view, success), next, None{}}, Nil{}}

def begin_code_copy(view: CodeView) -> CodeView:
  CodeView{wrap, copy} = view
  CodeView{wrap, CopyPending{}}

def begin(allowed: Bool, block: Block) -> Decision:
  match allowed:
    case False{}: Decision{block, Nil{}}
    case True{}:
      Block{identity, +source, view, +next, pending} = block
      Decision{Block{identity, source, begin_code_copy(view), (next + 1n : Nat), Some{next}}, [WriteClipboard{next, source}]}

def source_changed(same: Bool, source: String, block: Block) -> Decision:
  match same:
    case True{}: Decision{block, Nil{}}
    case False{}:
      Block{identity, previous, CodeView{wrap, copy}, next, pending} = block
      Decision{Block{identity, source, CodeView{wrap, CopyIdle{}}, next, None{}}, Nil{}}

def toggle_code_wrap(view: CodeView) -> CodeView:
  CodeView{wrap, copy} = view
  CodeView{Bool.not(wrap), copy}

def code_can_copy(view: CodeView) -> Bool:
  match view:
    case CodeView{wrap, CopyPending{}}: False{}
    case _: True{}

def expire_code_feedback(view: CodeView) -> CodeView:
  match view:
    case CodeView{wrap, CopyPending{}}: CodeView{wrap, CopyPending{}}
    case CodeView{wrap, other}: CodeView{wrap, CopyIdle{}}

def step(block: Block, input: Input) -> Decision:
  Block{identity, +source, +view, next, +pending} = block
  match input:
    case SourceChanged{+current}: source_changed(String.eq(source, current), current, Block{identity, source, view, next, pending})
    case ToggleWrap{}: Decision{Block{identity, source, toggle_code_wrap(view), next, pending}, Nil{}}
    case Copy{}: begin(code_can_copy(view), Block{identity, source, view, next, pending})
    case Copied{ticket, success}: copy_result(same_ticket(pending, ticket), success, Block{identity, source, view, next, pending})
    case ExpireFeedback{}: Decision{Block{identity, source, expire_code_feedback(view), next, pending}, Nil{}}

def initial_code_view() -> CodeView:
  CodeView{False{}, CopyIdle{}}

def observe(block: Block) -> Scene:
  Block{identity, source, CodeView{+wrap, +copy}, next, pending} = block
  Scene{identity, source, wrap, copy, code_can_copy(CodeView{wrap, copy}), [CopyControl{}, WrapControl{}]}

def choose_block(same: Bool, block: Block, fallback: Block) -> Block:
  match same:
    case True{}: block
    case False{}: fallback


def find_block(blocks: +List<Block>, +identity: String) -> Block:
  match blocks:
    case Nil{}: Block{identity, "", initial_code_view(), 0n, None{}}
    case Con{Block{+key, source, view, next, pending}, rest}:
      choose_block(String.eq(key, identity), Block{key, source, view, next, pending}, find_block(rest, identity))


def replace_block(same: Bool, old: Block, rest: +List<Block>, current: Block, fallback: +List<Block>) -> +List<Block>:
  match same:
    case True{}: current <> rest
    case False{}: old <> fallback


def save_block(blocks: +List<Block>, +identity: String, +current: Block) -> +List<Block>:
  match blocks:
    case Nil{}: [current]
    case Con{Block{+key, source, view, next, pending}, +rest}:
      replace_block(String.eq(key, identity), Block{key, source, view, next, pending}, rest, current, save_block(rest, identity, current))
