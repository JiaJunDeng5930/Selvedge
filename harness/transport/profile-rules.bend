import Base
import ../DOMAIN.bend as D
import ../reasoning/MODEL.bend as R

# Catalogue values cover executable efforts; Adaptive user selection remains auto.
type Requirements is Type:
  Requirements{
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

law evidence:
  Requirements
