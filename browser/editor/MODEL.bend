import Base
import ../../interaction/INPUT.bend as U
import ../controls/GEOMETRY.bend as Physical

type Editor is Data:
  Editor{owner: U.Editor, selection: Physical.Selection, composing: Bool}

type EditorEvent is Data:
  SelectionChanged{selection: Physical.Selection}
  CompositionChanged{composing: Bool}
  Enter{shift: Bool, alt: Bool, modified: Bool}

type Decision is Data:
  Decision{editor: Editor, submit: Bool}

def step(editor: Editor, event: EditorEvent, enabled: Bool, pending: Bool) -> Decision:
  Editor{owner, selection, +composing} = editor
  match event:
    case SelectionChanged{range}: Decision{Editor{owner, range, composing}, False{}}
    case CompositionChanged{active}: Decision{Editor{owner, selection, active}, False{}}
    case Enter{shift, alt, modified}:
      Decision{Editor{owner, selection, composing}, Physical.submit_key(composing, True{}, True{}, modified, shift, alt, enabled, pending)}
