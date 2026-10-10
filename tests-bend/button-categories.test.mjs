import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const imports = `import Base
import ./PROOF.bend as ProductionProof
import ./browser/controls/BUTTONS.bend as Buttons
import ./browser/controls/PROGRAM.bend as Controls
import ./browser/document/SOURCE.bend as Source
import ./browser/appearance/MODEL.bend as Appearance
import ./browser/appearance/DESIGN.bend as Design
import ./browser/appearance/TYPOGRAPHY.bend as Typography
import ./browser/layout/SPACE.bend as Space
import ./interaction/IDENTITY.bend as Identity
import ./interaction/TYPES.bend as Interaction
import ./interaction/session/MODEL.bend as Session
import ./interaction/presentation/MODEL.bend as View
`;

const syntax = `${imports}
def key() -> Identity.Key:
  Identity.Place{"known-button"}

def visual() -> Design.Style:
  Appearance.ordinary_button(Typography.Presentation{Typography.Body{}, Typography.Regular{}, Typography.Scale{0n}})

def button(face: Controls.Face) -> Controls.Button:
  Controls.Button{Interaction.ApplicationInput{Session.ClockObserved{0}}, View.Unavailable{"paused"}, "Known button", face,
    Controls.Push{}, Controls.Geometry{Space.fixed_demand(40n, 40n), 16n, 4n, 0n}, Controls.InFlow{}, Controls.Quiet{}}
`;

const ordinaryNode = `${syntax}
def ordinary() -> Source.Node:
  Source.Text{key(), "A legal general source", Source.InheritFont{}, Typography.NormalAnywhere{}}

def main() -> Source.Node:
  ordinary()
`;

async function checkout(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-button-categories-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const filename of await readdir(root)) {
    if (filename.endsWith('.bend')) await cp(path.join(root, filename), path.join(directory, filename));
  }
  for (const name of ['bendlib', 'harness', 'features', 'interaction', 'browser']) {
    await cp(path.join(root, name), path.join(directory, name), { recursive: true });
  }
  const compile = (filename, checkOnly = true) => spawnSync(compiler(), [filename, ...(checkOnly ? ['--check-only'] : [])], {
    cwd: directory, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024,
    env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
  return { directory, compile };
}

function accepted(result) {
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stdout + result.stderr);
}

// The source entry deliberately leaves five production-provider laws pending.
// Any other diagnostic would invalidate the type-correct mutation premise.
function sourceTyped(result, source) {
  assert.equal(result.error, undefined);
  assert.equal(result.status, 1);
  assert.deepEqual([...source.matchAll(/^law (\w+):/gm)].map(match => match[1]),
    ['construction_evidence', 'icon_evidence', 'choice_evidence', 'picker_evidence', 'construct']);
  const diagnostic = (result.stdout + result.stderr).replace(/bend [\d.]+ is available: run bend update\n?$/, '');
  assert.equal(diagnostic, 'SOME PROOFS FAIL\nError: 5 TODOs found.\nThe code is incomplete, and not a valid proof yet.\n');
}

