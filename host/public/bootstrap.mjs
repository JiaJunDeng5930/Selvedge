// DEFENSE: Loading the compiled browser module can fail before Bend's own rendering-error UI is available.
import('/app.mjs').catch(error => {
  const message = document.createElement('p'); message.setAttribute('role', 'alert');
  message.textContent = `Unable to load the browser program: ${error.message}`;
  document.getElementById('surface').replaceChildren(message);
});
