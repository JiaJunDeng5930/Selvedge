import('/app.mjs').catch(error => {
  const message = document.createElement('p'); message.setAttribute('role', 'alert');
  message.textContent = `Unable to load the browser program: ${error?.message ?? String(error)}`;
  document.getElementById('surface').replaceChildren(message);
});
