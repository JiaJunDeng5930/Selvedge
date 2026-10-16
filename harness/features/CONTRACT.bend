import Base
import ../../features/compaction/CONTRACT.bend as Compaction
import ../../features/board/CONTRACT.bend as Board
import ../../features/chatgpt/CONTRACT.bend as ChatGPT

# Feature-specific guarantees are assembled without extending every consumer
# of the root harness interface.
type Features is Type:
  Features{board: Board.BoardBoundary, chatgpt: ChatGPT.Boundary, compaction: Compaction.Boundary}
