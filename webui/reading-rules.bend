import Base
import ../core/user-input.bend as U
import ./interaction.bend as Physical
import ./reading.bend as Model

law history_layout:
  for anchor: Physical.Anchor
  {Model.layout(U.ReadHistory{}, Model.Bookmark{Some{anchor}}) == Model.PreserveAnchor{anchor} : Model.Effect}


law missing_history_anchor:
  {Model.layout(U.ReadHistory{}, Model.Bookmark{None{}}) == Model.MeasureAnchor{} : Model.Effect}


type ScrollOwnershipRequirements is Type:
  ScrollOwnershipRequirements{
    takeover: @intent:U.ReadingIntent -> @bookmark:Model.Bookmark -> @reduced:Bool ->
      {Model.step(Model.BeginUserScroll{}, intent, bookmark, reduced) ==
        Model.Decision{Model.Bookmark{None{}}, Some{U.ReadHistory{}}, [Model.LeaveViewport{}]} : Model.Decision}
  }

law scroll_ownership_evidence:
  ScrollOwnershipRequirements
