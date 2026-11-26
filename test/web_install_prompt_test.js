// Run via web_install_prompt_test.html from a local server at the repo root.
const installPromptSource = new URL('../web/install_prompt.js', document.currentScript.src);
window.runInstallPromptTests = async () => {
  const response = await fetch(installPromptSource);
  if (!response.ok) throw new Error('Could not load install_prompt.js');
  const source = await response.text();
  const run = new Function(
    'window', 'document', 'navigator', 'location', 'sessionStorage', 'console',
    source,
  );
  const chrome = 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
  const edge = chrome + ' EdgA/125.0.0.0';
  const safari = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  const chromeIos = safari.replace('Version/17.0', 'CriOS/125.0');
  const edgeIos = safari.replace('Version/17.0', 'EdgiOS/125.0');
  let count = 0;
  function check(condition, message) {
    count++;
    if (!condition) throw new Error(message);
  }
  function fixture(userAgent, options = {}) {
    const elements = {};
    for (const id of ['install-prompt', 'install-action', 'install-dismiss',
      'install-instructions']) {
      elements[id] = document.createElement('div');
      elements[id].hidden = id === 'install-prompt' || id === 'install-instructions';
    }
    const fakeWindow = new EventTarget();
    fakeWindow.matchMedia = () => ({ matches: !!options.standalone });
    const storage = options.storage || new Map();
    const fakeStorage = {
      getItem: (key) => {
        if (options.storageDenied) throw new Error('Storage unavailable');
        return storage.get(key) || null;
      },
      setItem: (key, value) => {
        if (options.storageDenied) throw new Error('Storage unavailable');
        storage.set(key, value);
      },
    };
    const logs = [];
    run(fakeWindow, { getElementById: (id) => elements[id] },
      { userAgent, standalone: !!options.iosStandalone },
      { protocol: options.protocol || 'https:', hostname: options.hostname || 'example.com' },
      fakeStorage, { warn: (...args) => logs.push(args), error: (...args) => logs.push(args) });
    return { window: fakeWindow, elements, storage, logs };
  }
  function frame(test) {
    test.window.dispatchEvent(new Event('flutter-first-frame'));
  }
  function nativeEvent(outcome) {
    const event = new Event('beforeinstallprompt', { cancelable: true });
    event.calls = 0;
    event.prompt = async () => {
      event.calls++;
      if (outcome instanceof Error) throw outcome;
      return { outcome };
    };
    return event;
  }
  const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

  for (const ua of [chrome, edge, safari, chromeIos, edgeIos]) {
    const test = fixture(ua);
    check(test.elements['install-prompt'].hidden, 'Prompt appeared before the first frame');
    frame(test);
    check(!test.elements['install-prompt'].hidden, 'Supported phone did not show a prompt');
    test.elements['install-action'].click();
    check(!test.elements['install-instructions'].hidden, 'Manual instructions were not shown');
    check(test.elements['install-instructions'].textContent.includes(
      ua.includes('iPhone') ? 'Share' : 'browser menu'), 'Wrong platform instructions');
  }

  for (const ua of [
    chrome.replace('Mobile ', ''),
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/125.0 Safari/537.36',
    chrome + ' SamsungBrowser/25.0',
    safari.replace('Version/17.0', 'FxiOS/125.0'),
  ]) {
    const test = fixture(ua);
    frame(test);
    check(test.elements['install-prompt'].hidden, 'Unsupported browser showed a prompt');
  }

  for (const options of [
    { standalone: true }, { iosStandalone: true }, { protocol: 'http:' },
  ]) {
    const test = fixture(chrome, options);
    frame(test);
    check(test.elements['install-prompt'].hidden, 'Standalone or insecure page showed a prompt');
  }
  const localhost = fixture(chrome, { protocol: 'http:', hostname: 'localhost' });
  frame(localhost);
  check(!localhost.elements['install-prompt'].hidden, 'Localhost was not supported');

  const noStorage = fixture(chrome, { storageDenied: true });
  frame(noStorage);
  check(!noStorage.elements['install-prompt'].hidden, 'Blocked storage hid the prompt');
  noStorage.elements['install-dismiss'].click();
  check(noStorage.elements['install-prompt'].hidden && noStorage.logs.length === 2,
    'Blocked storage was not reported or dismissal failed');

  const dismissed = fixture(chrome);
  frame(dismissed);
  dismissed.elements['install-dismiss'].click();
  check(dismissed.elements['install-prompt'].hidden, 'Dismissal did not hide the prompt');
  const reload = fixture(chrome, { storage: dismissed.storage });
  frame(reload);
  check(reload.elements['install-prompt'].hidden, 'Dismissal was not remembered for the session');
  const ignored = nativeEvent('accepted');
  reload.window.dispatchEvent(ignored);
  check(!ignored.defaultPrevented, 'Dismissal suppressed the browser install prompt');

  const accepted = fixture(chrome);
  const install = nativeEvent('accepted');
  accepted.window.dispatchEvent(install);
  check(install.defaultPrevented, 'Native prompt was not deferred');
  check(accepted.elements['install-prompt'].hidden, 'Native prompt appeared before first frame');
  frame(accepted);
  check(accepted.elements['install-action'].textContent === 'Install', 'Install action missing');
  accepted.elements['install-action'].click();
  await tick();
  check(install.calls === 1 && accepted.elements['install-prompt'].hidden,
    'Native installation did not close the invitation');

  for (const outcome of ['dismissed', new Error('Install failed')]) {
    const test = fixture(edge);
    frame(test);
    const event = nativeEvent(outcome);
    test.window.dispatchEvent(event);
    test.elements['install-action'].click();
    await tick();
    check(event.calls === 1 && !test.elements['install-instructions'].hidden,
      'Native prompt failure did not show manual instructions');
    if (outcome instanceof Error) check(test.logs.length === 1, 'Install error was not reported');
  }
  const installed = fixture(safari);
  frame(installed);
  installed.window.dispatchEvent(new Event('appinstalled'));
  check(installed.elements['install-prompt'].hidden, 'Installed event did not hide invitation');
  return `${count} install prompt checks passed`;
};
