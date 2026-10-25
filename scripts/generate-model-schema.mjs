import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

/** Emit checked consumers from the same executable declarations as the Rocq boundary. */
export async function generateModelSchema(root) {
  const { call } = await import(`${pathToFileURL(path.join(root, '.build/schema-model.mjs'))}?schema=${Date.now()}`);
  const schema = JSON.parse(call('schema', '{}')).value;
  const enums = new Map();
  const q = JSON.stringify;
  function type(kind, safe = false) {
    if (typeof kind === 'string') return ({ text: 'string', boolean: 'boolean', natural: safe ? 'number' : 'DomainNatural',
      integer: 'DomainInteger', decimal: 'JsonNumber | number', json: 'JsonValue' })[kind];
    if (kind.array) return `Array<${type(kind.array)}>`;
    if (kind.optional) return `${type(kind.optional, safe)} | null`;
    return kind.enum.map(q).join(' | ');
  }
  function decoder(kind, value, safe = false) {
    if (typeof kind === 'string') return `${({ text: 'decodeText', boolean: 'decodeBoolean', natural: safe ? 'decodeSafeNatural' : 'decodeNatural',
      integer: 'decodeInteger', decimal: 'decodeDecimal', json: 'decodeJson' })[kind]}(${value})`;
    if (kind.array) return `decodeArray(${value}, item => ${decoder(kind.array, 'item')})`;
    if (kind.optional) return `${value} === null ? null : ${decoder(kind.optional, value, safe)}`;
    const key = q(kind.enum);
    if (!enums.has(key)) enums.set(key, { name: `decodeEnum${enums.size}`, values: kind.enum });
    return `${enums.get(key).name}(${value})`;
  }
  function fields(fields, safe) {
    return fields.map(field => `${q(field.name)}${field.omittable || field.type.optional ? '?' : ''}: ${type(field.type, safe.includes(field.name))}`).join('; ');
  }
  function construct(tagField, tag, declared, safe) {
    const content = tagField === null ? [] : [`${q(tagField)}: ${q(tag)}`];
    for (const field of declared) {
      const value = `source[${q(field.name)}]`;
      const expression = decoder(field.type, value, safe.includes(field.name));
      content.push(field.omittable || field.type.optional
        ? `...(${value} === undefined ? {} : {${q(field.name)}: ${expression}})` : `${q(field.name)}: ${expression}`);
    }
    return `{${content.join(', ')}}`;
  }
  function union(name, variants) {
    return `export type ${name} =\n${variants.map(variant => `  | {${q(variant.tag_field)}: ${q(variant.tag)}; ${fields(variant.fields, variant.safe_fields)}}`).join('\n')};\n`
      + `export function decode${name}(input: unknown): ${name} {\n  const source = decodeObject(input);\n  switch (source[${q(variants[0].tag_field)}]) {\n`
      + variants.map(variant => `    case ${q(variant.tag)}: exactFields(source, ${q([variant.tag_field, ...variant.fields.map(field => field.name)])}); return ${construct(variant.tag_field, variant.tag, variant.fields, variant.safe_fields)};`).join('\n')
      + `\n    // DEFENSE: External boundary values must name a declared ${name} variant.\n    default: throw new TypeError('Unknown ${name} discriminant');\n  }\n}\n`;
  }
  const variants = schema.commands.map(command => ({tag_field:'op',tag:command.name,fields:command.fields,safe_fields:[]}));
  function record(name, declared) {
    return `export type ${name} = {${fields(declared, [])}};\nexport function decode${name}(input: unknown): ${name} {\n const source = decodeObject(input); exactFields(source, ${q(declared.map(field => field.name))}); return ${construct(null, null, declared, [])};\n}\n`;
  }
  const leaves = schema.results.leaves.map(entry => `export function decode${entry.name}(input: unknown): ${type(entry.type, entry.safe)} { return ${decoder(entry.type, 'input', entry.safe)}; }\n`).join('');
  const results = leaves + schema.results.unions.map(entry => union(entry.name, entry.variants)).join('\n') + schema.results.records.map(entry => record(entry.name, entry.fields)).join('\n');
  const unions = results + '\n' + union('Effect',schema.effects) + '\n' + union('AudioAdmission',schema.audio) + '\n' + union('Command',variants);
  const source = `// Generated from the executable Kernel model declarations. Do not edit.\n`
    + `import { JsonNumber, naturalKey, safeInteger } from '../public/json-tokens.mjs';\n`
    + `export type DomainNatural = number | JsonNumber;\nexport type DomainInteger = number | JsonNumber;\n`
    + `export type JsonValue = null | boolean | string | number | JsonNumber | JsonValue[] | {[key: string]: JsonValue};\n`
    + `function isObject(value: unknown): value is Record<string, unknown> { return typeof value === 'object' && value !== null && !Array.isArray(value) && !(value instanceof JsonNumber); }\n`
    + `function decodeObject(value: unknown): Record<string, unknown> {\n  // DEFENSE: A boundary payload may be a scalar or array rather than its declared record.\n  if (!isObject(value)) throw new TypeError('Expected model object'); return value;\n}\n`
    + `function isArray(value: unknown): value is unknown[] { return Array.isArray(value); }\n`
    + `function decodeArray<T>(value: unknown, decode: (item: unknown) => T): T[] {\n  // DEFENSE: A wire array field can contain a scalar.\n  if (!isArray(value)) throw new TypeError('Expected model array'); return value.map(decode);\n}\n`
    + `function exactFields(value: Record<string, unknown>, names: readonly string[]): void {\n  // DEFENSE: Unknown wire fields cannot silently acquire meaning at a later consumer.\n  if (Object.keys(value).some(name => !names.includes(name))) throw new TypeError('Unknown model field');\n}\n`
    + `function decodeText(value: unknown): string {\n  // DEFENSE: A declared model text field may contain another JSON type.\n  if (typeof value !== 'string') throw new TypeError('Expected model text'); return value;\n}\n`
    + `function decodeBoolean(value: unknown): boolean {\n  // DEFENSE: A declared model Boolean field may contain another JSON type.\n  if (typeof value !== 'boolean') throw new TypeError('Expected model Boolean'); return value;\n}\n`
    + `function decodeNatural(value: unknown): DomainNatural {\n  // DEFENSE: The exact-number ABI admits canonical natural tokens without converting them to rounded numbers.\n  if (typeof value !== 'number' && !(value instanceof JsonNumber)) throw new TypeError('Expected model natural'); naturalKey(value); return value;\n}\n`
    + `function decodeInteger(value: unknown): DomainInteger {\n  // DEFENSE: Core integers retain their strict decimal lexical contract.\n  if (value instanceof JsonNumber && /^-?(0|[1-9]\\d*)$/.test(value.source)) return value;\n  if (typeof value === 'number' && Number.isSafeInteger(value)) return value; throw new TypeError('Expected model integer');\n}\n`
    + `function decodeSafeNatural(value: unknown): number { const number = safeInteger(value);\n  // DEFENSE: Transport durations and limits must fit the physical runtime's nonnegative safe integer range.\n  if (number === undefined || number < 0) throw new TypeError('Expected bounded model natural'); return number;\n}\n`
    + `function decodeDecimal(value: unknown): JsonNumber | number {\n  // DEFENSE: External JSON decimal tokens must have JSON number syntax; numerical observations must be finite.\n  if (value instanceof JsonNumber && /^-?(0|[1-9]\\d*)(\\.\\d+)?([eE][+-]?\\d+)?$/.test(value.source)) return value;\n  if (typeof value === 'number' && Number.isFinite(value)) return value; throw new TypeError('Expected model decimal');\n}\n`
    + `export function decodeJson(value: unknown): JsonValue {\n  if (value === null || typeof value === 'boolean' || typeof value === 'string') return value;\n  if (typeof value === 'number' || value instanceof JsonNumber) return decodeDecimal(value);\n  if (isArray(value)) return value.map(decodeJson);\n  const object = decodeObject(value); return Object.fromEntries(Object.entries(object).map(([key,item]) => [key,decodeJson(item)]));\n}\n`
    + [...enums.values()].map(enumeration => `function ${enumeration.name}(value: unknown): ${enumeration.values.map(q).join(' | ')} {\n switch (value) { ${enumeration.values.map(value => `case ${q(value)}: return ${q(value)};`).join(' ')}\n // DEFENSE: A model enum must contain one of its declared wire values.\n default: throw new TypeError('Unknown model enum'); }\n}\n`).join('\n')
    + unions + `\nexport const commandOwners = ${q(Object.fromEntries(schema.commands.map(command => [command.name,command.owner])))} satisfies Record<Command['op'], string>;\n` + `\nexport const effectCallbacks = ${q(Object.fromEntries(schema.effects.map(effect => [effect.tag,effect.callback])))} satisfies Record<Effect['kind'], string | null>;\n`;
  const filename = path.join(root,'host/generated/model-schema.ts');
  await mkdir(path.dirname(filename),{recursive:true});
  if (await readFile(filename,'utf8').catch(error => { if(error.code === 'ENOENT') return ''; throw error; }) !== source) await writeFile(filename,source);
  return filename;
}
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  await generateModelSchema(path.resolve(new URL('../',import.meta.url).pathname));
}
