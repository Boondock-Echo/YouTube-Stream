import puppeteer from 'puppeteer-core';

const {
  WEB_URL,
  LOGIN_USER,
  LOGIN_PASS,
  LOGIN_USER_SELECTOR = 'input[placeholder="User ID"], input[autocomplete="username"]',
  LOGIN_PASS_SELECTOR = 'input[placeholder="Password"], input[autocomplete="current-password"]',
  LOGIN_SUBMIT_SELECTOR = 'button[type="submit"]',
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
  await page.waitForSelector(LOGIN_USER_SELECTOR, { timeout });
  await page.waitForSelector(LOGIN_PASS_SELECTOR, { timeout });

  await page.click(LOGIN_USER_SELECTOR, { clickCount: 3 });
  await page.keyboard.press('Backspace');
  await page.type(LOGIN_USER_SELECTOR, LOGIN_USER, { delay: 20 });

  await page.click(LOGIN_PASS_SELECTOR, { clickCount: 3 });
  await page.keyboard.press('Backspace');
  await page.type(LOGIN_PASS_SELECTOR, LOGIN_PASS, { delay: 20 });

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
