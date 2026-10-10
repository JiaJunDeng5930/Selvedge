import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const bend = path.join(root, '.build/bend/bin/bend');
const imports = `import Base
import ./PROOF.bend as ProductionProof
import ./bendlib/categories.bend as Categories
import ./browser/controls/CONTROLS.bend as Authored
import ./browser/controls/PROGRAM.bend as Controls
import ./browser/document/SOURCE.bend as Source
import ./browser/document/MODEL.bend as Doc
import ./browser/appearance/MODEL.bend as Appearance
import ./browser/appearance/DESIGN.bend as Design
import ./browser/appearance/TYPOGRAPHY.bend as Typography
import ./browser/layout/SPACE.bend as Space
import ./interaction/IDENTITY.bend as Identity
import ./interaction/TYPES.bend as Interaction
import ./interaction/session/MODEL.bend as Session
import ./interaction/presentation/MODEL.bend as View
import ./interaction/presentation/SURFACE.bend as Surface
import ./features/board/MODEL.bend as Board
import ./browser/runtime/frontend-utility.bend as Recovery
`;

const generic = `${imports}

def consume_input(-category: Authored.InputObservation -> Type, -observation: Authored.InputObservation, -evidence: category(observation)) -> Bool:
  True{}

def apply_input(-category: Authored.InputObservation -> Type, inclusion: Categories.Inclusion<Authored.InputObservation, Authored.authored_input, category>, -observation: Authored.InputObservation, evidence: Authored.authored_input(observation)) -> category(observation):
  Categories.Inclusion{derive} = inclusion
  derive(observation, evidence)

def input_client(-category: Authored.InputObservation -> Type, inclusion: Categories.Inclusion<Authored.InputObservation, Authored.authored_input, category>, member: Categories.Membership<Authored.InputObservation, Authored.authored_input>) -> Bool:
  Categories.Membership{observation, evidence} = member
  consume_input(category, observation, apply_input(category, inclusion, observation, evidence))

def consume_movable(-category: Authored.MovableObservation -> Type, -observation: Authored.MovableObservation, -evidence: category(observation)) -> Bool:
  True{}

def apply_movable(-category: Authored.MovableObservation -> Type, inclusion: Categories.Inclusion<Authored.MovableObservation, Authored.authored_movable, category>, -observation: Authored.MovableObservation, evidence: Authored.authored_movable(observation)) -> category(observation):
  Categories.Inclusion{derive} = inclusion
  derive(observation, evidence)

def movable_client(-category: Authored.MovableObservation -> Type, inclusion: Categories.Inclusion<Authored.MovableObservation, Authored.authored_movable, category>, member: Categories.Membership<Authored.MovableObservation, Authored.authored_movable>) -> Bool:
  Categories.Membership{observation, evidence} = member
  consume_movable(category, observation, apply_movable(category, inclusion, observation, evidence))

def arbitrary_client(+key: Identity.Key, +input: Controls.FormInput, +movable: Controls.MovableControl, +visual: Design.Style, +parameters: Design.LayoutParameters) -> Bool:
  requested = input_client(Authored.input_requested, Authored.input_is_requested(), Authored.construct_input(key, input, visual, parameters))
  a = input_client(Authored.input_binding, Authored.input_is_bound(), Authored.construct_input(key, input, visual, parameters))
  b = input_client(Authored.input_content, Authored.input_is_content(), Authored.construct_input(key, input, visual, parameters))
  c = input_client(Authored.input_protocol, Authored.input_is_protocol(), Authored.construct_input(key, input, visual, parameters))
  d = movable_client(Authored.movable_destinations, Authored.movable_is_destinations(), Authored.construct_movable(key, movable, visual, parameters))
  e = movable_client(Authored.movable_protocol, Authored.movable_is_protocol(), Authored.construct_movable(key, movable, visual, parameters))
  Bool.and(requested, Bool.and(a, Bool.and(b, Bool.and(c, Bool.and(d, e)))))
`;

const recoveryGeneric = `

def consume_recovery(-category: Recovery.RecoveryObservation -> Type, -observation: Recovery.RecoveryObservation, -evidence: category(observation)) -> Bool:
  True{}

def apply_recovery(-category: Recovery.RecoveryObservation -> Type, inclusion: Categories.Inclusion<Recovery.RecoveryObservation, Recovery.authored_recovery, category>, -observation: Recovery.RecoveryObservation, evidence: Recovery.authored_recovery(observation)) -> category(observation):
  Categories.Inclusion{derive} = inclusion
  derive(observation, evidence)

def recovery_client(-category: Recovery.RecoveryObservation -> Type, inclusion: Categories.Inclusion<Recovery.RecoveryObservation, Recovery.authored_recovery, category>, member: Categories.Membership<Recovery.RecoveryObservation, Recovery.authored_recovery>) -> Bool:
  Categories.Membership{observation, evidence} = member
  consume_recovery(category, observation, apply_recovery(category, inclusion, observation, evidence))

def arbitrary_recovery(+request: Recovery.RecoveryButton) -> Bool:
  a = recovery_client(Recovery.recovery_native, Recovery.authored_recovery_native(), Recovery.construct_recovery(request))
  b = recovery_client(Recovery.recovery_protocol, Recovery.authored_recovery_protocol(), Recovery.construct_recovery(request))
  c = recovery_client(Recovery.recovery_centered, Recovery.authored_recovery_centered(), Recovery.construct_recovery(request))
  Bool.and(a, Bool.and(b, c))
`;

