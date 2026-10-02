/* =====================================================================
   Clipboard pages
   Add-on to script.js (which is unchanged). It only watches the DOM that
   script.js builds and splits it into pages you flip with the folded
   corner at the bottom of the sheet.
     - rental list: N cars per page
     - /papers: page 1 agreement, page 2 temporary permit
   ===================================================================== */
(() => {
  const CARS_PER_PAGE = 6;

  const $ = (id) => document.getElementById(id);

  /* ---------- shared ---------- */
  function setCorners(prev, next, page, pages, labels) {
    prev.classList.toggle('hidden', page <= 0);
    next.classList.toggle('hidden', page >= pages - 1);
    if (labels) {
      prev.querySelector('span').textContent = labels(page - 1);
      next.querySelector('span').textContent = labels(page + 1);
    }
  }

  function turn(el, dir) {
    if (!el) return;
    el.classList.remove('turn-next', 'turn-prev');
    void el.offsetWidth;                       // restart the animation
    el.classList.add(dir > 0 ? 'turn-next' : 'turn-prev');
  }

  /* ---------- rental list ---------- */
  const list    = $('vehicleList');
  const sheet   = list.closest('.sheet');
  const lPrev   = $('listPrev');
  const lNext   = $('listNext');
  const pageNo  = $('listPageNo');
  let listPage  = 0;

  function applyList() {
    const cards = [...list.querySelectorAll('.card')];
    const pages = Math.max(1, Math.ceil(cards.length / CARS_PER_PAGE));
    if (listPage > pages - 1) listPage = pages - 1;

    cards.forEach((c, i) =>
      c.classList.toggle('page-off', Math.floor(i / CARS_PER_PAGE) !== listPage));

    setCorners(lPrev, lNext, listPage, pages, (p) => `Page ${p + 1}`);
    pageNo.textContent = pages > 1 ? `Page ${listPage + 1} of ${pages}` : '';
    list.scrollTop = 0;
  }

  // script.js rebuilds the list on open and on every tab click -> back to page 1
  new MutationObserver(() => { listPage = 0; applyList(); })
    .observe(list, { childList: true });

  lNext.addEventListener('click', () => { listPage++; applyList(); turn(sheet, 1); });
  lPrev.addEventListener('click', () => { listPage--; applyList(); turn(sheet, -1); });

  /* ---------- papers ---------- */
  const papers  = $('papers');
  const docC    = $('docContract');
  const docR    = $('docReg');
  const pPrev   = $('papersPrev');
  const pNext   = $('papersNext');
  let paperPage = 0;

  function applyPapers() {
    const hasReg = !docR.classList.contains('hidden');
    const pages  = hasReg ? 2 : 1;
    if (paperPage > pages - 1) paperPage = pages - 1;

    docC.classList.toggle('page-off', paperPage !== 0);
    docR.classList.toggle('page-off', paperPage !== 1);

    setCorners(pPrev, pNext, paperPage, pages);
  }

  // every time the papers open, start on the agreement
  let papersOpen = false;
  new MutationObserver(() => {
    const open = !papers.classList.contains('hidden');
    if (open && !papersOpen) paperPage = 0;
    papersOpen = open;
    if (open) applyPapers();
  }).observe(papers, { attributes: true, attributeFilter: ['class'] });

  new MutationObserver(applyPapers)
    .observe(docR, { attributes: true, attributeFilter: ['class'] });

  pNext.addEventListener('click', () => { paperPage = 1; applyPapers(); turn(docR, 1); });
  pPrev.addEventListener('click', () => { paperPage = 0; applyPapers(); turn(docC, -1); });

  /* ---------- keyboard: arrow keys flip pages too ---------- */
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
    if (document.activeElement && document.activeElement.tagName === 'INPUT') return;

    const btn = !papers.classList.contains('hidden')
      ? (e.key === 'ArrowRight' ? pNext : pPrev)
      : ($('confirm').classList.contains('hidden') && !$('app').classList.contains('hidden'))
        ? (e.key === 'ArrowRight' ? lNext : lPrev)
        : null;

    if (btn && !btn.classList.contains('hidden')) btn.click();
  });
})();
