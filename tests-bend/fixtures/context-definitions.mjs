import assert from 'node:assert/strict';
import { cp, mkdir, readdir, readFile, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { modify, replaceOnce } from '../locality-support.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
export const definitionAssembly = 'harness/context/KINDS.bend';

async function freezeHost(copy, directory = 'host') {
  for (const entry of await readdir(path.join(root, directory), { withFileTypes: true })) {
    const relative = path.join(directory, entry.name);
    if (relative === 'host/public/generated') continue;
    if (entry.isDirectory()) await freezeHost(copy, relative);
    else copy.originals.set(relative, await readFile(path.join(root, relative)));
  }
}

// The specimen adds only definitions and registration. Production consumers,
// proofs, existing definitions and the actual host observer stay byte-identical.
export async function extendTrackedContexts(copy) {
  await freezeHost(copy);
  await cp(path.join(root, 'host'), path.join(copy.directory, 'host'), { recursive: true });
  await symlink(path.join(root, 'node_modules'), path.join(copy.directory, 'node_modules'), 'dir');
  await modify(copy.directory, definitionAssembly, source => {
    const registered = replaceOnce(source, 'SkillInformation.definition()]', 'SkillInformation.definition(), review_notes(), review_policy()]');
    return replaceOnce(registered, 'def definitions()', `def review_notes() -> C.Definition:
  C.text_context("review_notes", "Workspace review guidance.",
    C.WorkspaceScope{}, C.WorkspaceFile{".review.md"},
    [C.IdentityField{"workspace", C.WorkspaceRoot{}, True{}}])

def review_policy() -> C.Definition:
  C.record_context("review_policy", "Workspace review metadata; body is excluded.",
    C.WorkspaceScope{}, C.WorkspaceFile{".review-policy.md"},
    [C.IdentityField{"workspace", C.WorkspaceRoot{}, True{}}, C.IdentityField{"path", C.SourcePath{}, True{}}],
    [C.TextField{"runner", C.Metadata{"runner"}, True{}},
     C.TextField{"rationale", C.Metadata{"rationale"}, True{}},
     C.TextField{"mode", C.Metadata{"mode"}, False{}}, C.IdentityValue{"path", "path"}])

def definitions()`);
  });
  const entry = path.join(copy.directory, 'CONTEXT_FIXTURE.bend');
  await writeFile(entry, `import Base
import ./KERNEL.bend as K
import ./HOST.bend as H
import ./harness/MODEL.bend as M
import ./harness/transport/MODEL.bend as I
import ./bendlib/json.bend as J

def initial() -> M.World():
  K.initial()

def packet(tokens: +List<String>, world: M.World()) -> I.Output:
  K.packet(tokens, world)

def state(output: I.Output) -> M.World():
  K.state(output)

def envelope(output: I.Output) -> J.Json:
  K.envelope(output)

def show(value: J.Json) -> Result<&2, &2, String, String>:
  K.show(value)

def run(operation: String, tokens: +List<String>) -> String:
  H.run(operation, tokens)
`);
  const module = path.join(copy.directory, 'host/public/generated/host-model.mjs');
  await mkdir(path.dirname(module), { recursive: true });
  assert.equal(copy.originals.has('harness/context/MODEL.bend'), true);
  assert.equal(copy.originals.has('host/context-sources.mjs'), true);
  return { entry, module };
}
