import Base
import ./board-architecture.bend as Board

# Feature-specific guarantees are assembled without extending every consumer
# of the root harness interface.
type Features is Type:
  Features{board: Board.BoardBoundary}
