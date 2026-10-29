// Independent browser layout measurement. No renderer functions are imported.
(() => {
  const expected = JSON.parse(document.getElementById('review-line-expected').textContent);
  const normalize = text => text.replace(/\r\n?/g, '\n');
  function measure(code) {
    const pre = code.parentElement;
    const top = pre.getBoundingClientRect().top;
    const characters = [];
    const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      for (let index = 0; index < node.length; index++) {
        if (node.data[index] === '\r' || node.data[index] === '\n') continue;
        const range = document.createRange();
        range.setStart(node, index); range.setEnd(node, index + 1);
        const rectangle = range.getBoundingClientRect();
        characters.push({ char: node.data[index], top: Math.round((rectangle.top - top) * 100) / 100 });
      }
    }
    return { text: code.textContent, normalizedText: normalize(code.textContent),
      preHeight: Math.round(pre.getBoundingClientRect().height * 100) / 100, characters };
  }
  const items = {};
  for (const [key, selector, text] of [
    ['source', '.source-context-text', expected.originalVisual],
    ['planned', '.planned-context-text', expected.plannedVisual],
    ['original', '.original', normalize(expected.originalLiteral ?? "'old'")],
    ['replacement', '.replacement', expected.highlightVisual],
  ]) {
    const actual = measure(document.querySelector(selector));
    const pre = document.createElement('pre');
    const code = document.createElement('code');
    code.textContent = text;
    pre.append(code); document.querySelector('main').append(pre);
    const reference = measure(code);
    items[key] = { actual, reference, matches:
      actual.normalizedText === reference.text && actual.preHeight === reference.preHeight &&
      JSON.stringify(actual.characters) === JSON.stringify(reference.characters) };
  }
  const receipt = { name: expected.name, userAgent: navigator.userAgent,
    items, mark: document.querySelector('.planned-context-text mark').textContent,
    replacement: document.querySelector('.replacement').textContent };
  const meta = document.createElement('meta');
  meta.id = 'review-line-receipt'; meta.content = encodeURIComponent(JSON.stringify(receipt));
  document.head.append(meta);
})();