const positive = `${syntax}

def apply(-A: Buttons.Observation -> Type, -B: Buttons.Observation -> Type, inclusion: Buttons.Inclusion<Buttons.Observation, A, B>, observation: Buttons.Observation, evidence: A(observation)) -> B(observation):
  Buttons.Inclusion{derive} = inclusion
  derive(observation, evidence)

def consume(-category: Buttons.Observation -> Type, observation: Buttons.Observation, evidence: category(observation)) -> Bool:
  True{}

def consume_constructed(-category: Buttons.Observation -> Type, inclusion: Buttons.Inclusion<Buttons.Observation, Buttons.authored, category>, package: Buttons.Membership<Buttons.Observation, Buttons.authored>) -> Bool:
  Buttons.Membership{+observation, evidence} = package
  consume(category, observation, apply(Buttons.authored, category, inclusion, observation, evidence))

def client_key(observation: Buttons.Observation) -> Type:
  Buttons.Observation{identity, visual, button, node} = observation
  {identity == key() : Identity.Key}

def observation(+face: Controls.Face) -> Buttons.Observation:
  Buttons.Observation{key(), visual(), button(face), Buttons.source(key(), visual(), button(face))}

def main() -> Bool:
  checked_0 = consume_constructed(Buttons.native, Buttons.authored_native(), Buttons.construct(key(), visual(), button(Controls.SingleLineFace{"Run"})))
  checked_1 = consume_constructed(Buttons.available, Buttons.authored_available(), Buttons.construct(key(), visual(), button(Controls.SingleLineFace{"Run"})))
  checked_2 = consume_constructed(Buttons.named, Buttons.inclusion_compose(Buttons.Observation, Buttons.authored, Buttons.authored, Buttons.named, Buttons.inclusion_identity(Buttons.Observation, Buttons.authored), Buttons.authored_named()), Buttons.construct(key(), visual(), button(Controls.SingleLineFace{"Run"})))
  checked_3 = consume(Buttons.centered, observation(Controls.IconFace{Controls.ArrowUp{}}), apply(Buttons.icon, Buttons.centered, Buttons.icon_centered(), observation(Controls.IconFace{Controls.ArrowUp{}}), Buttons.icon_evidence(key(), visual(), button(Controls.IconFace{Controls.ArrowUp{}}), Controls.ArrowUp{}, {==})))
  checked_4 = consume(Buttons.icon_help, observation(Controls.IconFace{Controls.ArrowUp{}}), apply(Buttons.icon, Buttons.icon_help, Buttons.icon_help_inclusion(), observation(Controls.IconFace{Controls.ArrowUp{}}), Buttons.icon_evidence(key(), visual(), button(Controls.IconFace{Controls.ArrowUp{}}), Controls.ArrowUp{}, {==})))
  checked_5 = consume(Buttons.native, observation(Controls.IconFace{Controls.ArrowUp{}}), apply(Buttons.icon, Buttons.native, Buttons.inclusion_compose(Buttons.Observation, Buttons.icon, Buttons.authored, Buttons.native, Buttons.icon_authored(), Buttons.authored_native()), observation(Controls.IconFace{Controls.ArrowUp{}}), Buttons.icon_evidence(key(), visual(), button(Controls.IconFace{Controls.ArrowUp{}}), Controls.ArrowUp{}, {==})))
  checked_6 = consume(Buttons.leading, observation(Controls.ChoiceFace{"Run", None{}, None{}, False{}}), apply(Buttons.choice, Buttons.leading, Buttons.choice_leading(), observation(Controls.ChoiceFace{"Run", None{}, None{}, False{}}), Buttons.choice_evidence(key(), visual(), button(Controls.ChoiceFace{"Run", None{}, None{}, False{}}), "Run", None{}, None{}, False{}, {==})))
  checked_7 = consume(Buttons.native, observation(Controls.ChoiceFace{"Run", None{}, None{}, False{}}), apply(Buttons.choice, Buttons.native, Buttons.inclusion_compose(Buttons.Observation, Buttons.choice, Buttons.authored, Buttons.native, Buttons.choice_authored(), Buttons.authored_native()), observation(Controls.ChoiceFace{"Run", None{}, None{}, False{}}), Buttons.choice_evidence(key(), visual(), button(Controls.ChoiceFace{"Run", None{}, None{}, False{}}), "Run", None{}, None{}, False{}, {==})))
  checked_8 = consume(Buttons.leading, observation(Controls.PickerFace{None{}, "Run"}), apply(Buttons.picker, Buttons.leading, Buttons.picker_leading(), observation(Controls.PickerFace{None{}, "Run"}), Buttons.picker_evidence(key(), visual(), button(Controls.PickerFace{None{}, "Run"}), None{}, "Run", {==})))
  checked_9 = consume(Buttons.native, observation(Controls.PickerFace{None{}, "Run"}), apply(Buttons.picker, Buttons.native, Buttons.inclusion_compose(Buttons.Observation, Buttons.picker, Buttons.authored, Buttons.native, Buttons.picker_authored(), Buttons.authored_native()), observation(Controls.PickerFace{None{}, "Run"}), Buttons.picker_evidence(key(), visual(), button(Controls.PickerFace{None{}, "Run"}), None{}, "Run", {==})))
  checked_10 = consume(client_key, observation(Controls.SingleLineFace{"Run"}), apply((value => Buttons.intersection(Buttons.Observation, Buttons.authored, client_key, value)), client_key, Buttons.intersection_second(Buttons.Observation, Buttons.authored, client_key), observation(Controls.SingleLineFace{"Run"}), Buttons.Intersection{Buttons.construction_evidence(key(), visual(), button(Controls.SingleLineFace{"Run"})), {==}}))
  checked_11 = consume(Buttons.native, observation(Controls.SingleLineFace{"Run"}), apply((value => Buttons.intersection(Buttons.Observation, Buttons.authored, client_key, value)), Buttons.native, Buttons.inclusion_compose(Buttons.Observation, (value => Buttons.intersection(Buttons.Observation, Buttons.authored, client_key, value)), Buttons.authored, Buttons.native, Buttons.intersection_first(Buttons.Observation, Buttons.authored, client_key), Buttons.authored_native()), observation(Controls.SingleLineFace{"Run"}), Buttons.Intersection{Buttons.construction_evidence(key(), visual(), button(Controls.SingleLineFace{"Run"})), {==}}))
  checked_12 = consume(Buttons.glyph_centered, observation(Controls.IconFace{Controls.ArrowUp{}}), apply(Buttons.icon, Buttons.glyph_centered, Buttons.icon_glyph_centered(), observation(Controls.IconFace{Controls.ArrowUp{}}), Buttons.icon_evidence(key(), visual(), button(Controls.IconFace{Controls.ArrowUp{}}), Controls.ArrowUp{}, {==})))
  Bool.and(checked_0, Bool.and(checked_1, Bool.and(checked_2, Bool.and(checked_3, Bool.and(checked_4, Bool.and(checked_5, Bool.and(checked_6, Bool.and(checked_7, Bool.and(checked_8, Bool.and(checked_9, Bool.and(checked_10, Bool.and(checked_11, Bool.and(checked_12, True{})))))))))))))

`;

