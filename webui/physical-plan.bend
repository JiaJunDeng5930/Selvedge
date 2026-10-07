import Base
import ./physical-content.bend as Content
import ./physical-allocation.bend as Allocation

type ProbeMode is Data:
  Measure{}
  TargetsOnly{}

type Job is Data:
  Job{request: Content.Request, roots: +List<Content.AllocatedNative>, mode: ProbeMode}

type Plan is Data:
  Awaiting{generation: Nat, first: Job, remaining: +List<Job>}
  Ready{world: Content.AllocatedWorld}
  Infeasible{failure: Allocation.Failure}
  Invalid{error: Content.Error}
