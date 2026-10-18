import Base
import ./measurement-requirements.bend as Dimensions
import ./physical-content-measurement.bend as Measurements
import ./SOURCE.bend as SourceSource
import ./CONTENT.bend as Content
import ./field-dimensions.bend as FieldDimensions
import ./physical-space.bend as Model
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure
import ../document/SOURCE.bend as Source
import ../document/MODEL.bend as Doc
import ../appearance/TYPOGRAPHY.bend as T
import ../../interaction/conversation/CODE.bend as Code
import ../../bendlib/categories.bend as Categories
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/equality-proof.bend as TextProof
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/logic-proof.bend as Logic

# Private evidence for complete measurement results and admission.
def same_purpose(+first: Content.Purpose, +second: Content.Purpose) ->
  {Measurements.same_purpose(first, second) == Dimensions.same_purpose(first, second) : Bool}:
  match first second:
    case Content.Natural{} Content.Natural{}: {==}
    case Content.Natural{} Content.AtWidth{+width}: {==}
    case Content.AtWidth{+width} Content.Natural{}: {==}
    case Content.AtWidth{+left} Content.AtWidth{+right}: {==}


def measurements_content_height_valid(+value: String, +height: Nat) ->
  {Measurements.content_height_valid(value, height) == Dimensions.content_height_valid(value, height) : Bool}:
  {==}

def measurements_primitive_observation_valid(+node: Source.Node, +height: Nat, +advance: Nat) ->
  {Measurements.primitive_observation_valid(node, height, advance) == Dimensions.primitive_observation_valid(node, height, advance) : Bool}:
  match node:
    case Source.Field{+key, +kind, +style, +attributes, +value, +placeholder, +options, +policy, +accessible_name, +enabled, +first_event, +remaining_events}:
      {==}
    case Source.Text{+key, +value, +font, +wrapping}:
      %Equal.sym(Bool, Measurements.content_height_valid(value, height), Dimensions.content_height_valid(value, height), measurements_content_height_valid(value, height)) :
        {_ == Dimensions.content_height_valid(value, height) : Bool}
      {==}
    case Source.RichText{+key, +style, Source.RichContent{+source, +value, +policy}, +attachments, +native_owner}:
      %Equal.sym(Bool, Measurements.content_height_valid(value, height), Dimensions.content_height_valid(value, height), measurements_content_height_valid(value, height)) :
        {_ == Dimensions.content_height_valid(value, height) : Bool}
      {==}
    case Source.NativeAttachment{+key, +target, +attributes, +style, +children}:
      {==}
    case Source.Box{+key, +tag, +style, +attributes, +children}:
      {==}
    case Source.Control{+key, +tag, +style, +attributes, +accessible_name, +enabled, +first_event, +remaining_events, +children}:
      {==}
    case Source.Glyph{+key, +drawing, +style}:
      {==}

def measurements_interactive_target_belongs(+target: Source.NativeTarget, +source: Maybe<&2, Code.Source>) ->
  {Measurements.interactive_target_belongs(target, source) == Dimensions.interactive_target_belongs(target, source) : Bool}:
  match target source:
    case Source.InteractiveTarget{+identity} Some{+owner}:
      {==}
    case Source.InteractiveTarget{+identity} None{}:
      {==}
    case Source.ToolbarTarget{+identity} _:
      {==}
    case Source.CodeBodyTarget{+identity, +wrap} _:
      {==}
    case Source.InteractiveSourceTarget{+identity, +exposed} _:
      {==}
    case Source.InteractiveFrameTarget{+identity, +active} _:
      {==}

def measurements_owned_interactive_root(+roots: +List<Content.NativeRoot>, +key: String, +source: Maybe<&2, Code.Source>) ->
  {Measurements.owned_interactive_root(roots, key, source) == Dimensions.owned_interactive_root(roots, key, source) : Bool}:
  match roots:
    case Nil{}:
      {==}
    case Con{Content.NativeRoot{+owner_key, +target, +tree, +attributes, +style}, +rest}:
      %Equal.sym(Bool, Measurements.owned_interactive_root(rest, key, source), Dimensions.owned_interactive_root(rest, key, source), measurements_owned_interactive_root(rest, key, source)) :
        {(String.eq(owner_key, key) && Measurements.interactive_target_belongs(target, source)) || _ == (String.eq(owner_key, key) && Dimensions.interactive_target_belongs(target, source)) || Dimensions.owned_interactive_root(rest, key, source) : Bool}
      %Equal.sym(Bool, Measurements.interactive_target_belongs(target, source), Dimensions.interactive_target_belongs(target, source), measurements_interactive_target_belongs(target, source)) :
        {(String.eq(owner_key, key) && _) || Dimensions.owned_interactive_root(rest, key, source) == (String.eq(owner_key, key) && Dimensions.interactive_target_belongs(target, source)) || Dimensions.owned_interactive_root(rest, key, source) : Bool}
      {==}

