import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../LAWS.bend as Laws
import ../../bendlib/json.bend as J
import ../protocol/COMMIT.bend as Commit
import ../execution/PROGRAM.bend as Execution
import ./MODEL.bend as Interface
import ./wire.bend as Wire
import ../protocol/commit-proof.bend as CommitProof

# Local proof obligations for the frontend boundary. No runtime policy lives here.

def Laws.frontend_input(input, world):
  match input:
    case Fail{reason}: {==}
    case Done{+input}:
      Equal.cong(M.Decision(), Interface.Output, (decision => Interface.Output{decision, M.durable(input)}),
        P.transition(input, world), Commit.input(~Execution.scheduled, input, world),
        Laws.interaction_transition(input, world))

def Laws.frontend_json(json, world):
  match json:
    case Fail{reason}: {==}
    case Done{json}: Laws.frontend_input(Wire.decode(json), world)

def Laws.frontend_packet(tokens, world):
  Laws.frontend_json(J.decode(tokens), world)
