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
import ./browser/controls/CONTROLS.bend as Buttons
import ./browser/controls/PROGRAM.bend as Controls
import ./browser/document/SOURCE.bend as Source
import ./browser/appearance/MODEL.bend as Appearance
import ./browser/appearance/TYPOGRAPHY.bend as Typography
import ./browser/layout/SPACE.bend as Space
import ./interaction/IDENTITY.bend as Identity
import ./interaction/TYPES.bend as Interaction
import ./interaction/session/MODEL.bend as Session
import ./interaction/presentation/MODEL.bend as View
`;

const positive = `${imports}
import ./PROOF.bend as ProductionProof

def first() -> Buttons.IconButton:
  Buttons.IconButton{Identity.Place{"send"},
    Appearance.ordinary_button(Typography.Presentation{Typography.Body{}, Typography.Regular{}, Typography.Scale{0n}}),
    Controls.ArrowUp{}, Interaction.ApplicationInput{Session.ClockObserved{0}}, View.Available{}, "Send",
    Controls.Push{}, Controls.Geometry{Space.fixed_demand(32n, 32n), 16n, 8n, 0n},
    Controls.InFlow{}, Controls.NoHelp{}, Controls.Quiet{}}

def second() -> Buttons.IconButton:
  Buttons.IconButton{Identity.Place{"stop"},
    Appearance.destructive_button(Typography.Presentation{Typography.Support{}, Typography.Strong{}, Typography.Scale{100n}}),
    Controls.StopSquare{}, Interaction.ApplicationInput{Session.ClockObserved{1}}, View.Unavailable{"paused"}, "Stop",
    Controls.Toggle{True{}}, Controls.Geometry{Space.fixed_demand(48n, 40n), 20n, 4n, 0n},
    Controls.ComposerEnd{}, Controls.Tooltip{"Stop task", 100n, True{}, True{}, False{}}, Controls.Working{"Running"}}

def inspect(node: Source.Node) -> Bool:
  Buttons.icon_button_centered(node)

def main() -> Bool:
  first_ok = inspect(Buttons.icon_button_source(first()))
  changed = Buttons.icon_button_resize(Buttons.icon_button_replace_icon(second(), Controls.PlayTriangle{}),
    Controls.Geometry{Space.fixed_demand(56n, 44n), 24n, 6n, 0n})
  second_ok = inspect(Buttons.icon_button_source(changed))
  Bool.and(first_ok, second_ok)
`;

const ordinaryNode = `${imports}
def ordinary() -> Source.Node:
  Source.Text{Identity.Place{"ordinary"}, "A legal general source", Source.InheritFont{}, Typography.NormalAnywhere{}}

def main() -> Source.Node:
  ordinary()
`;

async function checkout(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-icon-button-'));
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

test('public icon-button construction executes with production evidence and rejects a general source node', { timeout: 300_000 }, async t => {
  const { directory, compile } = await checkout(t);
  await writeFile(path.join(directory, 'client.bend'), positive);
  accepted(compile('client.bend'));
  const executed = compile('client.bend', false);
  accepted(executed);
  assert.match(executed.stdout, /\bTrue\{\}/);

  await writeFile(path.join(directory, 'ordinary.bend'), ordinaryNode);
  accepted(compile('ordinary.bend'));
  await writeFile(path.join(directory, 'rejected.bend'), ordinaryNode.replace('  ordinary()\n', '  Buttons.icon_button_source(ordinary())\n'));
  const rejected = compile('rejected.bend');
  const diagnostic = rejected.stdout + rejected.stderr;
  assert.equal(rejected.error, undefined, 'A compiler timeout is not a type boundary');
  assert.notEqual(rejected.status, 0, 'The family interpreter accepted Source.Node');
  assert.match(diagnostic, /- expected\s*:\s*Buttons\.IconButton\s*\n- observed\s*:\s*Source\.Node\b/);
  assert.doesNotMatch(diagnostic, /undefined (?:reference|name)|unresolved import|cannot (?:find|resolve).*import|unsupported syntax|syntax error/i);
});

test('production obligations reject type-correct button, glyph and SVG centering mutations', { timeout: 600_000 }, async t => {
  const { directory, compile } = await checkout(t);
  accepted(compile('PROOF.bend'));
  const mutations = [
    ['browser/controls/CONTROLS.bend',
      'action_alignment(value), Spatial.Centered{}), List.append',
      'action_alignment(value), Spatial.Leading{}), List.append', /icon_button_centered/],
    ['browser/controls/authored-primitives.bend',
      'Source.Style{Source.Layout{Model.Horizontal{}, Spatial.Centered{}, Spatial.Centered{},',
      'Source.Style{Source.Layout{Model.Horizontal{}, Spatial.Leading{}, Spatial.Centered{},', /icon_button_centered/],
    ['browser/layout/RENDERER.bend',
      'case Spatial.Centered{}: Nat.div(Nat.sub(available, size), 2n)',
      'case Spatial.Centered{}: Nat.sub(available, size)', /centered_drawing_offset|centered_drawing_styles/],
  ];
  for (const [filename, before, after, obligation] of mutations) {
    const target = path.join(directory, filename);
    const original = await readFile(target, 'utf8');
    assert.equal(original.split(before).length, 2, `${filename}: missing or ambiguous mutation anchor`);
    try {
      await writeFile(target, original.replace(before, after));
      await writeFile(path.join(directory, 'TYPECHECK.bend'), `import ./${filename} as Subject\n`);
      accepted(compile('TYPECHECK.bend'));
      const rejected = compile('PROOF.bend');
      assert.equal(rejected.error, undefined, 'A compiler timeout is not proof rejection');
      assert.notEqual(rejected.status, 0, `The production proof accepted ${filename}: ${after}`);
      assert.match(rejected.stdout + rejected.stderr, obligation);
    } finally {
      await writeFile(target, original);
    }
  }
});
