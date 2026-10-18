import { totalmem } from 'node:os';

// Leave space for native allocations and the parent process before the OS limit.
// The generic operational client needs several GB beyond the managed heap.
const maximumCompilerHeapBytes = 8_000_000_000;

export function compilerEnvironment(extra = {}) {
  const constrained = process.constrainedMemory?.() ?? 0;
  const memory = constrained > 0 ? Math.min(totalmem(), constrained) : totalmem();
  const heap = Math.floor(Math.min(maximumCompilerHeapBytes, memory > 0 ? memory * 0.7 : maximumCompilerHeapBytes));
  return {
    ...process.env,
    BEND_NO_TELEMETRY: '1',
    BUN_JSC_forceRAMSize: process.env.BUN_JSC_forceRAMSize ?? String(Math.floor(Math.min(8 * 1024 ** 3, memory))),
    BUN_JSC_gcMaxHeapSize: process.env.BUN_JSC_gcMaxHeapSize ?? String(heap),
    ...extra,
  };
}
