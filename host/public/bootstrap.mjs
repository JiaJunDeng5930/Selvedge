const surface = document.getElementById('surface');
const startup = document.getElementById('selvedge-startup');
function offerReload(text) {
  const message = document.createElement('p');
  message.setAttribute('role', 'alert');
  message.textContent = text;
  const reload = document.createElement('button');
  reload.type = 'button';
  reload.textContent = '重新加载';
  reload.addEventListener('click', () => window.location.reload());
  surface.replaceChildren(message, reload);
}
// DEFENSE: A stalled module load or first measurement leaves the static
// startup message in place. Offer a way to recover if it has not been replaced.
const deadline = setTimeout(() => {
  if (startup.isConnected) offerReload('加载界面用时较长。可以重新加载此页面。');
}, 12_000);
// DEFENSE: A rejected module can fail before the extracted program can render recovery.
import('./app.mjs').catch(error => {
  clearTimeout(deadline);
  offerReload(`无法加载界面：${error.message}`);
});
