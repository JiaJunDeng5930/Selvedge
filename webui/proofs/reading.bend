import Base
import ../reading-rules.bend as Rule
import ../reading.bend as Model

def Rule.history_layout(anchor):
  {==}

def Rule.missing_history_anchor():
  {==}

# The user takes ownership before the host can measure the new viewport.

def Rule.scroll_ownership_evidence():
  Rule.ScrollOwnershipRequirements{intent => bookmark => reduced => {==}}


def Rule.latest_layout(bookmark):
  match bookmark:
    case Model.Bookmark{anchor}: {==}

def Rule.return_latest(intent, bookmark, reduced):
  {==}

def Rule.layout_changed(height, viewport, intent, bookmark, reduced):
  {==}

def Rule.history_selection(anchor, intent, bookmark, reduced):
  {==}

def Rule.anchor_observation(anchor, intent, bookmark, reduced):
  {==}
