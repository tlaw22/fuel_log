(() => {
  const ua = navigator.userAgent;
  const isPhone = /iPhone|iPod/.test(ua) ||
      (/Android/.test(ua) && /Mobile/.test(ua));
  const isIos = /iPhone|iPod/.test(ua);
  const isOtherBrowser = /FxiOS|Firefox|OPiOS|OPR\/|SamsungBrowser|UCBrowser|DuckDuckGo|GSA\/|YaBrowser|Vivaldi|; wv\)/i.test(ua);
  const isEdge = /EdgiOS\/|EdgA\//.test(ua);
  const isChrome = /CriOS\/|Chrome\//.test(ua) && !isOtherBrowser && !isEdge;
  const isSafari = isIos && /Safari\//.test(ua) && !isOtherBrowser &&
      !isEdge && !isChrome;
  const isInstallOrigin = location.protocol === 'https:' ||
      (location.protocol === 'http:' &&
       /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname));
  if (!isPhone || !(isEdge || isChrome || isSafari) || !isInstallOrigin) return;

  const prompt = document.getElementById('install-prompt');
  const action = document.getElementById('install-action');
  const dismiss = document.getElementById('install-dismiss');
  const instructions = document.getElementById('install-instructions');
  const dismissedKey = 'fuel_install_prompt_dismissed';
  let deferredPrompt = null;
  let ready = false;
  let dismissed = false;

  try {
    dismissed = sessionStorage.getItem(dismissedKey) === '1';
  } catch (error) {
    console.warn('Could not read the install prompt preference:', error);
  }

  function isStandalone() {
    return navigator.standalone === true ||
        window.matchMedia('(display-mode: standalone)').matches;
  }

  function update() {
    prompt.hidden = !ready || dismissed || isStandalone();
    action.textContent = deferredPrompt ? 'Install' : 'How to install';
  }

  function close() {
    dismissed = true;
    deferredPrompt = null;
    prompt.hidden = true;
    try {
      sessionStorage.setItem(dismissedKey, '1');
    } catch (error) {
      console.warn('Could not save the install prompt preference:', error);
    }
  }

  function showInstructions() {
    instructions.textContent = isIos
        ? 'Open the browser Share menu and choose Add to Home Screen. If it is unavailable, open this page in Safari and use Share, then Add to Home Screen.'
        : 'Open the browser menu and choose Install app or Add to Home screen.';
    instructions.hidden = false;
    action.textContent = 'How to install';
  }

  window.addEventListener('beforeinstallprompt', (event) => {
    if (dismissed || isStandalone()) return;
    event.preventDefault();
    deferredPrompt = event;
    update();
  });
  window.addEventListener('flutter-first-frame', () => {
    ready = true;
    update();
  }, { once: true });
  window.addEventListener('appinstalled', close);
  dismiss.addEventListener('click', close);
  action.addEventListener('click', async () => {
    if (!deferredPrompt) {
      showInstructions();
      return;
    }
    const installEvent = deferredPrompt;
    deferredPrompt = null;
    try {
      const result = await installEvent.prompt();
      if (result.outcome === 'accepted') {
        close();
      } else {
        showInstructions();
      }
    } catch (error) {
      console.error('Could not open the browser install prompt:', error);
      showInstructions();
    }
  });
})();
