import Base
import ./board-architecture.bend as Board
import ./chatgpt-architecture.bend as ChatGPT

# Feature-specific guarantees are assembled without extending every consumer
# of the root harness interface.
type Features is Type:
  Features{board: Board.BoardBoundary, chatgpt: ChatGPT.Boundary}