test('button clients consume production memberships, inclusions and open intersections', { timeout: 600_000 }, async t => {
  const { directory, compile } = await checkout(t);
  await writeFile(path.join(directory, 'CLIENT.bend'), positive);
  await writeFile(path.join(root, '.workpad/button-category-client.bend'), positive);
  accepted(compile('CLIENT.bend'));
  const result = compile('CLIENT.bend', false);
  accepted(result);
  assert.match(result.stdout, /True\{\}/);
});

test('typed button construction rejects raw nodes and independent help', { timeout: 600_000 }, async t => {
  const { directory, compile } = await checkout(t);
  await writeFile(path.join(directory, 'NODE.bend'), ordinaryNode);
  accepted(compile('NODE.bend'));
  const rejectedFixtures = [
    ['NODE.bend', ordinaryNode.replace('  ordinary()\n', '  Buttons.source(key(), visual(), ordinary())\n'), /- expected\s*:\s*Controls\.Button\s*\n- observed\s*:\s*Source\.Node\b/],
    ['HELP.bend', `${syntax}\ndef main() -> Controls.Button:\n  Controls.Button{Interaction.ApplicationInput{Session.ClockObserved{0}}, View.Available{}, "Run", Controls.IconFace{Controls.ArrowUp{}}, Controls.Push{}, Controls.Geometry{Space.fixed_demand(40n, 40n), 16n, 4n, 0n}, Controls.InFlow{}, Controls.NoHelp{}, Controls.Quiet{}}\n`, /(?:arity|fields|arguments|constructor|expected).*?(?:8|9|Button)|(?:8|9).*?(?:fields|arguments)/is],
  ];
  for (const [filename, fixture, requiredDiagnostic] of rejectedFixtures) {
    await writeFile(path.join(directory, filename), fixture);
    const result = compile(filename);
    const diagnostic = result.stdout + result.stderr;
    assert.equal(result.error, undefined, 'A timeout is not type rejection');
    assert.notEqual(result.status, 0, `${filename} accepted invalid construction`);
    assert.match(diagnostic, requiredDiagnostic);
    assert.doesNotMatch(diagnostic, /undefined (?:reference|name)|unresolved import|syntax error/i);
  }
});

