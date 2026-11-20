'use strict';

(async () => {
  const transport = window.fetch.bind(window);
  const mode = document.body.dataset.mode;
  let phase = 'setup';
  try {
    const {run} = await import('./scenario.js');
    const [programSource, source] = await Promise.all([
      transport('./program').then(r => r.text()),
      transport('./asset').then(r => r.arrayBuffer())
    ]);
    const report = await run(mode, programSource, source, value => { phase = value; });
    const next = await transport('./result', {method:'POST', body:JSON.stringify(report)}).then(r => r.text());
    if (['reencoded', 'scaled'].includes(next)) location.replace('./' + next);
  } catch {
    await transport('./result', {method:'POST', body:JSON.stringify({failed:phase})});
  }
})();