def measurements_natural_ui_zero(+node: Source.Node, +key: String, +roots: +List<Content.NativeRoot>, +height: Nat) ->
  {Measurements.natural_ui_zero(node, key, roots, height) == Dimensions.natural_ui_zero(node, key, roots, height) : Bool}:
  match node:
    case Source.RichText{+identity, +style, Source.RichContent{+source, +value, +policy}, +attachments, +native_owner}:
      %Equal.sym(Bool, Measurements.owned_interactive_root(roots, key, source), Dimensions.owned_interactive_root(roots, key, source), measurements_owned_interactive_root(roots, key, source)) :
        {_ && Nat.is_eq(height, 0n) == Dimensions.owned_interactive_root(roots, key, source) && Nat.is_eq(height, 0n) : Bool}
      {==}
    case Source.NativeAttachment{+identity, +target, +attributes, +style, +children}:
      {==}
    case Source.Box{+identity, +tag, +style, +attributes, +children}:
      {==}
    case Source.Control{+identity, +tag, +style, +attributes, +accessible_name, +enabled, +first_event, +remaining_events, +children}:
      {==}
    case Source.Text{+identity, +value, +font, +wrapping}:
      {==}
    case Source.Glyph{+identity, +drawing, +style}:
      {==}
    case Source.Field{+identity, +kind, +style, +attributes, +value, +placeholder, +options, +policy, +accessible_name, +enabled, +first_event, +remaining_events}:
      {==}

def measurements_zero_height_ui(+purpose: Content.Purpose, +node: Source.Node, +key: String,
  +roots: +List<Content.NativeRoot>, +height: Nat) ->
  {Measurements.zero_height_ui(purpose, node, key, roots, height) == Dimensions.zero_height_ui(purpose, node, key, roots, height) : Bool}:
  match purpose:
    case Content.Natural{}:
      %Equal.sym(Bool, Measurements.natural_ui_zero(node, key, roots, height), Dimensions.natural_ui_zero(node, key, roots, height), measurements_natural_ui_zero(node, key, roots, height)) :
        {_ == Dimensions.natural_ui_zero(node, key, roots, height) : Bool}
      {==}
    case Content.AtWidth{+width}:
      {==}

def measurements_request_observation_valid(+request: Content.Request, +height: Nat, +advance: Nat) ->
  {Measurements.request_observation_valid(request, height, advance) == Dimensions.request_observation_valid(request, height, advance) : Bool}:
  Content.Request{+generation, +key, Content.Value{+node, +font}, +purpose, +native_roots, +native_policies} = request
  %Equal.sym(Bool, Measurements.primitive_observation_valid(node, height, advance), Dimensions.primitive_observation_valid(node, height, advance), measurements_primitive_observation_valid(node, height, advance)) :
    {_ || Measurements.zero_height_ui(purpose, node, key, native_roots, height) == Dimensions.primitive_observation_valid(node, height, advance) || Dimensions.zero_height_ui(purpose, node, key, native_roots, height) : Bool}
  %Equal.sym(Bool, Measurements.zero_height_ui(purpose, node, key, native_roots, height), Dimensions.zero_height_ui(purpose, node, key, native_roots, height), measurements_zero_height_ui(purpose, node, key, native_roots, height)) :
    {Dimensions.primitive_observation_valid(node, height, advance) || _ == Dimensions.primitive_observation_valid(node, height, advance) || Dimensions.zero_height_ui(purpose, node, key, native_roots, height) : Bool}
  {==}

def sourcesource_text_height(+wrapping: T.Wrapping, +key: String, +height: Nat) ->
  {SourceSource.text_height(wrapping, key, height) == Dimensions.text_height(wrapping, key, height) : Model.Height}:
  match wrapping:
    case T.SingleLine{}:
      {==}
    case T.UnbrokenLine{}:
      {==}
    case T.WrapAnywhere{}:
      {==}
    case T.WrapWords{}:
      {==}
    case T.ScrollableCode{}:
      {==}
    case T.NormalAnywhere{}:
      {==}
    case T.NormalWords{}:
      {==}

def sourcesource_select_root(+same: Bool, +root: Content.NativeRoot, +rest: +List<Content.NativeRoot>) ->
  {SourceSource.select_root(same, root, rest) == Dimensions.select_root(same, root, rest) : +List<Content.NativeRoot>}:
  match same:
    case True{}:
      {==}
    case False{}:
      {==}

def sourcesource_owned_root(+roots: +List<Content.NativeRoot>, +owner: String) ->
  {SourceSource.owned_root(roots, owner) == Dimensions.owned_root(roots, owner) : +List<Content.NativeRoot>}:
  match roots:
    case Nil{}:
      {==}
    case Con{+root, +rest}:
      Content.NativeRoot{+owner_key, +target, +tree, +attributes, +style} = root
      %Equal.sym(+List<Content.NativeRoot>, SourceSource.owned_root(rest, owner), Dimensions.owned_root(rest, owner), sourcesource_owned_root(rest, owner)) :
        {SourceSource.select_root(String.eq(owner_key, owner), root, _) == Dimensions.select_root(String.eq(owner_key, owner), root, Dimensions.owned_root(rest, owner)) : +List<Content.NativeRoot>}
      %Equal.sym(+List<Content.NativeRoot>, SourceSource.select_root(String.eq(owner_key, owner), root, Dimensions.owned_root(rest, owner)), Dimensions.select_root(String.eq(owner_key, owner), root, Dimensions.owned_root(rest, owner)), sourcesource_select_root(String.eq(owner_key, owner), root, Dimensions.owned_root(rest, owner))) :
        {_ == Dimensions.select_root(String.eq(owner_key, owner), root, Dimensions.owned_root(rest, owner)) : +List<Content.NativeRoot>}
      {==}

