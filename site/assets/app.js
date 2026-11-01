'use strict';
(() => {
  const root = document.documentElement;
  const stored = (() => { try { return localStorage.getItem('like-docs-theme'); } catch { return null; } })();
  root.dataset.theme = stored || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  document.querySelector('#theme').addEventListener('click', () => {
    root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
    try { localStorage.setItem('like-docs-theme', root.dataset.theme); } catch { /* storage can be unavailable */ }
  });
  // Use measured header height so wrapping/zoom never clips sticky navigation.
  const header = document.querySelector('header');
  new ResizeObserver(() => root.style.setProperty('--header-height', header.getBoundingClientRect().height + 'px')).observe(header);
  const menu = document.querySelector('#menu'), sidebar = document.querySelector('#sidebar');
  const backdrop = document.querySelector('#nav-backdrop'), closeNav = document.querySelector('#nav-close');
  const compact = matchMedia('(max-width: 980px)');
  const background = [header, document.querySelector('main'), document.querySelector('.on-this-page')];
  function setMenu(open, restoreFocus = true) {
    open = open && compact.matches;
    sidebar.classList.toggle('open', open);
    document.body.classList.toggle('nav-open', open);
    menu.setAttribute('aria-expanded', String(open));
    backdrop.hidden = !open;
    background.forEach(element => { element.inert = open; });
    if (open) closeNav.focus();
    else if (restoreFocus && compact.matches) menu.focus();
  }
  menu.addEventListener('click', () => setMenu(!sidebar.classList.contains('open')));
  closeNav.addEventListener('click', () => setMenu(false));
  backdrop.addEventListener('click', () => setMenu(false));
  compact.addEventListener('change', () => setMenu(false, false));
  sidebar.addEventListener('click', event => { if (event.target.closest('a') && compact.matches) setMenu(false, false); });
  document.addEventListener('keydown', event => {
    if (!sidebar.classList.contains('open')) return;
    if (event.key === 'Escape') { event.preventDefault(); setMenu(false); }
    if (event.key === 'Tab') {
      const stops = [...sidebar.querySelectorAll('a,button')].filter(el => el.getClientRects().length);
      const first = stops[0], last = stops[stops.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
  let noticeTimer;
  function notice(text) { const el = document.querySelector('#notice'); el.textContent = text; el.classList.add('visible'); clearTimeout(noticeTimer); noticeTimer = setTimeout(() => el.classList.remove('visible'), 2200); }
  async function copy(text) { try { await navigator.clipboard.writeText(text); notice('Copied to clipboard'); } catch { notice('Clipboard unavailable. Use View Markdown or select the code.'); } }
  document.querySelectorAll('pre > code').forEach(code => { const button = document.createElement('button'); button.type = 'button'; button.textContent = 'Copy'; button.className = 'copy-code'; button.setAttribute('aria-label', 'Copy code example'); button.addEventListener('click', () => copy(code.textContent)); code.parentElement.prepend(button); });
  document.querySelector('#copy-page').addEventListener('click', async event => { try { const response = await fetch(event.currentTarget.dataset.url); if (!response.ok) throw new Error('Unavailable'); await copy(await response.text()); } catch { notice('Page copy unavailable. Use View Markdown.'); } });
  const apiFilter = document.querySelector('#api-filter');
  if (apiFilter) {
    const symbols = [...document.querySelectorAll('[data-api-symbol]')];
    const applyFilter = () => {
      const terms = apiFilter.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
      let count = 0;
      symbols.forEach(section => {
        const matches = terms.every(term => section.textContent.toLowerCase().includes(term));
        section.hidden = !matches;
        if (matches) count++;
        section.querySelector('details').open = matches && terms.length > 0;
      });
      document.querySelector('#api-filter-status').textContent = count + ' public declarations shown' + (terms.length ? ' for your filter.' : '. Expand a declaration to read its members.');
    };
    apiFilter.addEventListener('input', applyFilter);
    const revealAnchor = () => {
      let id;
      try { id = decodeURIComponent(location.hash.slice(1)); } catch { return; }
      if (!id) return;
      const target = document.getElementById(id);
      const section = target?.closest('[data-api-symbol]');
      if (section) {
        apiFilter.value = '';
        applyFilter();
        section.querySelector('details').open = true;
        target.scrollIntoView({block: 'start'});
      }
    };
    addEventListener('hashchange', revealAnchor);
    revealAnchor();
  }
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
