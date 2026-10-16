import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, cp, mkdtemp, readdir, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const bend = path.join(root, '.build/bend/bin/bend');
const imports = `import Base
import ./PROOF.bend as ProductionProof
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
`;

const concrete = `${imports}
def key() -> Identity.Key:
  Identity.Place{"known-control"}

def visual() -> Design.Style:
  Appearance.ordinary_button(Typography.Presentation{Typography.Body{}, Typography.Regular{}, Typography.Scale{0n}})

def parameters() -> Maybe<&2, Design.LayoutParameters>:
  Design.parameters(4096n, Typography.Scale{0n},
    Typography.Metric{"@font/body", 8n, 8n, 20n, 8n},
    Typography.Metric{"@font/activity-primary", 7n, 7n, 20n, 7n},
    Typography.Metric{"@font/activity-support", 6n, 6n, 18n, 6n})

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

def native_fields(admitted: Maybe<&2, Design.LayoutParameters>) -> Bool:
  match admitted:
    case Some{+parameters}:
      Bool.and(native_input(Authored.input(key(), input(), visual(), parameters)), native_movable(Authored.movable_choices(key(), movable(), visual(), parameters)))
    case None{}: False{}

def main() -> Bool:
  native_fields(parameters())
`;

async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-control-categories-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const name of await readdir(root)) {
    if (name.endsWith('.bend')) await cp(path.join(root, name), path.join(directory, name));
  }
  for (const name of ['bendlib', 'browser', 'interaction', 'harness', 'features', 'host/adapters']) {
    await mkdir(path.dirname(path.join(directory, name)), { recursive: true });
    await cp(path.join(root, name), path.join(directory, name), { recursive: true });
  }
  await writeFile(path.join(directory, 'CLIENT.bend'), concrete);
  const compile = () => spawnSync(bend, ['CLIENT.bend'], {
    cwd: directory, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024,
    env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
  return { directory, compile };
}

function accepted(result) {
  assert.equal(result.error, undefined, 'A compiler timeout is not acceptance');
  assert.equal(result.signal, null, 'A compiler crash is not acceptance');
  assert.equal(result.status, 0, result.stdout + result.stderr);
}

test('generic input and movable clients project production memberships and execute native fields', { timeout: 180_000 }, async t => {
  assert.equal(compiler(), bend, 'Use the pinned workspace compiler');
  const { compile } = await fixture(t);
  const executed = compile();
  accepted(executed);
  assert.match(executed.stdout, /\bTrue\{\}/);
});