def sourcesource_toolbar_minimum(+roots: +List<Content.NativeRoot>) ->
  {SourceSource.toolbar_minimum(roots) == Dimensions.toolbar_minimum(roots) : Enclosure.Extent}:
  match roots:
    case Nil{}:
      {==}
    case Con{Content.NativeRoot{+owner_key, Source.ToolbarTarget{+identity}, +tree, +attributes, +style}, +rest}:
      %Equal.sym(Enclosure.Extent, SourceSource.toolbar_minimum(rest), Dimensions.toolbar_minimum(rest), sourcesource_toolbar_minimum(rest)) :
        {Model.extent_max(Model.minimum_demand(Model.demand(~Content.Value, ~Doc.DOMEvent, tree)), _) == Model.extent_max(Model.minimum_demand(Model.demand(~Content.Value, ~Doc.DOMEvent, tree)), Dimensions.toolbar_minimum(rest)) : Enclosure.Extent}
      {==}
    case Con{Content.NativeRoot{+owner_key, Source.CodeBodyTarget{+identity, +wrap}, +tree, +attributes, +style}, +rest}:
      %Equal.sym(Enclosure.Extent, SourceSource.toolbar_minimum(rest), Dimensions.toolbar_minimum(rest), sourcesource_toolbar_minimum(rest)) :
        {_ == Dimensions.toolbar_minimum(rest) : Enclosure.Extent}
      {==}
    case Con{Content.NativeRoot{+owner_key, Source.InteractiveTarget{+identity}, +tree, +attributes, +style}, +rest}:
      %Equal.sym(Enclosure.Extent, SourceSource.toolbar_minimum(rest), Dimensions.toolbar_minimum(rest), sourcesource_toolbar_minimum(rest)) :
        {_ == Dimensions.toolbar_minimum(rest) : Enclosure.Extent}
      {==}
    case Con{Content.NativeRoot{+owner_key, Source.InteractiveSourceTarget{+identity, +exposed}, +tree, +attributes, +style}, +rest}:
      %Equal.sym(Enclosure.Extent, SourceSource.toolbar_minimum(rest), Dimensions.toolbar_minimum(rest), sourcesource_toolbar_minimum(rest)) :
        {_ == Dimensions.toolbar_minimum(rest) : Enclosure.Extent}
      {==}
    case Con{Content.NativeRoot{+owner_key, Source.InteractiveFrameTarget{+identity, +active}, +tree, +attributes, +style}, +rest}:
      %Equal.sym(Enclosure.Extent, SourceSource.toolbar_minimum(rest), Dimensions.toolbar_minimum(rest), sourcesource_toolbar_minimum(rest)) :
        {_ == Dimensions.toolbar_minimum(rest) : Enclosure.Extent}
      {==}

def sourcesource_rich_minimum(+node: Source.Node, +roots: +List<Content.NativeRoot>, +observed: Nat) ->
  {SourceSource.rich_minimum(node, roots, observed) == Dimensions.rich_minimum(node, roots, observed) : Nat}:
  match node:
    case Source.RichText{+key, +style, Source.RichContent{+source, +value, Source.RichPolicy{Source.CodeSurface{+frame, +chrome}, +toolbar_height, +block_gap, +list_indent, +code_text, +wrap}}, +attachments, +native_owner}:
      %Equal.sym(Enclosure.Extent, SourceSource.toolbar_minimum(roots), Dimensions.toolbar_minimum(roots), sourcesource_toolbar_minimum(roots)) :
        {Nat.max(observed, Nat.add(Enclosure.extent_width(_), Nat.mul(2n, Enclosure.inline(Enclosure.frame_content(frame))))) == Nat.max(observed, Nat.add(Enclosure.extent_width(Dimensions.toolbar_minimum(roots)), Nat.mul(2n, Enclosure.inline(Enclosure.frame_content(frame))))) : Nat}
      {==}
    case Source.Box{+key, +tag, +style, +attributes, +children}:
      {==}
    case Source.Control{+key, +tag, +style, +attributes, +accessible_name, +enabled, +first_event, +remaining_events, +children}:
      {==}
    case Source.Text{+key, +value, +font, +wrapping}:
      {==}
    case Source.Glyph{+key, +drawing, +style}:
      {==}
    case Source.Field{+key, +kind, +style, +attributes, +value, +placeholder, +options, +policy, +accessible_name, +enabled, +first_event, +remaining_events}:
      {==}
    case Source.NativeAttachment{+key, +target, +attributes, +style, +children}:
      {==}

def sourcesource_observation_minimum(+observation: Content.Observation) ->
  {SourceSource.observation_minimum(observation) == Dimensions.observation_minimum(observation) : Nat}:
  Content.Observation{+generation, +key, +purpose, +minimum_width, +preferred_width, +content_height, +reference_advance} = observation
  {==}

def sourcesource_observation_preferred(+observation: Content.Observation) ->
  {SourceSource.observation_preferred(observation) == Dimensions.observation_preferred(observation) : Nat}:
  Content.Observation{+generation, +key, +purpose, +minimum_width, +preferred_width, +content_height, +reference_advance} = observation
  {==}

def sourcesource_observation_height(+observation: Content.Observation) ->
  {SourceSource.observation_height(observation) == Dimensions.observation_height(observation) : Nat}:
  Content.Observation{+generation, +key, +purpose, +minimum_width, +preferred_width, +content_height, +reference_advance} = observation
  {==}

def sourcesource_observation_advance(+observation: Content.Observation) ->
  {SourceSource.observation_advance(observation) == Dimensions.observation_advance(observation) : Nat}:
  Content.Observation{+generation, +key, +purpose, +minimum_width, +preferred_width, +content_height, +reference_advance} = observation
  {==}

