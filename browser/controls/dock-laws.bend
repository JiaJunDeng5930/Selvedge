import Base
import ../../interaction/INPUT.bend as U
import ../reading/MODEL.bend as Reading

type Requirements is Type:
  Requirements{
    measured_extent: @extent:F32 -> @viewport:F32 -> @+intent:U.ReadingIntent -> @+bookmark:Reading.Bookmark -> @reduced:Bool ->
      {Reading.step(Reading.LayoutChanged{extent, viewport}, intent, bookmark, reduced) ==
          Reading.Decision{bookmark, None{},
            Reading.ReserveComposer{Reading.reserve(extent, viewport)} <> Reading.layout(intent, bookmark)} : Reading.Decision}}

law evidence:
  Requirements
