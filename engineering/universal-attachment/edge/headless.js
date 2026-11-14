// Only the fixture page loads this runner. It uses the exact native AE page command.
(async () => {
  const {images, changed, duplicate, rejected, uncertain} = __CONFIG__;
  const output = document.querySelector('output');
  const call = (action, op, bytes = '') => edgeFixtureCommand(action, location.href, op, bytes);
  const expect = (actual, expected) => { if (actual !== expected) throw new Error('unexpected fixture state'); };
  try {
    for (const [index, {operation, bytes}] of images.entries()) {
      if (index === 1) {
        // Only an explicit response correlated to the exact operation and body
        // classifies a rejection; the receiver also accepts a body and loses its reply.
        for (const [op, expected] of [[rejected, 'rejected'], [uncertain, 'unknown']]) {
          expect(call('capture', op), 'bound');
          expect(call('commit', op, bytes), 'input-entered');
          if (expected === 'rejected') {
            const until = performance.now() + 5000;
            while (call('observe', op) === 'unknown' && performance.now() < until)
              await new Promise(resolve => setTimeout(resolve, 20));
          } else {
            await new Promise(resolve => setTimeout(resolve, 150));
          }
          expect(call('observe', op), expected);
          expect(call('commit', op, bytes), 'refused');
        }
      }
      expect(call('capture', operation), 'bound');
      expect(call('observe', operation), 'unknown');
      expect(call('commit', operation, bytes), 'input-entered');
      expect(call('commit', operation, bytes), 'refused');
      const until = performance.now() + 5000;
      while (call('observe', operation) === 'unknown' && performance.now() < until) {
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      expect(call('observe', operation), 'attached');
    }
    expect(call('capture', changed), 'bound');
    editor.value += ' user edit';
    expect(call('commit', changed, images[0].bytes), 'refused');
    editor.value = 'neutral draft';
    editor.setSelectionRange(2, 7, 'backward');
    expect(call('capture', duplicate), 'bound');
    const replacement = editor.cloneNode(true);
    replacement.value = editor.value;
    replacement.setSelectionRange(2, 7, 'backward');
    editor.replaceWith(replacement);
    expect(call('commit', duplicate, images[1].bytes), 'refused');
    expect(collection.childElementCount, 4);
    expect(collection.firstElementChild, prior);
    expect(document.activeElement, outside);
    expect(replacement.value, 'neutral draft');
    expect(replacement.selectionStart, 2);
    expect(replacement.selectionEnd, 7);
    expect(replacement.selectionDirection, 'backward');
    output.textContent = 'RIFTLET_EDGE_FIXTURE_COMPLETE';
  } catch (error) {
    output.textContent = 'RIFTLET_EDGE_FIXTURE_FAILED';
  }
  await fetch('/proof/' + draft, {method: 'POST', body: output.textContent});
})();
