(() => {
  const tag = 'fuel-log-custom-chart';
  const lunchTag = 'fuel-log-lunch';
  const scope = new URL('fuel-notifications/', document.baseURI).href;

  function chartImage(data) {
    const canvas = document.createElement('canvas');
    canvas.width = 600;
    canvas.height = 240;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Could not draw the notification chart.');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    const text = (value, x, y, maxWidth) => {
      context.fillStyle = '#000000';
      context.font = '26px sans-serif';
      context.fillText(value, x, y, maxWidth);
    };
    context.fillStyle = '#ffc300';
    context.beginPath();
    context.arc(30, 50, 8, 0, Math.PI * 2);
    context.fill();
    text(data.firstLabel, 48, 58, 290);
    text(data.firstAmount, 48, 92, 290);
    context.fillStyle = '#003566';
    context.beginPath();
    context.arc(30, 146, 8, 0, Math.PI * 2);
    context.fill();
    text(data.secondLabel, 48, 154, 290);
    text(data.secondAmount, 48, 188, 290);

    const first = data.firstTotal;
    const second = data.secondTotal;
    const negative = first < 0 || second < 0;
    const total = first == null || second == null ? 0 : first + second;
    const share = negative || total === 0 ? 0 : first / total;
    context.fillStyle = data.kind === 'lunch' &&
      (first == null || second == null || total === 0) ? '#cccccc' : '#003566';
    context.beginPath();
    context.arc(464, 120, 92, 0, Math.PI * 2);
    context.fill();
    context.fillStyle = '#ffc300';
    context.beginPath();
    context.moveTo(464, 120);
    context.arc(464, 120, 92, -Math.PI / 2, -Math.PI / 2 + share * 2 * Math.PI);
    context.closePath();
    context.fill();
    context.fillStyle = '#ffffff';
    context.fillRect(393, 103, 142, 34);
    const percent = Math.round(share * 100);
    const label = negative ? 'Negative amount' :
      total === 0 ? 'No data' : `${percent}% / ${100 - percent}%`;
    context.textAlign = 'center';
    text(label, 464, 128, 130);
    return canvas.toDataURL('image/png');
  }

  async function activeRegistration() {
    if (!('serviceWorker' in navigator)) {
      throw new Error('This browser does not support notification service workers.');
    }
    const registration = await navigator.serviceWorker.register(
      new URL('fuel_notification_worker.js', document.baseURI),
      {scope}
    );
    if (registration.active) return registration;
    const worker = registration.installing || registration.waiting;
    if (!worker) throw new Error('Notification service worker did not start.');
    await new Promise((resolve, reject) => {
      const onStateChange = () => {
        if (worker.state === 'activated') {
          worker.removeEventListener('statechange', onStateChange);
          resolve();
        } else if (worker.state === 'redundant') {
          worker.removeEventListener('statechange', onStateChange);
          reject(new Error('Notification service worker could not be activated.'));
        }
      };
      worker.addEventListener('statechange', onStateChange);
      onStateChange();
    });
    return registration;
  }

  async function cancelNotification(notificationTag) {
    if (!('serviceWorker' in navigator)) return;
    const registration = await navigator.serviceWorker.getRegistration(scope);
    if (!registration) return;
    const notifications = await registration.getNotifications({tag: notificationTag});
    notifications.forEach(notification => notification.close());
  }

  window.fuelLogNotifications = {
    requestPermission() {
      if (!window.isSecureContext || !('Notification' in window)) {
        return Promise.reject(new Error('Notifications require a supported browser and HTTPS or localhost.'));
      }
      return Notification.requestPermission();
    },
    async show(json) {
      const data = JSON.parse(json);
      if (Notification.permission !== 'granted') {
        throw new Error('Notifications are blocked in browser settings.');
      }
      const registration = await activeRegistration();
      const options = {
        body: `${data.fillUp} | ${data.firstLabel}: ${data.firstAmount} | ${data.secondLabel}: ${data.secondAmount}`,
        tag: data.kind === 'lunch' ? lunchTag : tag,
      };
      try {
        options.image = chartImage(data);
      } catch (error) {
        console.warn('Could not draw notification chart:', error);
      }
      try {
        await registration.showNotification(data.title, options);
      } catch (error) {
        if (!options.image) throw error;
        console.warn('Notification image was rejected; showing text only:', error);
        delete options.image;
        await registration.showNotification(data.title, options);
      }
    },
    async cancel() {
      await cancelNotification(tag);
    },
    async cancelLunch() {
      await cancelNotification(lunchTag);
    },
  };
})();
