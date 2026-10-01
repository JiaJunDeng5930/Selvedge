import Base
import ../core/user-input.bend as U
import ./interaction.bend as Physical

type Bookmark is Data:
  Bookmark{anchor: Maybe<&2, Physical.Anchor>}

type Event is Data:
  BeginUserScroll{}
  ReadHistory{anchor: Physical.Anchor}
  FollowLatest{}
  LayoutChanged{composer_height: F32, viewport_height: F32}
  AnchorObserved{anchor: Physical.Anchor}

type Effect is Data:
  LeaveViewport{}
  AlignLatest{animate: Bool}
  PreserveAnchor{anchor: Physical.Anchor}
  MeasureAnchor{}
  ReserveComposer{height: F32}

type Decision is Data:
  Decision{bookmark: Bookmark, intent: Maybe<&2, U.ReadingIntent>, effects: +List<Effect>}

def anchor_effect(anchor: Maybe<&2, Physical.Anchor>) -> Effect:
  match anchor:
    case None{}: MeasureAnchor{}
    case Some{value}: PreserveAnchor{value}

def layout(intent: U.ReadingIntent, bookmark: Bookmark) -> Effect:
  match intent bookmark:
    case U.FollowLatest{} Bookmark{anchor}: AlignLatest{False{}}
    case U.ReadHistory{} Bookmark{anchor}: anchor_effect(anchor)

def reserve(height: F32, viewport: F32) -> F32:
  F32.min(F32.max(height, 0.0), F32.max(viewport, 0.0))

def step(event: Event, intent: U.ReadingIntent, +bookmark: Bookmark, reduced_motion: Bool) -> Decision:
  match event:
    case BeginUserScroll{}: Decision{Bookmark{None{}}, Some{U.ReadHistory{}}, [LeaveViewport{}]}
    case ReadHistory{anchor}: Decision{Bookmark{Some{anchor}}, Some{U.ReadHistory{}}, [LeaveViewport{}]}
    case FollowLatest{}: Decision{Bookmark{None{}}, Some{U.FollowLatest{}}, [AlignLatest{Bool.not(reduced_motion)}]}
    case LayoutChanged{height, viewport}: Decision{bookmark, None{}, [ReserveComposer{reserve(height, viewport)}, layout(intent, bookmark)]}
    case AnchorObserved{anchor}: Decision{Bookmark{Some{anchor}}, None{}, Nil{}}

# A content/composer resize cannot invent follow-latest intent. The saved anchor
# is the same object used to issue the browser correction.
def history_layout(anchor: Physical.Anchor) ->
  {layout(U.ReadHistory{}, Bookmark{Some{anchor}}) == PreserveAnchor{anchor} : Effect}:
  {==}

def missing_history_anchor() ->
  {layout(U.ReadHistory{}, Bookmark{None{}}) == MeasureAnchor{} : Effect}:
  {==}

# The user takes ownership before the host can measure the new viewport.
def begin_user_scroll(intent: U.ReadingIntent, bookmark: Bookmark, reduced: Bool) ->
  {step(BeginUserScroll{}, intent, bookmark, reduced) ==
    Decision{Bookmark{None{}}, Some{U.ReadHistory{}}, [LeaveViewport{}]} : Decision}:
  {==}

type ScrollOwnershipRequirements is Type:
  ScrollOwnershipRequirements{
    takeover: @intent:U.ReadingIntent -> @bookmark:Bookmark -> @reduced:Bool ->
      {step(BeginUserScroll{}, intent, bookmark, reduced) ==
        Decision{Bookmark{None{}}, Some{U.ReadHistory{}}, [LeaveViewport{}]} : Decision}
  }

def scroll_ownership_evidence() -> ScrollOwnershipRequirements:
  ScrollOwnershipRequirements{begin_user_scroll}