def sourcesource_text_natural_dimensions(+wrapping: T.Wrapping, +minimum: Nat, +preferred: Nat, +height: Nat, +advance: Nat) ->
  {SourceSource.text_natural_dimensions(wrapping, minimum, preferred, height, advance) == Dimensions.text_natural_dimensions(wrapping, minimum, preferred, height, advance) : Space.Demand}:
  match wrapping:
    case T.SingleLine{}:
      {==}
    case T.UnbrokenLine{}:
      {==}
    case T.WrapAnywhere{}:
      {==}
    case T.WrapWords{}:
      {==}
    case T.ScrollableCode{}:
      {==}
    case T.NormalAnywhere{}:
      {==}
    case T.NormalWords{}:
      {==}

def sourcesource_text_natural_demand(+wrapping: T.Wrapping, +observation: Content.Observation) ->
  {SourceSource.text_natural_demand(wrapping, observation) == Dimensions.text_natural_demand(wrapping, observation) : Space.Demand}:
  %Equal.sym(Nat, SourceSource.observation_height(observation), Dimensions.observation_height(observation), sourcesource_observation_height(observation)) :
    {SourceSource.text_natural_dimensions(wrapping, SourceSource.observation_minimum(observation), SourceSource.observation_preferred(observation), _, SourceSource.observation_advance(observation)) == Dimensions.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), Dimensions.observation_preferred(observation), Dimensions.observation_height(observation), Dimensions.observation_advance(observation)) : Space.Demand}
  %Equal.sym(Nat, SourceSource.observation_minimum(observation), Dimensions.observation_minimum(observation), sourcesource_observation_minimum(observation)) :
    {SourceSource.text_natural_dimensions(wrapping, _, SourceSource.observation_preferred(observation), Dimensions.observation_height(observation), SourceSource.observation_advance(observation)) == Dimensions.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), Dimensions.observation_preferred(observation), Dimensions.observation_height(observation), Dimensions.observation_advance(observation)) : Space.Demand}
  %Equal.sym(Nat, SourceSource.observation_advance(observation), Dimensions.observation_advance(observation), sourcesource_observation_advance(observation)) :
    {SourceSource.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), SourceSource.observation_preferred(observation), Dimensions.observation_height(observation), _) == Dimensions.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), Dimensions.observation_preferred(observation), Dimensions.observation_height(observation), Dimensions.observation_advance(observation)) : Space.Demand}
  %Equal.sym(Nat, SourceSource.observation_preferred(observation), Dimensions.observation_preferred(observation), sourcesource_observation_preferred(observation)) :
    {SourceSource.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), _, Dimensions.observation_height(observation), Dimensions.observation_advance(observation)) == Dimensions.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), Dimensions.observation_preferred(observation), Dimensions.observation_height(observation), Dimensions.observation_advance(observation)) : Space.Demand}
  %Equal.sym(Space.Demand, SourceSource.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), Dimensions.observation_preferred(observation), Dimensions.observation_height(observation), Dimensions.observation_advance(observation)), Dimensions.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), Dimensions.observation_preferred(observation), Dimensions.observation_height(observation), Dimensions.observation_advance(observation)), sourcesource_text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), Dimensions.observation_preferred(observation), Dimensions.observation_height(observation), Dimensions.observation_advance(observation))) :
    {_ == Dimensions.text_natural_dimensions(wrapping, Dimensions.observation_minimum(observation), Dimensions.observation_preferred(observation), Dimensions.observation_height(observation), Dimensions.observation_advance(observation)) : Space.Demand}
  {==}

def content_local_value(+node: Source.Node, +font: T.Presentation) ->
  {Content.local_value(node, font) == Dimensions.local_value(node, font) : Content.Value}:
  match node:
    case Source.Box{+key, +tag, +style, +attributes, +children}:
      {==}
    case Source.Control{+key, +tag, +style, +attributes, +accessible_name, +enabled, +first_event, +remaining_events, +children}:
      {==}
    case Source.RichText{+key, +style, +content, +attachments, +native_owner}:
      {==}
    case Source.NativeAttachment{+key, +target, +attributes, +style, +children}:
      {==}
    case Source.Text{+key, +value, +choice, +wrapping}:
      {==}
    case Source.Glyph{+key, +drawing, +style}:
      {==}
    case Source.Field{+key, +kind, +style, +attributes, +value, +placeholder, +options, +policy, +accessible_name, +enabled, +first_event, +remaining_events}:
      {==}

