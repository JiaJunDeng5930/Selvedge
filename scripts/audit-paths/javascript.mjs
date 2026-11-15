import ts from 'typescript';

const knownMethods = new Set([
  'map', 'flatMap', 'filter', 'slice', 'sort', 'toSorted', 'reverse', 'toReversed',
  'concat', 'find', 'findIndex', 'some', 'every', 'reduce', 'join',
  'values', 'keys', 'entries', 'stringifyJson', 'parseJson',
]);
const producers = new Set([
  'map', 'flatMap', 'filter', 'slice', 'sort', 'toSorted', 'reverse', 'toReversed',
  'concat', 'Array.from', 'Object.entries', 'Object.keys', 'Object.values',
  'Object.fromEntries', 'Set', 'Stringify', 'split',
]);
const tail = new Set(['length', 'some', 'every', 'find', 'findIndex', 'first', 'last']);
const stages = new Set(['filter', 'map', 'flatMap', 'slice', 'reduce', 'join', 'reverse', 'sort']);
const relations = new Set([
  'map/slice', 'filter/slice', 'slice/slice', 'flatMap/slice', 'Object.entries/Object.fromEntries',
  'Object.fromEntries/Object.entries', 'Set/Array.from', 'Stringify/Parse', 'Array.from/Set',
  'split/length', 'sort/first', 'slice/first', 'slice/last', 'toSorted/first',
]);
const chain = (producer, consumer) => relations.has(`${producer}/${consumer}`) ||
  tail.has(consumer) && !['Set', 'Stringify', 'Object.fromEntries'].includes(producer) ||
  stages.has(consumer) && ['map','flatMap','filter','slice','Object.entries','Object.values','Object.keys'].includes(producer);

function unwrap(node) {
  while (node && (ts.isParenthesizedExpression(node) || ts.isAsExpression(node)
      || ts.isNonNullExpression(node) || ts.isSatisfiesExpression(node))) node = node.expression;
  return node;
}
function resultPath(node) {
  if (ts.isCallExpression(node)) {
    const f = unwrap(node.expression);
    const source = node.arguments[0];
    if (ts.isPropertyAccessExpression(f)) {
      const attr = f.name.text;
      const object = ts.isIdentifier(f.expression) ? f.expression.text : '';
      const qualified = `${object}.${attr}`;
      if (['Object.entries','Object.keys','Object.values','Object.fromEntries','Array.from'].includes(qualified))
        return { name: qualified, input: source };
      if (qualified === 'JSON.stringify') return { name: 'Stringify', input: source };
      if (qualified === 'JSON.parse') return { name: 'Parse', input: source };
      if (knownMethods.has(attr) || attr === 'split') return { name: attr, input: f.expression };
    }
    if (ts.isIdentifier(f) && f.text === 'stringifyJson') return { name: 'Stringify', input: source };
    if (ts.isIdentifier(f) && f.text === 'parseJson') return { name: 'Parse', input: source };
  }
  if (ts.isPropertyAccessExpression(node) && node.name.text === 'length')
    return { name: 'length', input: node.expression };
  if (ts.isElementAccessExpression(node) && node.argumentExpression.getText() === '0')
    return { name: 'first', input: node.expression };
  if (ts.isNewExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === 'Set')
    return { name: 'Set', input: node.arguments?.[0] };
}
function owner(node) {
  for (let current = node.parent; current; current = current.parent) {
    if (ts.isFunctionDeclaration(current) || ts.isMethodDeclaration(current) || ts.isAccessor(current))
      return current.name?.getText() ?? '<function>';
    if ((ts.isArrowFunction(current) || ts.isFunctionExpression(current)) && ts.isVariableDeclaration(current.parent))
      return current.parent.name.getText();
  }
  return '<module>';
}
function origin(checker, expr, seen = new Set()) {
  expr = unwrap(expr);
  if (!expr) return;
  const direct = resultPath(expr);
  if (direct && producers.has(direct.name)) return { node: expr, op: direct.name, aliases: [] };
  if (!ts.isIdentifier(expr)) return;
  const symbol = checker.getSymbolAtLocation(expr);
  const declaration = symbol?.valueDeclaration;
  if (!declaration || seen.has(symbol) || !ts.isVariableDeclaration(declaration)
    || !ts.isVariableDeclarationList(declaration.parent) || !(declaration.parent.flags & ts.NodeFlags.Const)
    || expr.getSourceFile() !== declaration.getSourceFile()
    || expr.pos <= declaration.pos) return;
  seen.add(symbol);
  const upstream = origin(checker, declaration.initializer, seen);
  if (upstream) upstream.aliases.push({ name: expr.text, declaration, symbol });
  return upstream;
}

export function scanJavaScript(files) {
  const program = ts.createProgram(files, {
    allowJs: true, checkJs: true, noEmit: true, skipLibCheck: true,
    target: ts.ScriptTarget.ESNext, module: ts.ModuleKind.NodeNext,
  });
  const checker = program.getTypeChecker();
  const findings = [];
  for (const file of files) {
    const source = program.getSourceFile(file);
    const invalid = source && program.getSyntacticDiagnostics(source)[0];
    if (!source || invalid) {
      const detail = invalid && ts.flattenDiagnosticMessageText(invalid.messageText, ' ');
      throw new Error(`Cannot analyze ${file}${detail ? `: ${detail}` : ''}`);
    }
    const location = node => source.getLineAndCharacterOfPosition(node.getStart(source)).line + 1;
    const uses = new Map();
    const candidates = [];
    function visit(node) {
      if (ts.isIdentifier(node)) {
        const symbol = ts.isShorthandPropertyAssignment(node.parent)
          ? checker.getShorthandAssignmentValueSymbol(node.parent)
          : checker.getSymbolAtLocation(node);
        const declaration = symbol?.valueDeclaration;
        if (declaration && ts.isVariableDeclaration(declaration) &&
            declaration.name !== node && declaration.getSourceFile() === source) {
          if (!uses.has(symbol)) uses.set(symbol, []);
          uses.get(symbol).push(location(node));
        }
      }
      const sink = resultPath(node);
      if (sink?.input) {
        const from = origin(checker, sink.input);
        if (from && chain(from.op, sink.name)) candidates.push({ node, sink, from });
      }
      ts.forEachChild(node, visit);
    }
    visit(source);
    for (const { node, sink, from } of candidates) {
      findings.push({
        file, function: owner(node), line: location(node), producer: from.op,
        producerLine: location(from.node), consumer: sink.name, classification: 'candidate',
        bindings: from.aliases.map(({ name, declaration, symbol }) => ({
          name, line: location(declaration), useLines: uses.get(symbol) ?? [],
        })),
      });
    }
  }
  return { files: files.length, findings };
}
