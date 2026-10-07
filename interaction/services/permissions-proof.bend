import Base
import ./permissions-laws.bend as Rule
import ./CONTEXT.bend as Context
import ../presentation/MODEL.bend as V
import ../../harness/DOMAIN.bend as D

def sandboxed_network(network: Bool) -> {Context.network_summary(D.Sandboxed{}, network) == V.execution_network_summary(network) : String}:
  match network:
    case True{}: {==}
    case False{}: {==}

def Rule.evidence():
  Rule.Requirements{
    mode => {==},
    network => {==},
    mode => {==},
    sandboxed_network,
    task => workspace => mode => network => approval => project => guidance => access => profiles => {==},
    task => workspace => mode => network => approval => project => guidance => access => profiles => {==},
    origin => project => workspace => sandbox => approval => guidance => profiles => {==},
    origin => project => workspace => sandbox => approval => guidance => profiles => {==}}
