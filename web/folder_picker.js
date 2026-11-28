window.fuelLogFolderPicker = {
  pick() {
    return new Promise((resolve, reject) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.webkitdirectory = true;
      input.style.display = 'none';
      const done = (value) => {
        input.remove();
        resolve(value);
      };
      input.addEventListener('cancel', () => done(null));
      input.addEventListener('change', async () => {
        try {
          const allowed = /\.(jpe?g|png)$/i;
          const files = Array.from(input.files).filter((f) => allowed.test(f.name));
          const result = await Promise.all(
            files.map(async (f) => ({
              name: f.name,
              bytes: new Uint8Array(await f.arrayBuffer()),
            })),
          );
          done(result);
        } catch (error) {
          input.remove();
          reject(error);
        }
      });
      document.body.appendChild(input);
      input.click();
    });
  },
};
