import Base
import ./CONTENT.bend as Content
import ./physical-content-rules.bend as Rules

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
