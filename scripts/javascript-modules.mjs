import { parse } from 'acorn';

// Split one official js_lib emission into self-contained entry modules. Keeping
// all Identifier uses is conservative: a shadowed name can retain extra code,
// but cannot remove a dependency. The pinned backend emits closed declarations.
export function javascriptModules(library) {
  const marker = '// Program\n// =======\n\n';
  const start = library.indexOf(marker);
  if (start < 0) throw new Error('Joint JavaScript compilation requires the pinned program marker');
  const runtime = library.slice(0, start + marker.length);
  const program = library.slice(start + marker.length);
  const tree = parse(program, { ecmaVersion: 2024, sourceType: 'module' });
  const exported = tree.body.at(-1);
  if (exported?.type !== 'ExportDefaultDeclaration' || exported.declaration.type !== 'ObjectExpression') {
    throw new Error('Joint JavaScript compilation requires the pinned export object');
  }
  const exports = new Map();
  for (const property of exported.declaration.properties) {
    if (property.type !== 'Property' || property.computed || property.kind !== 'init'
        || property.method || property.key.type !== 'Literal' || typeof property.key.value !== 'string'
        || exports.has(property.key.value)) {
      throw new Error('Joint JavaScript compilation encountered an unsupported export');
    }
    exports.set(property.key.value, property.value);
  }
  const declarations = new Map();
  const statements = tree.body.slice(0, -1).map(statement => {
    const names = statement.type === 'FunctionDeclaration' && statement.id
      ? [statement.id.name]
      : statement.type === 'VariableDeclaration' && statement.kind === 'const'
        && statement.declarations.every(value => value.id.type === 'Identifier')
        ? statement.declarations.map(value => value.id.name) : null;
    if (!names) throw new Error(`Joint JavaScript compilation encountered an unsupported declaration: ${statement.type}`);
    const declaration = { statement, names, references: identifiers(statement) };
    for (const name of names) {
      if (declarations.has(name)) throw new Error(`Joint JavaScript compilation encountered a duplicate declaration: ${name}`);
      declarations.set(name, declaration);
    }
    return declaration;
  });

  return definitions => {
    const selected = Object.entries(definitions).map(([original, qualified]) => {
      const expression = exports.get(qualified);
      if (!expression) throw new Error(`Joint JavaScript compilation did not export: ${qualified}`);
      return { original, expression };
    });
    const needed = new Set();
    const pending = selected.flatMap(({ expression }) => [...identifiers(expression)]);
    for (let index = 0; index < pending.length; index++) {
      const declaration = declarations.get(pending[index]);
      if (!declaration || needed.has(declaration)) continue;
      needed.add(declaration);
      pending.push(...declaration.references);
    }
    const source = runtime + statements.filter(declaration => needed.has(declaration))
      .map(({ statement }) => program.slice(statement.start, statement.end)).join('\n\n')
      + '\nexport default {\n' + selected.map(({ original, expression }) =>
        `  ${JSON.stringify(original)}: ${program.slice(expression.start, expression.end)},`).join('\n') + '\n};\n';
    return source;
  };
}

function identifiers(node) {
  const found = new Set();
  const pending = [node];
  while (pending.length) {
    const current = pending.pop();
    if (current.type === 'Identifier') found.add(current.name);
    for (const value of Object.values(current)) {
      if (Array.isArray(value)) {
        for (const child of value) if (child && typeof child.type === 'string') pending.push(child);
      } else if (value && typeof value.type === 'string') pending.push(value);
    }
  }
  return found;
}