const concrete = `${generic}${recoveryGeneric}
def key() -> Identity.Key:
  Identity.Place{"known-control"}

def visual() -> Design.Style:
  Appearance.ordinary_button(Typography.Presentation{Typography.Body{}, Typography.Regular{}, Typography.Scale{0n}})

def parameters() -> Design.LayoutParameters:
  Design.LayoutParameters{1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n}

def input() -> Controls.FormInput:
  Controls.FormInput{Surface.DirectoryBrowserLocation{"retained-value"}, "Known input", Controls.TextInput{}, Controls.AccessibleOnly{}, View.Unavailable{"paused"}}

def action() -> Interaction.Input:
  Interaction.ApplicationInput{Session.ClockObserved{0}}

def movable() -> Controls.MovableControl:
  Controls.MovableControl{[Surface.Placement{"available", "Available", action(), View.Available{}}, Surface.Placement{"unavailable", "Unavailable", action(), View.Unavailable{"paused"}}],
    View.CardFace{1n, "Card", "", Board.NoPriority{}, False{}, "", "", Nil{}, "", ""}, "Move card", Controls.ArrowUp{}, Controls.Geometry{Space.fixed_demand(1n, 1n), 1n, 1n, 0n}}

def native_input(node: Source.Node) -> Bool:
  match node:
    case Source.Field{key, Source.TextField{}, style, attributes, value, placeholder, options, policy, name, False{}, Doc.EditText{binding}, Nil{}}:
      Bool.and(String.eq(value, "retained-value"), Bool.and(String.eq(name, "Known input"), String.eq(binding, Identity.encode(key))))
    case _: False{}

def native_movable(node: Source.Node) -> Bool:
  match node:
    case Source.Field{key, Source.SelectField{}, style, attributes, value, placeholder,
      Con{Source.Choice{empty_value, empty_label, True{}}, Con{Source.Choice{target, label, False{}}, Nil{}}}, policy, name, True{}, Doc.SelectDestination{binding}, Nil{}}:
      Bool.and(String.eq(target, "available"), Bool.and(String.eq(label, "Available"), String.eq(binding, Identity.encode(key))))
    case _: False{}

def main() -> Bool:
  Bool.and(arbitrary_recovery(Recovery.RecoveryButton{Typography.Presentation{Typography.Body{}, Typography.Regular{}, Typography.Scale{0n}}, "failure"}),
    Bool.and(arbitrary_client(key(), input(), movable(), visual(), parameters()),
    Bool.and(native_input(Authored.input(key(), input(), visual(), parameters())), native_movable(Authored.movable_choices(key(), movable(), visual(), parameters())))))
`;

