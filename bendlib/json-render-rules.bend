import Base
import ./json.bend as J

# The witness is an actual successful result of the production renderer.
def Completed(-result: Result<&2, &2, String, String>) -> Type:
  Sigma<&2, &1, String, (text => {result == Done{text} : Result<&2, &2, String, String>})>

type Requirements is Type:
  Requirements{
    sufficient: @+fuel:Nat -> @+job:J.Render ->
      @enough:{Nat.is_ge(fuel, J.required(job)) == True{} : Bool} ->
      Completed(J.render(fuel, job)),
    render_complete: @+job:J.Render -> Completed(J.render(J.required(job), job)),
    show_complete: @+value:J.Json -> Completed(J.show(value))}

law evidence:
  Requirements
