import Base
import ../../interaction/INPUT.bend as U
import ../controls/GEOMETRY.bend as Physical
import ./MODEL.bend as Model

law history_layout:
  for anchor: Physical.Anchor
  {Model.layout(U.ReadHistory{}, Model.Bookmark{Some{anchor}}) == [Model.PreserveAnchor{anchor}] : +List<Model.Effect>}

law missing_history_anchor:
  {Model.layout(U.ReadHistory{}, Model.Bookmark{None{}}) == [Model.MeasureAnchor{}] : +List<Model.Effect>}

type ScrollOwnershipRequirements is Type:
  ScrollOwnershipRequirements{
    takeover: @intent:U.ReadingIntent -> @bookmark:Model.Bookmark -> @reduced:Bool ->
      {Model.step(Model.BeginUserScroll{}, intent, bookmark, reduced) ==
        Model.Decision{Model.Bookmark{None{}}, Some{U.ReadHistory{}}, [Model.LeaveViewport{}]} : Model.Decision}
  }

law scroll_ownership_evidence:
  ScrollOwnershipRequirements

law latest_layout:
  for bookmark: Model.Bookmark
  {Model.layout(U.FollowLatest{}, bookmark) ==
    [Model.CancelAnchorObservation{}, Model.AlignLatest{False{}}] : +List<Model.Effect>}

law return_latest:
  for intent: U.ReadingIntent
  for bookmark: Model.Bookmark
  for reduced: Bool
  {Model.step(Model.FollowLatest{}, intent, bookmark, reduced) ==
    Model.Decision{Model.Bookmark{None{}}, Some{U.FollowLatest{}},
      [Model.CancelAnchorObservation{}, Model.AlignLatest{Bool.not(reduced)}]} : Model.Decision}

law layout_changed:
  for height: F32
  for viewport: F32
  for intent: U.ReadingIntent
  for bookmark: Model.Bookmark
  for reduced: Bool
  {Model.step(Model.LayoutChanged{height, viewport}, intent, bookmark, reduced) ==
    Model.Decision{bookmark, None{}, List.append(&2, Model.Effect,
      [Model.ReserveComposer{Model.reserve(height, viewport)}], Model.layout(intent, bookmark))} : Model.Decision}

law history_selection:
  for anchor: Physical.Anchor
  for intent: U.ReadingIntent
  for bookmark: Model.Bookmark
  for reduced: Bool
  {Model.step(Model.ReadHistory{anchor}, intent, bookmark, reduced) ==
    Model.Decision{Model.Bookmark{Some{anchor}}, Some{U.ReadHistory{}}, [Model.LeaveViewport{}]} : Model.Decision}

law anchor_observation:
  for anchor: Physical.Anchor
  for intent: U.ReadingIntent
  for bookmark: Model.Bookmark
  for reduced: Bool
  {Model.step(Model.AnchorObserved{anchor}, intent, bookmark, reduced) ==
    Model.Decision{Model.Bookmark{Some{anchor}}, None{}, Nil{}} : Model.Decision}