def sourcesource_observed_leaf_resolved(+line_height: Nat, +node: Source.Node, +key: String, +font: T.Presentation,
  +rule: Model.Rule, +observation: Content.Observation, +roots: +List<Content.NativeRoot>,
  +policies: +List<Content.NativePolicy>) ->
  {SourceSource.observed_leaf_resolved(line_height, node, key, font, rule, observation, roots, policies) == Dimensions.observed_leaf_resolved(line_height, node, key, font, rule, observation, roots, policies) : SourceSource.Forest}:
  match node:
    case Source.Text{+label, +value, +choice, +wrapping}:
      %Equal.sym(Nat, SourceSource.observation_height(observation), Dimensions.observation_height(observation), sourcesource_observation_height(observation)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, (Content.local_value(Source.Text{label, value, choice, wrapping}, font)), Model.DisplayOnly{}, rule, (SourceSource.text_natural_demand(wrapping, observation)), SourceSource.text_height(wrapping, key, (_))}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, (Dimensions.local_value(Source.Text{label, value, choice, wrapping}, font)), Model.DisplayOnly{}, rule, (Dimensions.text_natural_demand(wrapping, observation)), Dimensions.text_height(wrapping, key, (Dimensions.observation_height(observation)))}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Space.Demand, SourceSource.text_natural_demand(wrapping, observation), Dimensions.text_natural_demand(wrapping, observation), sourcesource_text_natural_demand(wrapping, observation)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, (Content.local_value(Source.Text{label, value, choice, wrapping}, font)), Model.DisplayOnly{}, rule, (_), SourceSource.text_height(wrapping, key, (Dimensions.observation_height(observation)))}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, (Dimensions.local_value(Source.Text{label, value, choice, wrapping}, font)), Model.DisplayOnly{}, rule, (Dimensions.text_natural_demand(wrapping, observation)), Dimensions.text_height(wrapping, key, (Dimensions.observation_height(observation)))}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Content.Value, Content.local_value(Source.Text{label, value, choice, wrapping}, font), Dimensions.local_value(Source.Text{label, value, choice, wrapping}, font), content_local_value(Source.Text{label, value, choice, wrapping}, font)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, (_), Model.DisplayOnly{}, rule, (Dimensions.text_natural_demand(wrapping, observation)), SourceSource.text_height(wrapping, key, (Dimensions.observation_height(observation)))}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, (Dimensions.local_value(Source.Text{label, value, choice, wrapping}, font)), Model.DisplayOnly{}, rule, (Dimensions.text_natural_demand(wrapping, observation)), Dimensions.text_height(wrapping, key, (Dimensions.observation_height(observation)))}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Model.Height, SourceSource.text_height(wrapping, key, (Dimensions.observation_height(observation))), Dimensions.text_height(wrapping, key, (Dimensions.observation_height(observation))), sourcesource_text_height(wrapping, key, (Dimensions.observation_height(observation)))) :
        {SourceSource.ReadyForest{[Model.Leaf{key, (Dimensions.local_value(Source.Text{label, value, choice, wrapping}, font)), Model.DisplayOnly{}, rule, (Dimensions.text_natural_demand(wrapping, observation)), _}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, (Dimensions.local_value(Source.Text{label, value, choice, wrapping}, font)), Model.DisplayOnly{}, rule, (Dimensions.text_natural_demand(wrapping, observation)), Dimensions.text_height(wrapping, key, (Dimensions.observation_height(observation)))}], roots, policies} : SourceSource.Forest}
      {==}
    case Source.Field{+label, +kind, +style, +attributes, +value, +placeholder, +options,
      Source.FieldPolicy{+columns, +lines, +maximum_lines}, +accessible_name, +enabled, +first_event, +remaining_events}:
      Content.Observation{+generation, +observed_key, +purpose, +minimum, +preferred, +measured, +advance} = observation
      +policy: Source.FieldPolicy = Source.FieldPolicy{columns, lines, maximum_lines}
      +field: Source.Node = Source.Field{label, kind, style, attributes, value, placeholder, options,
        policy, accessible_name, enabled, first_event, remaining_events}
      +demand: Space.Demand = FieldDimensions.natural_demand(kind, policy, line_height, minimum, preferred, measured, advance)
      +height: Model.Height = FieldDimensions.height(FieldDimensions.multiline(kind), key, Enclosure.extent_height(Model.minimum_demand(demand)))
      Equal.cong(Content.Value, SourceSource.Forest,
        (local => SourceSource.ReadyForest{[Model.Leaf{key, local, Source.interaction_of(field), rule, demand, height}], roots, policies}),
        Content.local_value(field, font), Dimensions.local_value(field, font), content_local_value(field, font))
    case Source.RichText{+label, +style, +content, +attachments, +native_owner}:
      %Equal.sym(+List<Content.NativeRoot>, SourceSource.owned_root(roots, key), Dimensions.owned_root(roots, key), sourcesource_owned_root(roots, key)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Content.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), _, (SourceSource.observation_minimum(observation)))), (SourceSource.observation_height(observation))}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), SourceSource.owned_root(roots, key), (SourceSource.observation_minimum(observation)))), (SourceSource.observation_preferred(observation))), (SourceSource.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(+List<Content.NativeRoot>, SourceSource.owned_root(roots, key), Dimensions.owned_root(roots, key), sourcesource_owned_root(roots, key)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Content.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (SourceSource.observation_minimum(observation)))), (SourceSource.observation_height(observation))}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), _, (SourceSource.observation_minimum(observation)))), (SourceSource.observation_preferred(observation))), (SourceSource.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Nat, SourceSource.observation_height(observation), Dimensions.observation_height(observation), sourcesource_observation_height(observation)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Content.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (SourceSource.observation_minimum(observation)))), (_)}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (SourceSource.observation_minimum(observation)))), (SourceSource.observation_preferred(observation))), (SourceSource.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Nat, SourceSource.observation_height(observation), Dimensions.observation_height(observation), sourcesource_observation_height(observation)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Content.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (SourceSource.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (SourceSource.observation_minimum(observation)))), (SourceSource.observation_preferred(observation))), (_)}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Nat, SourceSource.observation_minimum(observation), Dimensions.observation_minimum(observation), sourcesource_observation_minimum(observation)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Content.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (_))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (SourceSource.observation_minimum(observation)))), (SourceSource.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Nat, SourceSource.observation_minimum(observation), Dimensions.observation_minimum(observation), sourcesource_observation_minimum(observation)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Content.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (_))), (SourceSource.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Nat, SourceSource.observation_preferred(observation), Dimensions.observation_preferred(observation), sourcesource_observation_preferred(observation)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Content.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (_)), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Content.Value, Content.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), content_local_value((Source.RichText{label, style, content, attachments, native_owner}), font)) :
        {SourceSource.ReadyForest{[Model.Leaf{key, _, Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Nat, SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation))), Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation))), sourcesource_rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(_), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      %Equal.sym(Nat, SourceSource.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation))), Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation))), sourcesource_rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))) :
        {SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((_), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} == SourceSource.ReadyForest{[Model.Leaf{key, Dimensions.local_value((Source.RichText{label, style, content, attachments, native_owner}), font), Model.DisplayOnly{}, rule, Space.Demand{Enclosure.Extent{(Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_height(observation))}, Enclosure.Extent{Nat.max((Dimensions.rich_minimum((Source.RichText{label, style, content, attachments, native_owner}), Dimensions.owned_root(roots, key), (Dimensions.observation_minimum(observation)))), (Dimensions.observation_preferred(observation))), (Dimensions.observation_height(observation))}}, Model.HeightAtWidth{key}}], roots, policies} : SourceSource.Forest}
      {==}
    case Source.Box{+label, +tag, +style, +attributes, +children}:
      {==}
    case Source.Control{+label, +tag, +style, +attributes, +accessible_name, +enabled, +first_event, +remaining_events, +children}:
      {==}
    case Source.Glyph{+label, +drawing, +style}:
      {==}
    case Source.NativeAttachment{+label, +target, +attributes, +style, +children}:
      {==}