test('production proofs reject type-correct button requirement mutations', { timeout: 600_000 }, async t => {
  const { directory, compile } = await checkout(t);
  accepted(compile('PROOF.bend'));
  const mutations = [
    ['browser/controls/BUTTONS.bend', 'Doc.Activate{UIIdentity.encode(key)}, Nil{}', 'Doc.Activate{"wrong-identity"}, Nil{}', /construction_evidence/],
    ['browser/controls/BUTTONS.bend', 'name, A.enabled(availability), Doc.Activate', 'name, True{}, Doc.Activate', /construction_evidence/],
    ['browser/controls/BUTTONS.bend', 'name, A.enabled(availability), Doc.Activate', '\"\", A.enabled(availability), Doc.Activate', /construction_evidence/],
    ['browser/controls/BUTTONS.bend', 'A.action_alignment(value), Spatial.Centered{}), List.append', 'Spatial.Leading{}, Spatial.Centered{}), List.append', /construction_evidence|icon_production/],
    ['browser/controls/BUTTONS.bend', 'A.action_alignment(value), Spatial.Centered{}), List.append', 'A.action_alignment(value), Spatial.Leading{}), List.append', /construction_evidence|icon_production/],
    ['browser/controls/PROGRAM.bend', 'Tooltip{text, 300n, True{}, True{}, False{}}', 'Tooltip{text, 300n, True{}, False{}, False{}}', /icon_production/],
    ['browser/controls/authored-primitives.bend', 'Model.Horizontal{}, Spatial.Centered{}, Spatial.Centered{}', 'Model.Horizontal{}, Spatial.Leading{}, Spatial.Centered{}', /icon_production/, 'glyph_style'],
    ['browser/controls/authored-primitives.bend', 'Model.Horizontal{}, Spatial.Centered{}, Spatial.Centered{}', 'Model.Horizontal{}, Spatial.Centered{}, Spatial.Leading{}', /icon_production/, 'glyph_style'],
    ['browser/controls/CONTROLS.bend', 'Source.Glyph{key, Iconography.drawing(icon, size), Factory.glyph_style(parent, size, size)}', 'Source.Text{key, "not-an-icon", Source.InheritFont{}, T.SingleLine{}}', /Rule\.project_presentation_evidence/, 'glyph'],
  ];
  for (const [filename, before, after, obligation, scope] of mutations) {
    const target = path.join(directory, filename);
    const original = await readFile(target, 'utf8');
    const start = scope ? original.indexOf(`def ${scope}(`) : 0;
    assert.ok(start >= 0, `${filename}: missing mutation function`);
    const next = scope ? original.indexOf('\ndef ', start + 1) : -1;
    const end = next < 0 ? original.length : next;
    const subject = original.slice(start, end);
    assert.equal(subject.split(before).length, 2, `${filename}: ambiguous mutation anchor`);
    try {
      await writeFile(target, original.slice(0, start) + subject.replace(before, after) + original.slice(end));
      await writeFile(path.join(directory, 'TYPECHECK.bend'), 'import ./browser/controls/BUTTONS.bend as Buttons\n');
      sourceTyped(compile('TYPECHECK.bend'), await readFile(path.join(directory, 'browser/controls/BUTTONS.bend'), 'utf8'));
      const result = compile('PROOF.bend');
      const diagnostic = result.stdout + result.stderr;
      assert.equal(result.error, undefined, 'A timeout is not proof rejection');
      assert.notEqual(result.status, 0, `Production accepted ${filename}: ${after}`);
      assert.match(diagnostic, obligation);
      assert.doesNotMatch(diagnostic, /TYPE ERROR|TYPE MISMATCH|undefined (?:reference|name)|syntax error/i);
      if (scope === 'glyph') {
        await writeFile(path.join(directory, 'BUTTONPROOF.bend'), 'import ./browser/controls/button-proof.bend as ButtonProof\n');
        const buttonResult = compile('BUTTONPROOF.bend');
        const buttonDiagnostic = buttonResult.stdout + buttonResult.stderr;
        assert.equal(buttonResult.error, undefined, 'A timeout is not icon proof rejection');
        assert.notEqual(buttonResult.status, 0, 'Icon production accepted a non-glyph node');
        assert.match(buttonDiagnostic, /icon_production/);
        assert.doesNotMatch(buttonDiagnostic, /TYPE ERROR|TYPE MISMATCH|undefined (?:reference|name)|unresolved import|syntax error/i);
      }
    } finally {
      await writeFile(target, original);
    }
  }
});
