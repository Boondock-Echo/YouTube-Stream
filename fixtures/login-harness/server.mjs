import http from 'node:http';

const port = Number(process.env.LOGIN_FIXTURE_PORT || '4173');

const baseStyles = `
  body { font-family: Arial, sans-serif; margin: 2rem; }
  form { display: grid; gap: 0.5rem; max-width: 20rem; }
  input, button { padding: 0.5rem; }
  #cookie-banner { border: 1px solid #ddd; padding: 1rem; margin-bottom: 1rem; }
`;

function pageTemplate(title, body, script = '') {
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>${title}</title>
    <style>${baseStyles}</style>
  </head>
  <body>
    <h1>${title}</h1>
    ${body}
    <script>${script}</script>
  </body>
</html>`;
}

function loginForm(action = '/post-login') {
  return `<form id="login-form" action="${action}">
    <label>User <input placeholder="User ID" autocomplete="username" name="user" /></label>
    <label>Pass <input placeholder="Password" autocomplete="current-password" type="password" name="pass" /></label>
    <button type="submit">Login</button>
  </form>`;
}

const loginFormHtml = loginForm('/post-login');
const loginFormLiteral = JSON.stringify(loginFormHtml);

const server = http.createServer((req, res) => {
  const { url = '/' } = req;

  if (url === '/health') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok');
    return;
  }

  if (url === '/main') {
    const html = pageTemplate(
      'Main DOM Login',
      loginFormHtml,
      `document.getElementById('login-form').addEventListener('submit', (event) => {
        event.preventDefault();
        window.location.href = '/post-login';
      });`
    );
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  if (url === '/delayed') {
    const html = pageTemplate(
      'Delayed Render Login',
      '<div id="mount">Rendering login form...</div>',
      `setTimeout(() => {
        document.getElementById('mount').innerHTML = ${loginFormLiteral};
        document.getElementById('login-form').addEventListener('submit', (event) => {
          event.preventDefault();
          window.location.href = '/post-login';
        });
      }, 1200);`
    );
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  if (url === '/iframe') {
    const html = pageTemplate(
      'Iframe Login',
      '<iframe id="login-frame" src="/iframe-form" width="420" height="300" style="border:1px solid #ddd"></iframe>'
    );
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  if (url === '/iframe-form') {
    const html = pageTemplate(
      'Iframe Form',
      loginFormHtml,
      `document.getElementById('login-form').addEventListener('submit', (event) => {
        event.preventDefault();
        window.top.location.href = '/post-login';
      });`
    );
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  if (url === '/cookie') {
    const html = pageTemplate(
      'Cookie Banner Login',
      `<div id="cookie-banner">
        <p>Accept cookies to continue</p>
        <button id="accept-cookies" type="button">Accept cookies</button>
      </div>
      <div id="login-container"></div>`,
      `const container = document.getElementById('login-container');
      function renderLogin() {
        container.innerHTML = ${loginFormLiteral};
        document.getElementById('login-form').addEventListener('submit', (event) => {
          event.preventDefault();
          window.location.href = '/post-login';
        });
      }
      document.getElementById('accept-cookies').addEventListener('click', () => {
        document.getElementById('cookie-banner').remove();
        renderLogin();
      });`
    );
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  if (url === '/post-login') {
    const html = pageTemplate('Logged In', '<p id="welcome">Login complete</p>');
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('Not found');
});

server.listen(port, () => {
  console.log(`[fixture] login fixture server listening on http://127.0.0.1:${port}`);
});
