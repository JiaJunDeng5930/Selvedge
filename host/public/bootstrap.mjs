// DEFENSE: Loading may fail before the extracted program can construct its error presentation.
import('./app.mjs').catch(error => {
  const message = document.createElement('p');
  message.setAttribute('role', 'alert');
  message.textContent = `Unable to load the browser program: ${error.message}`;
  document.getElementById('surface').replaceChildren(message);
});
