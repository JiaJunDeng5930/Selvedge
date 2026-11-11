const escape = value => String(value ?? '')
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

function screenshot(file, label) {
  return `<a href="${escape(file)}"><img src="${escape(file)}" alt="${escape(label)}" loading="lazy"></a>`;
}

function cell(item, label) {
  if (item.status === 'missing') return '<span class="missing">Missing · see capture log</span>';
  if (item.status === 'not-applicable') return `<span>Not applicable · ${escape(item.reason)}</span>`;
  return `${screenshot(item.primary, label)}
    ${item.bottom ? `<a href="${escape(item.bottom)}">Scrolled to bottom</a>` : ''}
    ${item.right ? `<a href="${escape(item.right)}">Scrolled to right</a>` : ''}`;
}

export function gallery({ viewports, sections, counts }) {
  const headings = viewports.map(({ width, height, textScale }) =>
    `<th scope="col">${width} × ${height}${textScale === 100 ? '' : `<br>${textScale}% text`}</th>`).join('');
  const tables = sections.map(({ id, title, log, exitCode, rows, extras }) => `
<section id="${id}">
  <h2>${escape(title)}</h2>
  <p><a href="${escape(log)}">Capture log</a>${exitCode ? ` · process exited ${exitCode}` : ''}</p>
  <div class="table"><table>
    <thead><tr><th scope="col">State</th>${headings}</tr></thead>
    <tbody>${rows.map(({ state, cells }) => `<tr><th scope="row">${escape(state)}</th>
      ${cells.map(item => `<td>${cell(item, `${state} · ${item.viewport}`)}</td>`).join('')}</tr>`).join('')}</tbody>
  </table></div>
  ${extras.length ? `<h3>Breakpoint and interaction samples</h3><div class="extras">${extras.map(({ file, name }) =>
    `<figure>${screenshot(file, name)}<figcaption>${escape(name)}</figcaption></figure>`).join('')}</div>` : ''}
</section>`).join('');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Selvedge browser screenshots</title>
<style>
  :root { font: 15px/1.5 system-ui, sans-serif; color: #25231e; background: #f7f6f2; }
  body { margin: 0 auto; max-width: 120rem; padding: 1.5rem; }
  a { color: #075b55; }
  nav, .extras { display: flex; flex-wrap: wrap; gap: .5rem 1rem; }
  section { margin-block: 2rem; }
  .table { overflow: auto; }
  table { border-collapse: collapse; background: white; width: 100%; table-layout: fixed; }
  th, td { border: 1px solid #e1ddd2; padding: .5rem; vertical-align: top; }
  th { background: #efece2; }
  th:first-child { position: sticky; left: 0; width: 10rem; text-align: left; overflow-wrap: anywhere; }
  th:not(:first-child), td { min-width: 10rem; }
  table { min-width: ${(viewports.length + 1) * 11}rem; }
  img { width: 100%; height: auto; display: block; }
  td a { display: block; }
  .missing { color: #9b3321; }
  figure { width: 10rem; margin: 0; }
</style>
</head>
<body>
<h1>Selvedge browser screenshots</h1>
<p>${counts.captured} captured · ${counts.missing} missing · ${counts['not-applicable']} not applicable.
Open a thumbnail to see the original. <a href="manifest.json">Manifest</a></p>
<nav aria-label="Screenshot groups">${sections.map(({ id, title }) =>
  `<a href="#${id}">${escape(title)}</a>`).join('')}</nav>
${tables}
</body>
</html>
`;
}
