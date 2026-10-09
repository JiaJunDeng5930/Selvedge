import Base
import ../DOMAIN.bend as D
import ../reasoning/MODEL.bend as R
import ../../bendlib/json.bend as J

# Catalogue values cover executable efforts; Adaptive user selection remains auto.
type ProfileRequirements is Type:
  ProfileRequirements{
    default_permitted: @+profile:D.Profile ->
      @valid:{D.profile_valid(profile) == True{} : Bool} ->
      {D.profile_permitted(profile, D.profile_default(profile)) == True{} : Bool},
    fixed_selection_member: @key:String -> @provider:String -> @name:String ->
      @default:String -> @+values:+List<String> -> @+selection:String ->
      @accepted:{D.profile_permitted(D.Profile{key, provider, name, R.Fixed{}, Some{D.ReasoningOptions{default, values}}}, selection) == True{} : Bool} ->
      {R.member(values, selection) == True{} : Bool},
    default_alias: @+profile:D.Profile ->
      {D.profile_selection("default", profile) == D.profile_default(profile) : String},
    explicit_selection: @+profile:D.Profile -> @+selection:String ->
      @explicit:{String.eq(selection, "default") == False{} : Bool} ->
      {D.profile_selection(selection, profile) == selection : String}}

law profile_evidence:
  ProfileRequirements

def required_escape(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{code}, rest}: J.escaped_char(code) ++ required_escape(rest)

# The witness is an actual successful result of the production renderer.

def Completed(-result: Result<&2, &2, String, String>) -> Type:
  Sigma<&2, &1, String, (text => {result == Done{text} : Result<&2, &2, String, String>})>

type JsonRenderRequirements is Type:
  JsonRenderRequirements{
    sufficient: @+fuel:Nat -> @+job:J.Render ->
      @enough:{Nat.is_ge(fuel, J.required(job)) == True{} : Bool} ->
      Completed(J.render(fuel, job)),
    render_complete: @+job:J.Render -> Completed(J.render(J.required(job), job)),
    show_complete: @+value:J.Json -> Completed(J.show(value)),
    escape_refines: @+text:String -> {J.escape(text) == required_escape(text) : String}}

law json_render_evidence:
  JsonRenderRequirements
