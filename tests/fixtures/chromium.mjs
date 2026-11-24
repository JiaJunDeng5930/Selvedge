import { constants } from 'node:fs';
import { access } from 'node:fs/promises';
import { chromium } from 'playwright-core';

async function chromiumExecutable() {
  const requested = process.env.SELVEDGE_CHROMIUM_EXECUTABLE_PATH;
  if (requested) {
    await access(requested, constants.X_OK);
    return requested;
  }
  for (const filename of ['/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome']) {
    try {
      await access(filename, constants.X_OK);
      return filename;
    } catch (error) {
      // DEFENSE: Linux distributions install Chromium under different executable names.
      if (error.code !== 'ENOENT') throw error;
    }
  }
  throw new Error('Browser acceptance requires Chromium. Install it or set SELVEDGE_CHROMIUM_EXECUTABLE_PATH.');
}

let launchFailure;

export async function launchChromium() {
  // DEFENSE: Direct Bun runs can continue after a crashing executable fails the first test.
  if (launchFailure) throw launchFailure;
  try {
    return await chromium.launch({ executablePath: await chromiumExecutable(), headless: true });
  } catch (error) {
    launchFailure = error;
    throw error;
  }
}
