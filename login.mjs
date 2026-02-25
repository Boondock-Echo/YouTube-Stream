import puppeteer from 'puppeteer-core';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const {
  WEB_URL,
  LOGIN_USER,
  LOGIN_PASS,
  LOGIN_USER_SELECTOR = 'input[placeholder="User ID"], input[autocomplete="username"]',
  LOGIN_PASS_SELECTOR = 'input[placeholder="Password"], input[autocomplete="current-password"]',
  LOGIN_SUBMIT_SELECTOR = 'button[type="submit"]',
  LOGIN_COOKIE_ACCEPT_SELECTOR = '',
  LOGIN_SUCCESS_SELECTOR = '',
  LOGIN_POST_SUBMIT_SELECTOR = '',
  CHROME_DEBUG_PORT = '9222',
  LOGIN_TIMEOUT_MS = '30000'
} = process.env;

if (!WEB_URL) {
  throw new Error('WEB_URL is required');
}
if (!LOGIN_USER || !LOGIN_PASS) {
  console.log('[login] LOGIN_USER/LOGIN_PASS not set; skipping automated login.');
  process.exit(0);
}

const timeout = Number(LOGIN_TIMEOUT_MS) || 30000;
const browserURL = `http://127.0.0.1:${CHROME_DEBUG_PORT}`;
const DEBUG_ARTIFACT_DIR = '/tmp/login-debug';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const DEFAULT_COOKIE_ACCEPT_SELECTORS = [
  '#onetrust-accept-btn-handler',
  'button#accept-cookies',
  'button[aria-label*="accept" i]',
  'button[title*="accept" i]',
  'button[data-testid*="accept" i]',
  'button[class*="accept" i]',
  'button[id*="accept" i]',
  'button[name*="accept" i]',
];

async function connectWithRetry(retries = 30) {
  let lastErr;
  for (let i = 0; i < retries; i += 1) {
    try {
      return await puppeteer.connect({ browserURL, defaultViewport: null });
    } catch (err) {
      lastErr = err;
      await sleep(500);
    }
  }
  throw lastErr;
}

const browser = await connectWithRetry();
try {
  let [page] = await browser.pages();
  if (!page) {
    page = await browser.newPage();
  }

  page.on('console', (msg) => {
    console.log(`[login][page-console][${msg.type()}] ${msg.text()}`);
  });
  page.on('pageerror', (err) => {
    console.error(`[login][pageerror] ${err.message}`);
  });
  page.on('requestfailed', (request) => {
    const failureText = request.failure()?.errorText ?? 'unknown';
    console.error(`[login][requestfailed] ${request.method()} ${request.url()} (${failureText})`);
  });

  try {
    await page.goto(WEB_URL, { waitUntil: 'domcontentloaded', timeout });
    await acceptCookies(page);
    const userFieldMatch = await waitForSelectorInFrames(page, LOGIN_USER_SELECTOR, { timeout });
    const passFieldMatch = await waitForSelectorInFrames(page, LOGIN_PASS_SELECTOR, { timeout });

    await fillInput(userFieldMatch, LOGIN_USER_SELECTOR, LOGIN_USER);
    await fillInput(passFieldMatch, LOGIN_PASS_SELECTOR, LOGIN_PASS);

    const preSubmitUrl = page.url();

    if (LOGIN_SUBMIT_SELECTOR) {
      const submitButtonMatch = await findSelectorInFrames(page, LOGIN_SUBMIT_SELECTOR, { timeout: 2000 });
      const submitButton = submitButtonMatch?.element;
      if (submitButton) {
        await clickElementMatch(submitButtonMatch, LOGIN_SUBMIT_SELECTOR);
      } else {
        await passFieldMatch.frame.keyboard.press('Enter');
      }
    } else {
      await passFieldMatch.frame.keyboard.press('Enter');
    }

    await loginSuccessWait(page, timeout, preSubmitUrl);

    console.log('[login] Automated login flow completed.');
  } catch (err) {
    const currentUrl = page.url();
    let currentTitle = '(unavailable)';
    try {
      currentTitle = await page.title();
    } catch {
      // title may be unavailable if page context is gone.
    }

    console.error(`[login] Failed at URL="${currentUrl}" title="${currentTitle}"`);
    console.error(
      `[login] Selectors: LOGIN_USER_SELECTOR="${LOGIN_USER_SELECTOR}" LOGIN_PASS_SELECTOR="${LOGIN_PASS_SELECTOR}" LOGIN_SUBMIT_SELECTOR="${LOGIN_SUBMIT_SELECTOR}" LOGIN_SUCCESS_SELECTOR="${LOGIN_SUCCESS_SELECTOR}"`
    );

    try {
      await mkdir(DEBUG_ARTIFACT_DIR, { recursive: true });
      const screenshotPath = path.join(DEBUG_ARTIFACT_DIR, 'failure.png');
      const htmlPath = path.join(DEBUG_ARTIFACT_DIR, 'failure.html');

      await page.screenshot({ path: screenshotPath, fullPage: true });
      await writeFile(htmlPath, await page.content(), 'utf-8');
      console.error(`[login] Saved failure artifacts: ${screenshotPath}, ${htmlPath}`);
    } catch (artifactErr) {
      console.error(`[login] Failed to save debug artifacts: ${artifactErr.message}`);
    }

    throw err;
  }
} finally {
  await browser.disconnect();
}

