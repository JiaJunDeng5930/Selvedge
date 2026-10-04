import Base
import ../focus-rules.bend as Rule
import ../focus.bend as Model

def Rule.cycle_evidence():
  Rule.CycleRequirements{order => focused => reverse => {==}, +key => +focused => previous => +first => +last => matching =>
      Equal.cong(Bool, Maybe<&2, String>,
        (hit => Model.cycle_match(hit, False{}, previous, Nil{}, first, last, first)),
        String.eq(key, focused), True{}, matching)
    , +key => +rest => +focused => matching =>
      Equal.cong(Bool, Maybe<&2, String>,
        (hit => Model.cycle_match(hit, True{}, None{}, rest, Some{key},
          List.head(&2, String, List.reverse(&2, String, key <> rest)),
          Model.cycle_scan(rest, focused, Some{key}, Some{key}, List.head(&2, String, List.reverse(&2, String, key <> rest)), True{}))),
        String.eq(key, focused), True{}, matching)
    }
