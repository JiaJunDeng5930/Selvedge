import Base
import ../model-rules.bend as Rule
import ../platform.bend as Platform

def Rule.production_commit_preserves_product(decision, generation, environment, font):
  match decision:
    case Platform.Decision{product, platform, effects}: {==}
