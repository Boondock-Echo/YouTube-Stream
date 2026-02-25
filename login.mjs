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
    await page.waitForSelector(LOGIN_USER_SELECTOR, { timeout });
    await page.waitForSelector(LOGIN_PASS_SELECTOR, { timeout });

    await fillInput(page, LOGIN_USER_SELECTOR, LOGIN_USER);
    await fillInput(page, LOGIN_PASS_SELECTOR, LOGIN_PASS);

    const preSubmitUrl = page.url();

    if (LOGIN_SUBMIT_SELECTOR) {
      const submitButton = await page.$(LOGIN_SUBMIT_SELECTOR);
      if (submitButton) {
        await submitButton.click();
      } else {
        await page.keyboard.press('Enter');
      }
    } else {
      await page.keyboard.press('Enter');
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
      page
        .waitForSelector(LOGIN_SUCCESS_SELECTOR, { timeout: waitTimeout })
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
      page
        .waitForFunction(
          (passwordSelector) => !document.querySelector(passwordSelector),
          { timeout: waitTimeout },
          LOGIN_PASS_SELECTOR
        )
        .then(() => `Password field disappeared (${LOGIN_PASS_SELECTOR})`)
    );

    if (LOGIN_POST_SUBMIT_SELECTOR) {
      attemptedChecks.push(`LOGIN_POST_SUBMIT_SELECTOR (${LOGIN_POST_SUBMIT_SELECTOR}) visible`);
      successChecks.push(
        page
          .waitForSelector(LOGIN_POST_SUBMIT_SELECTOR, { timeout: waitTimeout })
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

async function fillInput(page, selector, value) {
  await page.focus(selector);
  await page.click(selector, { clickCount: 3 });
  await page.keyboard.press('Backspace');
  await page.type(selector, value, { delay: 20 });

  await page.evaluate(
    ({ inputSelector, inputValue }) => {
      const input = document.querySelector(inputSelector);
      if (!input) {
        return;
      }
      input.value = inputValue;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    },
    { inputSelector: selector, inputValue: value }
  );
}

async function acceptCookies(page) {
  const selectors = [
    ...(LOGIN_COOKIE_ACCEPT_SELECTOR ? [LOGIN_COOKIE_ACCEPT_SELECTOR] : []),
    ...DEFAULT_COOKIE_ACCEPT_SELECTORS
  ];

  for (const selector of selectors) {
    try {
      const button = await page.$(selector);
      if (!button) {
        continue;
      }
      await button.click();
      await sleep(500);
      console.log(`[login] Accepted cookie banner using selector: ${selector}`);
      return;
    } catch {
      // Try the next candidate selector.
    }
  }
}