def sourcesource_observed_leaf(+node: Source.Node, +key: String, +font: T.Presentation,
  +rule: Model.Rule, +observation: Content.Observation, +roots: +List<Content.NativeRoot>,
  +policies: +List<Content.NativePolicy>) ->
  {SourceSource.observed_leaf(node, key, font, rule, observation, roots, policies) == Dimensions.observed_leaf(node, key, font, rule, observation, roots, policies) : SourceSource.Forest}:
  sourcesource_observed_leaf_resolved(T.resolved_line_height(T.resolved(font)), node, key, font, rule, observation, roots, policies)

def sourcesource_receipt(+found: Maybe<&2, Content.Observation>, +request: Content.Request,
  +rule: Model.Rule, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {SourceSource.receipt(found, request, rule, roots, policies) == Dimensions.receipt(found, request, rule, roots, policies) : SourceSource.Forest}:
  match found:
    case None{}: {==}
    case Some{+observation}:
      Content.Request{+generation, +key, Content.Value{+node, +font}, +purpose, +native_roots, +native_policies} = request
      sourcesource_observed_leaf(node, key, font, rule, observation, roots, policies)


def target_key(+target: Source.NativeTarget) ->
  {Source.target_key(target) == Dimensions.target_key(target) : String}:
  match target:
    case Source.ToolbarTarget{identity}: {==}
    case Source.CodeBodyTarget{identity, wrap}: {==}
    case Source.InteractiveTarget{identity}: {==}
    case Source.InteractiveSourceTarget{identity, exposed}: {==}
    case Source.InteractiveFrameTarget{identity, active}: {==}


def content_root_slot(+root: Content.NativeRoot) ->
  {Content.root_slot(root) == Dimensions.root_slot(root) : Content.NativeSlot}:
  Content.NativeRoot{+owner_key, +target, tree, attributes, style} = root
  Equal.cong(String, Content.NativeSlot, (key => Content.NativeSlot{owner_key, key}),
    Source.target_key(target), Dimensions.target_key(target), target_key(target))

def content_policy_slot(+policy: Content.NativePolicy) ->
  {Content.policy_slot(policy) == Dimensions.policy_slot(policy) : Content.NativeSlot}:
  Content.NativePolicy{+owner_key, +target, attributes, style} = policy
  Equal.cong(String, Content.NativeSlot, (key => Content.NativeSlot{owner_key, key}),
    Source.target_key(target), Dimensions.target_key(target), target_key(target))

def content_root_slots(+roots: +List<Content.NativeRoot>) ->
  {Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Content.root_slot, roots) == Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Dimensions.root_slot, roots) : +List<Content.NativeSlot>}:
  match roots:
    case Nil{}: {==}
    case Con{+root, +rest}:
      %Equal.sym(Content.NativeSlot, Content.root_slot(root), Dimensions.root_slot(root), content_root_slot(root)) :
        {_ <> Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Content.root_slot, rest) == Dimensions.root_slot(root) <> Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Dimensions.root_slot, rest) : +List<Content.NativeSlot>}
      Equal.cong((+List<Content.NativeSlot>), (+List<Content.NativeSlot>), (tail => Dimensions.root_slot(root) <> tail),
        Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Content.root_slot, rest), Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Dimensions.root_slot, rest), content_root_slots(rest))

def content_policy_slots(+policies: +List<Content.NativePolicy>) ->
  {Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Content.policy_slot, policies) == Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Dimensions.policy_slot, policies) : +List<Content.NativeSlot>}:
  match policies:
    case Nil{}: {==}
    case Con{+policy, +rest}:
      %Equal.sym(Content.NativeSlot, Content.policy_slot(policy), Dimensions.policy_slot(policy), content_policy_slot(policy)) :
        {_ <> Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Content.policy_slot, rest) == Dimensions.policy_slot(policy) <> Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Dimensions.policy_slot, rest) : +List<Content.NativeSlot>}
      Equal.cong((+List<Content.NativeSlot>), (+List<Content.NativeSlot>), (tail => Dimensions.policy_slot(policy) <> tail),
        Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Content.policy_slot, rest), Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Dimensions.policy_slot, rest), content_policy_slots(rest))

