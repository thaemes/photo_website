// ─── STATE ────────────────────────────────────────────────
let currentSection = 'photos';
let currentGalleryIndex = 0;
let currentPhotoIndex = 0;
let currentArticleSlug = null;
let _userTouching = false; // true while finger is on screen

// ─── INIT ─────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  buildSidebarNav();
  router();
  window.addEventListener('hashchange', router);
  document.addEventListener('keydown', handleKey);
});

// ─── ROUTER ───────────────────────────────────────────────
function router() {
  const hash = location.hash.slice(1);
  const [sec, id] = hash.split('/');

  if (!sec || sec === 'photos') { showPhotosRoute(id); return; }
  if (sec === 'writing')        { showWritingRoute(id); return; }
  showPhotosRoute();
}

// ─── NAVIGATION ───────────────────────────────────────────
function navigate(path) {
  if (location.hash === `#${path}`) router();
  else location.hash = path;
}

// ─── ROUTE HANDLERS ───────────────────────────────────────
function showPhotosRoute(id) {
  showSection('photos');
  if (!siteData.galleries?.length) return;
  const index = (id !== undefined) ? (parseInt(id) || 0) : currentGalleryIndex;
  loadGallery(index);
}

function showWritingRoute(id) {
  showSection('writing');
  if (!siteData.articles?.length) return;
  if (id) {
    renderArticle(id);
    currentArticleSlug = id;
    buildSidebarNav(); // re-render so the active article is highlighted
  } else {
    showArticleList();
  }
}

// ─── SECTION SWITCHING ────────────────────────────────────
function tabClick(name) {
  if (name === currentSection) { openMobileMenu(); return; }
  navigate(name === 'photos' ? `photos/${currentGalleryIndex}` : 'writing');
}

function showSection(name) {
  currentSection = name;

  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll(`.tab-btn[data-section="${name}"]`).forEach(b => b.classList.add('active'));

  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
  document.getElementById(`section-${name}`).classList.add('active');

  buildSidebarNav();
}

// ─── SIDEBAR NAV ──────────────────────────────────────────
function buildSidebarNav() {
  const nav = document.getElementById('sidebar-nav');
  nav.innerHTML = '';

  if (currentSection === 'photos') {
    (siteData.galleries || []).forEach((g, i) => {
      const btn = document.createElement('button');
      btn.className = 'nav-item' + (i === currentGalleryIndex ? ' active' : '');
      btn.innerHTML = `
        <span class="nav-title">${esc(g.title)}</span>
        ${g.desc ? `<span class="nav-sub">${esc(g.desc)}</span>` : ''}
      `;
      btn.onclick = () => { closeMobileMenu(); navigate(`photos/${i}`); };
      nav.appendChild(btn);
    });
  } else {
    (siteData.articles || []).forEach(a => {
      const btn = document.createElement('button');
      btn.className = 'nav-item' + (a.slug === currentArticleSlug ? ' active' : '');
      btn.innerHTML = `
        <span class="nav-title">${esc(a.title)}</span>
        <span class="nav-sub">${esc(a.date)}</span>
      `;
      btn.onclick = () => { closeMobileMenu(); navigate(`writing/${a.slug}`); };
      nav.appendChild(btn);
    });
  }
}

// ─── MOBILE MENU ──────────────────────────────────────────
function openMobileMenu() {
  const overlay = document.getElementById('mobile-overlay');
  const mobileNav = document.getElementById('mobile-nav-content');
  mobileNav.innerHTML = '';

  const label = document.createElement('div');
  label.className = 'nav-section-label';
  label.textContent = currentSection === 'photos' ? 'Galleries' : 'Articles';
  mobileNav.appendChild(label);

  const items = currentSection === 'photos' ? siteData.galleries : siteData.articles;
  (items || []).forEach((item, i) => {
    const btn = document.createElement('button');
    btn.className = 'nav-item' + (
      currentSection === 'photos'
        ? (i === currentGalleryIndex ? ' active' : '')
        : (item.slug === currentArticleSlug ? ' active' : '')
    );
    if (currentSection === 'photos') {
      btn.innerHTML = `
        <span class="nav-title">${esc(item.title)}</span>
        ${item.desc ? `<span class="nav-sub">${esc(item.desc)}</span>` : ''}
      `;
      btn.onclick = () => { closeMobileMenu(); navigate(`photos/${i}`); };
    } else {
      btn.innerHTML = `
        <span class="nav-title">${esc(item.title)}</span>
        <span class="nav-sub">${esc(item.date)}</span>
      `;
      btn.onclick = () => { closeMobileMenu(); navigate(`writing/${item.slug}`); };
    }
    mobileNav.appendChild(btn);
  });

  overlay.classList.add('open');
  overlay.setAttribute('aria-hidden', 'false');
}

function closeMobileMenu() {
  const overlay = document.getElementById('mobile-overlay');
  overlay.classList.remove('open');
  overlay.setAttribute('aria-hidden', 'true');
}

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeMobileMenu();
});

