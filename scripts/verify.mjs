import { build } from './build.mjs';
import { check } from './check.mjs';
import { runTests } from './test.mjs';

const buildResult = await build({ check: true });
await check(buildResult);
await runTests(buildResult);
