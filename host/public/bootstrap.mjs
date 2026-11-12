const surface = document.getElementById('surface');
const startup = document.getElementById('selvedge-startup');
const content = startup.querySelector('.startup-content');

function offerReload(text) {
  const message = document.createElement('p');
  message.setAttribute('role', 'alert');
  message.textContent = text;
  const reload = document.createElement('button');
  reload.type = 'button';
  reload.textContent = '重新加载';
  reload.addEventListener('click', () => window.location.reload());
  content.replaceChildren(message, reload);
  if (!startup.isConnected) surface.replaceChildren(startup);
  surface.inert = false;
}

// DEFENSE: A stalled module load or first measurement leaves the static
// startup view in place. Offer a way to recover if it has not been replaced.
const deadline = setTimeout(() => {
  if (startup.isConnected) offerReload('加载用时较长。');
}, 12_000);

// DEFENSE: A rejected module can fail before the extracted program can render recovery.
import('./app.mjs').catch(error => {
  clearTimeout(deadline);
  console.error(error);
  offerReload('无法加载界面。');
});