async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-control-categories-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const name of await readdir(root)) {
    if (name.endsWith('.bend')) await cp(path.join(root, name), path.join(directory, name));
  }
  for (const name of ['bendlib', 'browser', 'interaction', 'harness', 'features']) {
    await cp(path.join(root, name), path.join(directory, name), { recursive: true });
  }
  await writeFile(path.join(directory, 'CLIENT.bend'), concrete);
  const compile = (checkOnly = true) => spawnSync(bend, ['CLIENT.bend', ...(checkOnly ? ['--check-only'] : [])], {
    cwd: directory, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024,
    env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
  return { directory, compile };
}

function accepted(result, checkOnly = true) {
  assert.equal(result.error, undefined, 'A compiler timeout is not acceptance');
  assert.equal(result.signal, null, 'A compiler crash is not acceptance');
  assert.equal(result.status, 0, result.stdout + result.stderr);
  if (checkOnly) assert.match(result.stdout, /ALL PROOFS CHECK/);
}

test('generic input and movable clients project production memberships and execute native fields', { timeout: 180_000 }, async t => {
  assert.equal(compiler(), bend, 'Use the pinned workspace compiler');
  const { compile } = await fixture(t);
  accepted(compile());
  const executed = compile(false);
  accepted(executed, false);
  assert.match(executed.stdout, /\bTrue\{\}/);
});

const mutations = [
  ['input-value', 'interpret_input_field', 'attributes, value, placeholder, options, policy, field_name, enabled, first, remaining}', 'attributes, "changed-value", placeholder, options, policy, field_name, enabled, first, remaining}', /input_widget_evidence|input_evidence|Location: request_content_projection\n/],
  ['input-policy', 'interpret_input_field', 'attributes, value, placeholder, options, policy, field_name, enabled, first, remaining}', 'attributes, value, placeholder, options, Source.FieldPolicy{2n, 2n, 2n}, field_name, enabled, first, remaining}', /input_widget_evidence|input_evidence|Location: request_content_projection\n/],
  ['movable-filter', 'movable_choices', 'Source.Choice{"", "Move to…", True{}} <> placement_choices(destinations)', 'Source.Choice{"", "Move to…", True{}} <> (Source.Choice{"unavailable", "Unavailable", False{}} <> placement_choices(destinations))', /movable_evidence|Location: RuleSourceRules\.movement_field_has_own_identity\n/],
];

for (const [name, scope, before, after, obligation] of mutations) {
  test(`production evidence rejects the ${name} source mutation`, { timeout: 180_000 }, async t => {
    const { directory, compile } = await fixture(t);
    // The same entry must succeed before its mutation can establish rejection.
    accepted(compile());
    const target = path.join(directory, 'browser/controls/CONTROLS.bend');
    const source = await readFile(target, 'utf8');
    const start = source.indexOf(`def ${scope}(`);
    assert.ok(start >= 0, `Missing mutation function ${scope}`);
    const next = source.indexOf('\ndef ', start + 1);
    const end = next < 0 ? source.length : next;
    const body = source.slice(start, end);
    assert.equal(body.split(before).length, 2, `Ambiguous mutation anchor in ${scope}`);
    await writeFile(target, source.slice(0, start) + body.replace(before, after) + source.slice(end));
    const result = compile();
    const diagnostic = result.stdout + result.stderr;
    assert.equal(result.error, undefined, 'A timeout does not establish proof rejection');
    assert.equal(result.signal, null, 'A crash does not establish proof rejection');
    assert.equal(result.status, 1, diagnostic);
    assert.match(diagnostic, /SOME PROOFS FAIL/);
    assert.match(diagnostic, obligation);
    assert.match(diagnostic, /expected\s*:/);
    assert.match(diagnostic, /observed\s*:/);
    assert.doesNotMatch(diagnostic, /TYPE ERROR|TYPE MISMATCH|undefined (?:reference|name)|unresolved import|syntax error|stack overflow|segmentation fault|panic|TODOs found/i);
  });
}

test('production recovery evidence rejects misalignment of its emitted refresh glyph', { timeout: 180_000 }, async t => {
  const { directory, compile } = await fixture(t);
  accepted(compile());
  const target = path.join(directory, 'browser/runtime/frontend-utility.bend');
  const source = await readFile(target, 'utf8');
  const before = 'AuthoredControls.glyph(Identity.part(retry_key(), "icon"), Controls.Refresh{}, Appearance.ordinary_button(font), 16n)';
  const after = 'Source.Glyph{Identity.part(retry_key(), "icon"), MutationIcons.drawing(Controls.Refresh{}, 16n), mutation_misaligned(Factory.glyph_style(Appearance.ordinary_button(font), 16n, 16n))}';
  assert.equal(source.split(before).length, 2, 'Recovery must have one actual refresh glyph');
  // Mutate only the emitted glyph; retain the production centered predicate.
  const helper = `

def mutation_misaligned(style: Source.Style) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  Source.Style{Source.Layout{direction, main, Spatial.Leading{}, frame, width, height, minimum, scroll, position}, font, chrome, states}
`;
  const recoveryDeclaration = 'def recovery_source(';
  assert.equal(source.split(recoveryDeclaration).length, 2, 'Recovery must have one source producer');
  await writeFile(target, source.replace('import Base\n', 'import Base\nimport ../appearance/ICONS.bend as MutationIcons\n').replace(recoveryDeclaration, helper + '\n' + recoveryDeclaration).replace(before, after));
  const result = compile();
  const diagnostic = result.stdout + result.stderr;
  assert.equal(result.error, undefined, 'A timeout does not establish recovery proof rejection');
  assert.equal(result.signal, null, 'A crash does not establish recovery proof rejection');
  assert.equal(result.status, 1, diagnostic);
  assert.match(diagnostic, /SOME PROOFS FAIL/);
  assert.match(diagnostic, /Location: (?:recovery_evidence|Rule\.frontend_utility_evidence)\n/);
  if (/Location: Rule\.frontend_utility_evidence\n/.test(diagnostic)) {
    assert.match(diagnostic, /expected\s*:\s*Source\.Control/);
    assert.match(diagnostic, /observed\s*:\s*Source\.Control/);
  } else {
    assert.match(diagnostic, /expected\s*:\s*False\{\}/);
    assert.match(diagnostic, /observed\s*:\s*True\{\}/);
  }
  assert.doesNotMatch(diagnostic, /TYPE ERROR|TYPE MISMATCH|undefined (?:reference|name)|unresolved import|syntax error|stack overflow|segmentation fault|panic|TODOs found/i);
});
