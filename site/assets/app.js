'use strict';
(() => {
  const root = document.documentElement;
  const stored = (() => { try { return localStorage.getItem('like-docs-theme'); } catch { return null; } })();
  root.dataset.theme = stored || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  document.querySelector('#theme').addEventListener('click', () => {
    root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
    try { localStorage.setItem('like-docs-theme', root.dataset.theme); } catch { /* storage can be unavailable */ }
  });
  const menu = document.querySelector('#menu'), sidebar = document.querySelector('#sidebar');
  menu.addEventListener('click', () => { const open = sidebar.classList.toggle('open'); menu.setAttribute('aria-expanded', String(open)); });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') { sidebar.classList.remove('open'); menu.setAttribute('aria-expanded', 'false'); } });
  let noticeTimer;
  function notice(text) { const el = document.querySelector('#notice'); el.textContent = text; el.classList.add('visible'); clearTimeout(noticeTimer); noticeTimer = setTimeout(() => el.classList.remove('visible'), 2200); }
  async function copy(text) { try { await navigator.clipboard.writeText(text); notice('Copied to clipboard'); } catch { notice('Clipboard unavailable. Use View Markdown or select the code.'); } }
  document.querySelectorAll('pre > code').forEach(code => { const button = document.createElement('button'); button.type = 'button'; button.textContent = 'Copy'; button.className = 'copy-code'; button.setAttribute('aria-label', 'Copy code example'); button.addEventListener('click', () => copy(code.textContent)); code.parentElement.prepend(button); });
  document.querySelector('#copy-page').addEventListener('click', async event => { try { const response = await fetch(event.currentTarget.dataset.url); if (!response.ok) throw new Error('Unavailable'); await copy(await response.text()); } catch { notice('Page copy unavailable. Use View Markdown.'); } });
  const dialog = document.querySelector('#search'), input = document.querySelector('#search-input'), results = document.querySelector('#search-results'), status = document.querySelector('#search-status');
  let indexPromise;
  function loadIndex() { if (!indexPromise) indexPromise = fetch(document.body.dataset.base + 'search.json').then(response => { if (!response.ok) throw new Error('Index unavailable'); return response.json(); }).catch(error => { indexPromise = null; throw error; }); return indexPromise; }
  function openSearch() { if (!dialog.open) dialog.showModal(); input.focus(); loadIndex().catch(() => { status.textContent = 'Search could not load. Browse the guides in the sidebar.'; }); }
  document.querySelector('.search-open').addEventListener('click', openSearch);
  document.querySelector('#search-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => { if (event.target === dialog) { const b = dialog.getBoundingClientRect(); if (event.clientX < b.left || event.clientX > b.right || event.clientY < b.top || event.clientY > b.bottom) dialog.close(); } });
  document.addEventListener('keydown', event => { const editing = /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) || document.activeElement.isContentEditable; if ((event.key.toLowerCase() === 'k' && (event.metaKey || event.ctrlKey)) || (event.key === '/' && !editing)) { event.preventDefault(); openSearch(); } });
  let generation = 0;
  input.addEventListener('input', async () => {
    const current = ++generation, query = input.value.trim().toLowerCase(); results.replaceChildren();
    if (!query) { status.textContent = 'Search guides, APIs and examples.'; return; }
    try {
      const pages = await loadIndex(); if (current !== generation) return;
      const terms = query.split(/\s+/), matches = pages.map(page => { const title = page.title.toLowerCase(), text = page.text.toLowerCase(); return {page, score: terms.every(term => title.includes(term) || text.includes(term)) ? terms.reduce((score, term) => score + (title.includes(term) ? 10 : 1), 0) : 0}; }).filter(x => x.score).sort((a, b) => b.score - a.score).slice(0, 12);
      status.textContent = matches.length ? matches.length + ' matching guides' : 'No matching guides. Try fewer words or a class name.';
      for (const {page} of matches) { const li = document.createElement('li'), a = document.createElement('a'), small = document.createElement('small'), strong = document.createElement('strong'), excerpt = document.createElement('p'); a.href = page.url; small.textContent = page.group; strong.textContent = page.title; const hit = page.text.toLowerCase().indexOf(terms[0]); excerpt.textContent = page.text.slice(Math.max(0, hit - 35), Math.max(0, hit - 35) + 160) + '…'; a.append(small, strong, excerpt); li.append(a); results.append(li); }
    } catch { if (current === generation) status.textContent = 'Search could not load. Browse the guides in the sidebar.'; }
  });
})();
