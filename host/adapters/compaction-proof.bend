import Base
import ../../bendlib/json.bend as J
import ./COMPACTION.bend as C

def C.complete_correspondence():
  operation => source => {==}

def C.opaque_input_has_no_local_token_estimate():
  +source => opaque => Equal.cong(Bool, J.Json, (value => C.meter_fallback_content(value, source)),
    C.request_has_opaque(J.get(source, "request")), True{}, opaque)
