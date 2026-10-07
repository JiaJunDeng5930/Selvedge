import Base
import ../../interaction/conversation/CODE.bend as Code

# NOTE: One parser result carries its declared content source and exact Markdown input.
type Observation is Data:
  Observation{identity: Code.Identity, text: String, source_value: String}
