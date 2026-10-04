import Base
import ./physical-content.bend as Content
import ./physical-content-rules.bend as Rules
import ./physical-space.bend as SpaceModel

def choose_receipt(matches: Bool, +observation: Content.Observation,
  +tail_result: Maybe<&2, Content.Observation>) -> Maybe<&2, Content.Observation>:
  match matches:
    case True{}: Some{observation}
    case False{}: tail_result

def scan(observations: +List<Content.Observation>, +request: Content.Request) -> Maybe<&2, Content.Observation>:
  match observations:
    case Nil{}: None{}
    case Con{+observation, rest}:
      choose_receipt(Rules.observation_matches(request, observation), observation, scan(rest, request))

def find(request: Content.Request, observations: +List<Content.Observation>) -> Maybe<&2, Content.Observation>:
  scan(observations, request)

def choose_sample(active: Bool, +sample: SpaceModel.HeightSample,
  +tail_result: +List<SpaceModel.HeightSample>) -> +List<SpaceModel.HeightSample>:
  match active:
    case True{}: sample <> tail_result
    case False{}: tail_result

def collect_height_samples(observations: +List<Content.Observation>, +generation: Nat) -> +List<SpaceModel.HeightSample>:
  match observations:
    case Nil{}: Nil{}
    case Con{Content.Observation{observed_generation, key, Content.Natural{}, minimum_width, preferred_width, content_height, reference_advance}, rest}:
      collect_height_samples(rest, generation)
    case Con{Content.Observation{observed_generation, key, Content.AtWidth{width}, minimum_width, preferred_width, content_height, reference_advance}, rest}:
      choose_sample(Nat.is_eq(generation, observed_generation), SpaceModel.HeightSample{key, width, content_height},
        collect_height_samples(rest, generation))

def height_samples(snapshot: Content.Snapshot, observations: +List<Content.Observation>) -> +List<SpaceModel.HeightSample>:
  Content.Snapshot{generation, source, default_font} = snapshot
  collect_height_samples(observations, generation)
