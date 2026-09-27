import Base
import ../../MODEL.bend as M
import ../architecture.bend as A
import ../operations.bend as Ops
import ../protocol.bend as Protocol

def control_frame(+task: M.Task, operation: M.Operation()) ->
  {M.task_phase(M.with_operations(Ops.replace(M.task_operations(task), operation), task)) == M.task_phase(task) : M.Phase}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def A.result_boundary():
  A.ResultBoundary{
    (plugin => pending => operation => value => error => task => world => {==}),
    (plugin => pending => operation => value => error => task => tasks => next_task => ticket => environment => limits => projects => {==}),
    (call => current => replacement => error => pending => {==}),
    (reason => call => value => error => pending => ({==}, {==})),
    (plugin => outcome => {==}),
    (expected => ticket => plugin => pending => value => error => task => operation => outcome => different =>
      Equal.cong(Bool, Protocol.Event, (same => Protocol.matching(same, Protocol.AfterResult{task, operation, outcome})),
        Nat.is_eq(ticket, expected), False{}, different)),
    (id => call => announced => ticket => plugin => pending => value => error => task => duplicate => duplicate_error => {==}),
    (history => owner => operation => call => value => error => plugin => outcome => ({==}, {==})),
    (task => operation => control_frame(task, operation)),
    (outcome => plugin => pending => operation => value => error => task => world => {==}),
    (value => error => pending => operation => task => world => {==}),
    (code => reason => pending => operation => task => world => {==}),
    (operation => value => error => task => world => {==}),
    (operation => value => error => task => world => {==}),
    (operation => value => error => task => world => ({==}, {==})),
    (plugin => pending => operation => value => error => task => world => {==}),
    (ticket => plugin => pending => value => error => outcome => operation => task => world => {==}),
    (call => remaining => value => error => task => world => {==}),
    (plugin => pending => call => remaining => value => error => task => tasks => next_task => ticket => environment => limits => projects => {==})}