async function loginSuccessWait(page, waitTimeout, preSubmitUrl) {
  const attemptedChecks = [];
  const successChecks = [];

  if (LOGIN_SUCCESS_SELECTOR) {
    attemptedChecks.push(`LOGIN_SUCCESS_SELECTOR (${LOGIN_SUCCESS_SELECTOR}) visible`);
    successChecks.push(
      waitForSelectorInFrames(page, LOGIN_SUCCESS_SELECTOR, { timeout: waitTimeout })
        .then(() => `LOGIN_SUCCESS_SELECTOR matched (${LOGIN_SUCCESS_SELECTOR})`)
    );
  } else {
    attemptedChecks.push(`URL changed from pre-submit URL (${preSubmitUrl})`);
    successChecks.push(
      page
        .waitForFunction((originalUrl) => window.location.href !== originalUrl, { timeout: waitTimeout }, preSubmitUrl)
        .then(() => `URL changed from ${preSubmitUrl}`)
    );

    attemptedChecks.push(`password field disappeared (${LOGIN_PASS_SELECTOR})`);
    successChecks.push(
      waitForSelectorToDisappearInFrames(page, LOGIN_PASS_SELECTOR, waitTimeout)
        .then(() => `Password field disappeared (${LOGIN_PASS_SELECTOR})`)
    );

    if (LOGIN_POST_SUBMIT_SELECTOR) {
      attemptedChecks.push(`LOGIN_POST_SUBMIT_SELECTOR (${LOGIN_POST_SUBMIT_SELECTOR}) visible`);
      successChecks.push(
        waitForSelectorInFrames(page, LOGIN_POST_SUBMIT_SELECTOR, { timeout: waitTimeout })
          .then(() => `LOGIN_POST_SUBMIT_SELECTOR matched (${LOGIN_POST_SUBMIT_SELECTOR})`)
      );
    }
  }

  try {
    const successReason = await Promise.any(successChecks);
    console.log(`[login] Login verification succeeded: ${successReason}`);
  } catch {
    const currentUrl = page.url();
    let currentTitle = '(unavailable)';
    try {
      currentTitle = await page.title();
    } catch {
      // title may be unavailable if page context is gone.
    }

    throw new Error(
      `[login] Login verification failed. URL="${currentUrl}" title="${currentTitle}" attemptedChecks=${attemptedChecks.join('; ')}`
    );
  }
}

async function fillInput(fieldMatch, selector, value) {
  const { frame, element } = fieldMatch;
  await element.focus();
  await element.click({ clickCount: 3 });
  await frame.keyboard.press('Backspace');
  await element.type(value, { delay: 20 });

  await element.evaluate((input, inputValue) => {
    input.value = inputValue;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }, value);

  console.log(`[login] Filled selector "${selector}" in frame: ${frame.url() || '(no url)'}`);
}

async function clickElementMatch(elementMatch, selector) {
  await elementMatch.element.click();
  console.log(`[login] Clicked selector "${selector}" in frame: ${elementMatch.frame.url() || '(no url)'}`);
}

async function acceptCookies(page) {
  const selectors = [
    ...(LOGIN_COOKIE_ACCEPT_SELECTOR ? [LOGIN_COOKIE_ACCEPT_SELECTOR] : []),
    ...DEFAULT_COOKIE_ACCEPT_SELECTORS
  ];

  for (const selector of selectors) {
    try {
      const buttonMatch = await findSelectorInFrames(page, selector, { timeout: 1000 });
      const button = buttonMatch?.element;
      if (!button) {
        continue;
      }
      await clickElementMatch(buttonMatch, selector);
      await sleep(500);
      console.log(`[login] Accepted cookie banner using selector: ${selector}`);
      return;
    } catch {
      // Try the next candidate selector.
    }
  }
}

async function waitForSelectorInFrames(page, selector, { timeout }) {
  const found = await findSelectorInFrames(page, selector, { timeout });
  if (!found) {
    throw new Error(`[login] Selector not found within timeout: ${selector}`);
  }
  return found;
}

async function findSelectorInFrames(page, selector, { timeout }) {
  const start = Date.now();

  while (Date.now() - start < timeout) {
    for (const frame of page.frames()) {
      try {
        const element = await frame.$(selector);
        if (element) {
          console.log(`[login] Selector "${selector}" matched in frame: ${frame.url() || '(no url)'}`);
          return { frame, element };
        }
      } catch {
        // Ignore detached frame errors and continue polling.
      }
    }
    await sleep(200);
  }

  return null;
}

async function waitForSelectorToDisappearInFrames(page, selector, timeout) {
  const start = Date.now();

  while (Date.now() - start < timeout) {
    let found = false;
    for (const frame of page.frames()) {
      try {
        const element = await frame.$(selector);
        if (element) {
          found = true;
          break;
        }
      } catch {
        // Ignore detached frame errors and continue polling.
      }
    }

    if (!found) {
      return;
    }

    await sleep(200);
  }

  throw new Error(`[login] Selector did not disappear within timeout: ${selector}`);
}
