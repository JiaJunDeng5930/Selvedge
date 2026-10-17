import Base
import ../DOMAIN.bend as D
import ../reasoning/MODEL.bend as Reasoning
import ../../bendlib/json.bend as J

def encode(model: D.Model) -> J.Json:
  D.Model{D.Profile{profile, provider, name, policy, options}, reasoning} = model
  J.Object{[J.Field{"profile", J.Text{profile}}, J.Field{"provider", J.Text{provider}},
    J.Field{"name", J.Text{name}}, J.Field{"reasoning", J.Text{reasoning}}, J.Field{"adaptive_reasoning", Reasoning.json(policy)}]}
