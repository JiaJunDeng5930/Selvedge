import Base
import ./focus.bend as Model

type CycleRequirements is Type:
  CycleRequirements{
    document: @order:+List<String> -> @focused:Maybe<&2,String> -> @reverse:Bool ->
      {Model.cycle(Model.Document{}, order, focused, reverse) == None{} : Maybe<&2,String>},
    forward_wrap: @+key:String -> @+focused:String -> @previous:Maybe<&2,String> -> @+first:Maybe<&2,String> -> @+last:Maybe<&2,String> ->
      @matching:{String.eq(key, focused) == True{} : Bool} ->
      {Model.cycle_scan([key], focused, previous, first, last, False{}) == first : Maybe<&2,String>},
    backward_wrap: @+key:String -> @+rest:+List<String> -> @+focused:String ->
      @matching:{String.eq(key, focused) == True{} : Bool} ->
      {Model.cycle_focused(Some{focused}, key <> rest, True{}) == List.head(&2, String, List.reverse(&2, String, key <> rest)) : Maybe<&2,String>}
  }

law cycle_evidence:
  CycleRequirements
