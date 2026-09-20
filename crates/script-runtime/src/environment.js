(() => {
    const host = globalThis.__selvedgeHost;
    const stringify = JSON.stringify;
    const parse = JSON.parse;
    const ownNames = Object.getOwnPropertyNames;
    const records = new Map();
    const aliases = new Map();
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    let logs = [];
    let lexicalNames = [];

    function logValue(value) {
        if (typeof value === "undefined") return "undefined";
        if (typeof value === "bigint") return `${value}n`;
        if (typeof value === "function") return value.toString();
        try { return parse(stringify(value)); }
        catch { return String(value); }
    }

    const console = Object.fromEntries(["log", "info", "warn", "error", "debug"]
        .map(level => [level, (...values) => logs.push({ level, values: values.map(logValue) })]));

    function moduleApi(referrer, ancestors = []) {
        async function exportsFrom(record, resolved) {
            if (!ancestors.includes(resolved)) await record.ready;
            return record.module.exports;
        }
        return Object.freeze({
            async load(specifier) {
                if (typeof specifier !== "string") throw new TypeError("module specifier must be a string");
                const key = stringify([referrer, specifier]);
                if (aliases.has(key)) {
                    const resolved = aliases.get(key);
                    return exportsFrom(records.get(resolved), resolved);
                }
                const loaded = await host("@selvedge/load-module", { specifier, referrer });
                const resolved = loaded.resolved_specifier;
                aliases.set(key, resolved);
                if (records.has(resolved)) return exportsFrom(records.get(resolved), resolved);
                const module = { exports: {} };
                const record = { module, source: loaded.source, ready: null };
                records.set(resolved, record);
                try {
                    const evaluate = new AsyncFunction("module", "exports", "modules", loaded.source);
                    record.ready = evaluate(module, module.exports, moduleApi(resolved, [...ancestors, resolved]));
                    await record.ready;
                } catch (error) {
                    records.delete(resolved);
                    for (const [alias, target] of aliases) if (target === resolved) aliases.delete(alias);
                    throw error;
                }
                return module.exports;
            },
            source(specifier) {
                const resolved = aliases.get(stringify([referrer, specifier])) ?? specifier;
                if (!records.has(resolved)) throw new Error(`module is not loaded: ${specifier}`);
                return records.get(resolved).source;
            },
            list() { return Array.from(records.keys()).sort(); },
        });
    }

    globalThis.modules = moduleApi("");
    globalThis.environment = Object.freeze({
        names() {
            return Array.from(new Set([...ownNames(globalThis), ...lexicalNames]))
                .filter(name => !name.startsWith("__selvedge"))
                .sort();
        },
    });
    globalThis.console = console;
    Object.defineProperty(globalThis, "__selvedgeRuntime", {
        value: Object.freeze({
            console,
            takeLogs() { const result = logs; logs = []; return result; },
            setLexicalNames(names) { lexicalNames = names; },
        }),
        configurable: false,
        writable: false,
        enumerable: false,
    });
    for (const name of ["WeakRef", "FinalizationRegistry", "SharedArrayBuffer", "Atomics", "WebAssembly", "Intl", "Temporal"]) {
        Object.defineProperty(globalThis, name, { value: undefined, writable: false, configurable: false });
    }
})();