def content_native_slots(+prepared: Content.Prepared) ->
  {Content.native_slots(prepared) == Dimensions.native_slots(prepared) : +List<Content.NativeSlot>}:
  Content.Prepared{snapshot, tree, +roots, +policies} = prepared
  %Equal.sym((+List<Content.NativeSlot>), Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Content.root_slot, roots), Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Dimensions.root_slot, roots), content_root_slots(roots)) :
    {List.append(&2, Content.NativeSlot, _, Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Content.policy_slot, policies)) == List.append(&2, Content.NativeSlot, Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Dimensions.root_slot, roots), Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Dimensions.policy_slot, policies)) : +List<Content.NativeSlot>}
  Equal.cong((+List<Content.NativeSlot>), (+List<Content.NativeSlot>), (tail => List.append(&2, Content.NativeSlot, Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~Dimensions.root_slot, roots), tail)),
    Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Content.policy_slot, policies), Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~Dimensions.policy_slot, policies), content_policy_slots(policies))

def content_slot_member(+slots: +List<Content.NativeSlot>, +owner: String, +target: String) ->
  {Content.slot_member(slots, owner, target) == Dimensions.slot_member(slots, owner, target) : Bool}:
  match slots:
    case Nil{}:
      {==}
    case Con{Content.NativeSlot{+slot_owner, +slot_target}, +rest}:
      %Equal.sym(Bool, Content.slot_member(rest, owner, target), Dimensions.slot_member(rest, owner, target), content_slot_member(rest, owner, target)) :
        {(String.eq(slot_owner, owner) && String.eq(slot_target, target)) || _ == (String.eq(slot_owner, owner) && String.eq(slot_target, target)) || Dimensions.slot_member(rest, owner, target) : Bool}
      {==}

def content_duplicate_member(+found: Bool, +slot: Content.NativeSlot, +remaining: Maybe<&2, Content.NativeSlot>) ->
  {Content.duplicate_member(found, slot, remaining) == Dimensions.duplicate_member(found, slot, remaining) : Maybe<&2, Content.NativeSlot>}:
  match found:
    case True{}:
      {==}
    case False{}:
      {==}

def content_duplicate_native_slot(+slots: +List<Content.NativeSlot>) ->
  {Content.duplicate_native_slot(slots) == Dimensions.duplicate_native_slot(slots) : Maybe<&2, Content.NativeSlot>}:
  match slots:
    case Nil{}:
      {==}
    case Con{Content.NativeSlot{+owner, +target}, +rest}:
      %Equal.sym(Maybe<&2, Content.NativeSlot>, Content.duplicate_native_slot(rest), Dimensions.duplicate_native_slot(rest), content_duplicate_native_slot(rest)) :
        {Content.duplicate_member(Content.slot_member(rest, owner, target), Content.NativeSlot{owner, target}, _) == Dimensions.duplicate_member(Dimensions.slot_member(rest, owner, target), Content.NativeSlot{owner, target}, Dimensions.duplicate_native_slot(rest)) : Maybe<&2, Content.NativeSlot>}
      %Equal.sym(Bool, Content.slot_member(rest, owner, target), Dimensions.slot_member(rest, owner, target), content_slot_member(rest, owner, target)) :
        {Content.duplicate_member(_, Content.NativeSlot{owner, target}, Dimensions.duplicate_native_slot(rest)) == Dimensions.duplicate_member(Dimensions.slot_member(rest, owner, target), Content.NativeSlot{owner, target}, Dimensions.duplicate_native_slot(rest)) : Maybe<&2, Content.NativeSlot>}
      %Equal.sym(Maybe<&2, Content.NativeSlot>, Content.duplicate_member(Dimensions.slot_member(rest, owner, target), Content.NativeSlot{owner, target}, Dimensions.duplicate_native_slot(rest)), Dimensions.duplicate_member(Dimensions.slot_member(rest, owner, target), Content.NativeSlot{owner, target}, Dimensions.duplicate_native_slot(rest)), content_duplicate_member(Dimensions.slot_member(rest, owner, target), Content.NativeSlot{owner, target}, Dimensions.duplicate_native_slot(rest))) :
        {_ == Dimensions.duplicate_member(Dimensions.slot_member(rest, owner, target), Content.NativeSlot{owner, target}, Dimensions.duplicate_native_slot(rest)) : Maybe<&2, Content.NativeSlot>}
      {==}


def no_duplicate(+duplicate: Maybe<&2, Content.NativeSlot>) ->
  {Measurements.no_duplicate(duplicate) == Dimensions.no_duplicate(duplicate) : Bool}:
  match duplicate:
    case None{}: {==}
    case Some{+slot}: {==}

