import Base
import ./harness/DOMAIN.bend as D
import ./harness/tools/discovery-proof.bend as DiscoveryProof
import ./harness/MODEL.bend as M
import ./bendlib/json.bend as J
import ./harness/transport/PROGRAM.bend as Frontend
import ./harness/transport/MODEL.bend as Interface

def Host.receive(max_bytes: U32) -> IO(Result<&1, &1, U32 & String, Maybe<&2, +List<String>>>):
  import "./host/transport.c"

# The only unchecked recursion is the lifetime of the external stdin stream.
# It constructs no proofs. PROGRAM.transition itself always terminates.
@unsafe def serve(packet: Maybe<&2, +List<String>>, world: M.World()) -> IO(Unit):
  match packet:
    case None{}: IO.pure(Unit, Unit{})
    case Some{tokens}:
      +output = Frontend.packet(tokens, world)
      do IO<Unit>:
        IO.print(J.stringify(Interface.envelope(output)))
        packet : Maybe<&2, +List<String>> <- IO.try(Maybe<&2, +List<String>>, Host.receive(D.frame_bytes()))
        serve(packet, Interface.state(output))

def main() -> IO(Unit):
  do IO<Unit>:
    packet : Maybe<&2, +List<String>> <- IO.try(Maybe<&2, +List<String>>, Host.receive(D.frame_bytes()))
    serve(packet, M.initial())
