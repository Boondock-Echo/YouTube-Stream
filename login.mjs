import puppeteer from 'puppeteer-core';

const {
  WEB_URL,
  LOGIN_USER,
  LOGIN_PASS,
  LOGIN_USER_SELECTOR = 'input[placeholder="User ID"], input[autocomplete="username"]',
  LOGIN_PASS_SELECTOR = 'input[placeholder="Password"], input[autocomplete="current-password"]',
  LOGIN_SUBMIT_SELECTOR = 'button[type="submit"]',
  LOGIN_COOKIE_ACCEPT_SELECTOR = '',
  LOGIN_SUCCESS_SELECTOR = '',
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

  await page.goto(WEB_URL, { waitUntil: 'domcontentloaded', timeout });
  await acceptCookies(page);
  await page.waitForSelector(LOGIN_USER_SELECTOR, { timeout });
  await page.waitForSelector(LOGIN_PASS_SELECTOR, { timeout });

  await fillInput(page, LOGIN_USER_SELECTOR, LOGIN_USER);
  await fillInput(page, LOGIN_PASS_SELECTOR, LOGIN_PASS);

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

  await Promise.race([
    page.waitForNavigation({ waitUntil: 'networkidle2', timeout }).catch(() => null),
    loginSuccessWait(page, timeout)
  ]);

  console.log('[login] Automated login flow completed.');
} finally {
  await browser.disconnect();
}

async function loginSuccessWait(page, waitTimeout) {
  if (!LOGIN_SUCCESS_SELECTOR) {
    await sleep(2000);
    return;
  }
  await page.waitForSelector(LOGIN_SUCCESS_SELECTOR, { timeout: waitTimeout });
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