def complete_duplicate(+prepared: Content.Prepared) ->
  {Content.duplicate_native_slot(Content.native_slots(prepared)) == Dimensions.duplicate_native_slot(Dimensions.native_slots(prepared)) : Maybe<&2, Content.NativeSlot>}:
  Equal.trans((Maybe<&2, Content.NativeSlot>), Content.duplicate_native_slot(Content.native_slots(prepared)),
    Dimensions.duplicate_native_slot(Content.native_slots(prepared)), Dimensions.duplicate_native_slot(Dimensions.native_slots(prepared)),
    content_duplicate_native_slot(Content.native_slots(prepared)),
    Equal.cong((+List<Content.NativeSlot>), (Maybe<&2, Content.NativeSlot>), Dimensions.duplicate_native_slot,
      Content.native_slots(prepared), Dimensions.native_slots(prepared), content_native_slots(prepared)))

def duplicate_target_rejected(+prepared: Content.Prepared, +owner: String, +target: String) ->
  {SourceSource.reject_duplicate(Some{Content.NativeSlot{owner, target}}, prepared) == Dimensions.target_outcome(Some{Content.NativeSlot{owner, target}}, prepared) : Content.Preparation}:
  match prepared:
    case Content.Prepared{snapshot, tree, roots, policies}: {==}

def target_admission(+prepared: Content.Prepared, +duplicate: Maybe<&2, Content.NativeSlot>, +accepted: Bool,
  observed: {Measurements.native_targets_valid(prepared) == accepted : Bool},
  duplicate_known: {Content.duplicate_native_slot(Content.native_slots(prepared)) == duplicate : Maybe<&2, Content.NativeSlot>},
  coherent: {Dimensions.no_duplicate(duplicate) == accepted : Bool}) ->
  {SourceSource.native_targets_admitted(Categories.admit_checked(Content.Prepared, Measurements.native_targets_valid, prepared, accepted, observed), prepared) == Dimensions.target_outcome(duplicate, prepared) : Content.Preparation}:
  match duplicate accepted:
    case None{} True{}: {==}
    case None{} False{}:
      Logic.impossible({SourceSource.native_targets_admitted(Categories.admit_checked(Content.Prepared, Measurements.native_targets_valid, prepared, False{}, observed), prepared) == Dimensions.target_outcome(None{}, prepared) : Content.Preparation}, Equal.sym(Bool, True{}, False{}, coherent))
    case Some{Content.NativeSlot{+owner, +target}} True{}:
      Logic.impossible({SourceSource.native_targets_admitted(Categories.admit_checked(Content.Prepared, Measurements.native_targets_valid, prepared, True{}, observed), prepared) == Dimensions.target_outcome(Some{Content.NativeSlot{owner, target}}, prepared) : Content.Preparation}, coherent)
    case Some{Content.NativeSlot{+owner, +target}} False{}:
      Equal.trans(Content.Preparation,
        SourceSource.reject_duplicate(Content.duplicate_native_slot(Content.native_slots(prepared)), prepared),
        SourceSource.reject_duplicate(Some{Content.NativeSlot{owner, target}}, prepared),
        Dimensions.target_outcome(Some{Content.NativeSlot{owner, target}}, prepared),
        Equal.cong((Maybe<&2, Content.NativeSlot>), Content.Preparation, (value => SourceSource.reject_duplicate(value, prepared)),
          Content.duplicate_native_slot(Content.native_slots(prepared)), Some{Content.NativeSlot{owner, target}}, duplicate_known),
        duplicate_target_rejected(prepared, owner, target))

def admitted_targets(+prepared: Content.Prepared) ->
  {SourceSource.admit_native_targets(prepared) == Dimensions.admitted_targets(prepared) : Content.Preparation}:
  +duplicate = Content.duplicate_native_slot(Content.native_slots(prepared))
  Equal.trans(Content.Preparation, SourceSource.admit_native_targets(prepared), Dimensions.target_outcome(duplicate, prepared), Dimensions.admitted_targets(prepared),
    target_admission(prepared, duplicate, Measurements.native_targets_valid(prepared), {==}, {==},
      Equal.sym(Bool, Measurements.no_duplicate(duplicate), Dimensions.no_duplicate(duplicate), no_duplicate(duplicate))),
    Equal.cong((Maybe<&2, Content.NativeSlot>), Content.Preparation, (value => Dimensions.target_outcome(value, prepared)),
      duplicate, Dimensions.duplicate_native_slot(Dimensions.native_slots(prepared)), complete_duplicate(prepared)))

def sourcesource_single_root(+trees: +List<Model.Tree<Content.Value, Doc.DOMEvent>>, +snapshot: Content.Snapshot,
  +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {SourceSource.single_root(trees, snapshot, roots, policies) == Dimensions.single_root(trees, snapshot, roots, policies) : Content.Preparation}:
  match trees:
    case Nil{}:
      {==}
    case Con{+tree, Nil{}}:
      admitted_targets(Content.Prepared{snapshot, tree, roots, policies})
    case Con{+tree, Con{+next, +rest}}:
      {==}

def sourcesource_preparation(+result: SourceSource.Forest, +snapshot: Content.Snapshot) ->
  {SourceSource.preparation(result, snapshot) == Dimensions.preparation(result, snapshot) : Content.Preparation}:
  match result:
    case SourceSource.ReadyForest{+trees, +roots, +policies}:
      %Equal.sym(Content.Preparation, SourceSource.single_root(trees, snapshot, roots, policies), Dimensions.single_root(trees, snapshot, roots, policies), sourcesource_single_root(trees, snapshot, roots, policies)) :
        {_ == Dimensions.single_root(trees, snapshot, roots, policies) : Content.Preparation}
      {==}
    case SourceSource.MissingForest{+first, +remaining}:
      {==}
    case SourceSource.InvalidForest{+error}:
      {==}