// ─── GALLERY ──────────────────────────────────────────────
function loadGallery(index) {
  const galleries = siteData.galleries || [];
  if (!galleries.length) return;

  index = Math.max(0, Math.min(index, galleries.length - 1));
  currentGalleryIndex = index;
  currentPhotoIndex = 0;

  // Highlight active gallery in sidebar
  buildSidebarNav();

  const gallery = galleries[index];
  document.getElementById('gallery-title-display').textContent = gallery.title;

  renderStrip(gallery);
  showPhoto(gallery, 0);
}

function renderStrip(gallery) {
  const strip = document.getElementById('gallery-strip');
  strip.innerHTML = '';
  gallery.photos.forEach((p, i) => {
    const img = document.createElement('img');
    img.className = 'strip-thumb' + (i === 0 ? ' active' : '');
    img.src = p;
    img.loading = 'lazy';
    img.onclick = () => showPhoto(gallery, i);
    strip.appendChild(img);
  });
}

function showPhoto(gallery, index) {
  const photos = gallery.photos;
  index = Math.max(0, Math.min(index, photos.length - 1));
  currentPhotoIndex = index;

  const mainImg = document.getElementById('gallery-main-img');
  mainImg.style.opacity = 0;
  mainImg.src = photos[index];
  mainImg.onload = () => mainImg.style.opacity = 1;

  document.getElementById('gallery-counter').textContent = `${index + 1} / ${photos.length}`;

  // Highlight active strip thumb
  document.querySelectorAll('.strip-thumb').forEach((el, i) => {
    el.classList.toggle('active', i === index);
  });

    // Don't fight an active swipe — sync the strip after finger lifts
    if (!_userTouching) {
      const activeThumb = document.querySelector('.strip-thumb.active');
      if (activeThumb) activeThumb.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
    }
   

  // Arrow states
  document.getElementById('arrow-left').disabled = index === 0;
  document.getElementById('arrow-right').disabled = index === photos.length - 1;
}

function galleryNav(dir) {
  const gallery = siteData.galleries[currentGalleryIndex];
  showPhoto(gallery, currentPhotoIndex + dir);
}

// ─── ARTICLES ─────────────────────────────────────────────
function showArticleList() {
  currentArticleSlug = null;
  document.getElementById('writing-list-view').style.display = 'block';
  document.getElementById('writing-article-view').style.display = 'none';
  buildArticleList();
  buildSidebarNav();
}

function buildArticleList() {
  const list = document.getElementById('article-list');
  list.innerHTML = '';
  (siteData.articles || []).forEach(a => {
    const row = document.createElement('div');
    row.className = 'article-list-item';
    row.innerHTML = `
      <span class="article-list-date">${esc(a.date)}</span>
      <div class="article-list-info">
        <div class="article-list-title">${esc(a.title)}</div>
        ${a.desc ? `<div class="article-list-desc">${esc(a.desc)}</div>` : ''}
      </div>
    `;
    row.onclick = () => navigate(`writing/${a.slug}`);
    list.appendChild(row);
  });
}

function renderArticle(slug) {
  const article = (siteData.articles || []).find(a => a.slug === slug);
  if (!article) return;

  document.getElementById('writing-list-view').style.display = 'none';
  document.getElementById('writing-article-view').style.display = 'block';

  document.getElementById('article-content').innerHTML = `
    <h1>${esc(article.title)}</h1>
    <div class="article-date-line">${esc(article.date)}</div>
    ${article.html}
  `;

  window.scrollTo(0, 0);
}

// ─── KEYBOARD ─────────────────────────────────────────────
function handleKey(e) {
  if (currentSection !== 'photos') return;
  if (e.key === 'ArrowLeft')  galleryNav(-1);
  if (e.key === 'ArrowRight') galleryNav(1);
}

// ─── UTIL ─────────────────────────────────────────────────
function esc(s) {
  return String(s || '')
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;');
}

// ─── STRIP SCROLL WHEEL ───────────────────────────────────
// Redirect vertical wheel events on the strip to horizontal scroll
document.addEventListener('DOMContentLoaded', () => {
  const strip = document.getElementById('gallery-strip');
  strip.addEventListener('wheel', e => {
    if (e.deltaY === 0) return;
    e.preventDefault();
    strip.scrollBy({ left: e.deltaY * 2, behavior: 'smooth' });
  }, { passive: false });
});

// ─── TOUCH SWIPE ──────────────────────────────────────────
(function () {
  let startX = 0;
  let startY = 0;
  const THRESHOLD = 40;   // min horizontal px to count as a swipe
  const LOCK = 0.8;       // if vertical movement > LOCK * horizontal, ignore

  const el = document.getElementById ? null : null; // resolved after DOMContentLoaded

  document.addEventListener('touchstart', e => {
    _userTouching = true;
    startX = e.touches[0].clientX;
    startY = e.touches[0].clientY;
  }, { passive: true });

  document.addEventListener('touchend', e => {
    setTimeout(() => { _userTouching = false; }, 400);

    if (currentSection !== 'photos') return;
    const dx = e.changedTouches[0].clientX - startX;
    const dy = e.changedTouches[0].clientY - startY;
    if (Math.abs(dx) < THRESHOLD) return;          // too short
    if (Math.abs(dy) > Math.abs(dx) * LOCK) return; // mostly vertical scroll
    galleryNav(dx < 0 ? 1 : -1);
  }, { passive: true });
})();