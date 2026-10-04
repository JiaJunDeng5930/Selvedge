import Base
import ./physical-source.bend as Source
import ./physical-content.bend as Content
import ./physical-content-rules.bend as ContentRules

def native_targets_claim(+snapshot: Content.Snapshot, +observations: +List<Content.Observation>) -> Type:
  {ContentRules.ready_native_targets_valid(Source.prepare(snapshot, observations)) == True{} : Bool}

type Requirements is Type:
  Requirements{native_targets: @+snapshot:Content.Snapshot -> @+observations:+List<Content.Observation> ->
    native_targets_claim(snapshot, observations)}

law evidence:
  Requirements
