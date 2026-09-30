/* d4n-social rules: instagram (content.js) */
// Same design as the X rules: JS finds and *marks* unwanted elements with
// data-tc-* attributes, instagram.cleanser.css hides them, gated on flags on
// <html>. Instagram's class names are generated, so everything keys on hrefs,
// <article>, roles and short label text ("Sponsored", "Suggested for you",
// "Follow"). Marks are recomputed on every scan because Instagram recycles
// nodes as the feed scrolls.
(function () {
  if (window.__d4nInstalled) return;
  window.__d4nInstalled = true;

  const D4N = window.__d4n || {};

  const DEFAULTS = {
    igHideReels: true,             // Reels tab, /reels/ feed, Reels carousels in the home feed
    igHideExplore: true,           // Explore grid tiles; search stays
    igHideSuggestedPosts: true,    // posts from accounts you don't follow
    igHideAds: true,               // "Sponsored" posts
    igHideSuggestedAccounts: true, // "Suggested for you" carousels
    igHideAppNags: true,           // open-in-app banners and dialogs
    igHidePromos: true,            // Threads links and Meta AI entry points
    igHideShopping: true,          // Shop tab and links
    igHideStories: false,          // the stories tray on home
    igHideCounts: false,           // like and view counts
    igHideNotifications: false,    // the heart in the top bar
    igDMOnly: false,               // handled natively: home opens the inbox
    igStopAtCaughtUp: false,       // nothing loads after "You're all caught up"
    igFollowingOnly: false,        // handled natively: home is /?variant=following
    auditMode: false,              // dim and label matches instead of hiding them
  };

  let settings = { ...DEFAULTS, ...(D4N.settings || {}) };

  function post(message) {
    try { window.webkit.messageHandlers.d4n.postMessage(message); } catch (e) { /* not in the app */ }
  }

  function ensureStyle() {
    if (document.getElementById("d4n-style")) return;
    const style = document.createElement("style");
    style.id = "d4n-style";
    style.textContent = D4N.css || "";
    (document.head || document.documentElement).appendChild(style);
  }

  function applyRootFlags() {
    const root = document.documentElement;
    for (const [key, on] of Object.entries(settings)) {
      if (typeof DEFAULTS[key] !== "boolean") continue;
      root.toggleAttribute("data-tc-" + key.toLowerCase(), !!on);
    }
  }

  // ---- Routes ----------------------------------------------------------------
  // The CSS scopes some rules to a page, e.g. the Explore grid. Instagram is a
  // single-page app, so the route is re-read on every scan.

  function route() {
    let p = location.pathname.toLowerCase();
    if (!p.endsWith("/")) p += "/";
    if (p === "/") return "home";
    if (p.startsWith("/explore/search/")) return "search";
    if (p.startsWith("/explore/")) return "explore";
    if (p.startsWith("/reels/")) return "reels";
    if (p.startsWith("/reel/")) return "reel";
    if (p.startsWith("/direct/")) return "direct";
    if (p.startsWith("/p/")) return "post";
    if (p.startsWith("/stories/")) return "story";
    if (p.startsWith("/accounts/")) return "account";
    if (/^\/[^/]+\/$/.test(p)) return "profile";
    return "other";
  }

  function applyRoute() {
    document.documentElement.setAttribute("data-tc-route", route());
  }

  // Blocked pages, mirrored from NavigationPolicy.swift. Taps on them are
  // swallowed before Instagram's router sees them and the app loads the
  // replacement page (home, or the profile for its Reels tab).
  function blockedPath(url) {
    if (!/(^|\.)instagram\.com$/i.test(url.hostname)) return false;
    let p = url.pathname.toLowerCase();
    if (!p.endsWith("/")) p += "/";
    if (settings.igHideReels && (p.startsWith("/reels/") || /^\/[^/]+\/reels\/$/.test(p))) return true;
    if (settings.igHideExplore && p.startsWith("/explore/people")) return true;
    return false;
  }

  window.addEventListener("click", (event) => {
    const anchor = event.target && event.target.closest ? event.target.closest("a[href]") : null;
    if (!anchor) return;
    let url;
    try { url = new URL(anchor.getAttribute("href"), location.href); } catch (e) { return; }
    if (!blockedPath(url)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    post({ type: "route", url: url.href, tap: true });
  }, true);

  // ---- Labels ----------------------------------------------------------------
  // Whole short text nodes, matched case-insensitively. Captions are longer
  // than 40 characters almost always, and never equal one of these. English
  // only: add your Instagram UI language's wording here.

  const LABELS = {
    ad: ["sponsored", "ad"],
    follow: ["follow", "follow back"],
    suggestedAccounts: ["suggested for you", "suggested accounts", "accounts you might like", "people you may know"],
    suggestedPosts: ["suggested posts", "suggested post"],
    reels: ["reels", "suggested reels", "reels for you"],
    caughtUp: ["you're all caught up", "you've completely caught up"],
    nag: ["open", "open app", "open in app", "use the app", "use app", "get app", "get the app",
          "open instagram", "switch to the app", "download the app", "install"],
    promo: ["meta ai", "ask meta ai", "threads", "try threads", "get threads", "join threads"],
  };
  const LABEL_INDEX = new Map();
  for (const [kind, words] of Object.entries(LABELS)) for (const word of words) LABEL_INDEX.set(word, kind);
  const COUNT_RE = /^[\d,.]+\s?[km]?\s(likes?|views?)$/i;

  const norm = (text) => text.replace(/[‘’]/g, "'").replace(/\s+/g, " ").trim().toLowerCase();

  // One pass over the page's short text nodes, bucketed by label kind.
  function collectLabels(root) {
    const hits = { count: [] };
    for (const kind of Object.keys(LABELS)) hits[kind] = [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      const raw = node.nodeValue;
      if (!raw || raw.length > 40) continue;
      const el = node.parentElement;
      if (!el || el.closest("script, style")) continue;
      const text = norm(raw);
      if (!text) continue;
      const kind = LABEL_INDEX.get(text);
      if (kind) hits[kind].push(el);
      else if (COUNT_RE.test(text)) hits.count.push(el);
    }
    return hits;
  }

  const inArticle = (el) => el.closest("article");

  // The child of the feed list that holds `el`: climb while the parent holds
  // no article besides el's own. null when the climb reaches the page root,
  // which happens on pages with no feed, and nothing is hidden there.
  function feedSlot(el) {
    const own = el.matches("article") ? 1 : el.querySelectorAll("article").length;
    let node = el;
    while (node.parentElement && node.parentElement !== document.body &&
           node.parentElement.querySelectorAll("article").length === own) {
      node = node.parentElement;
    }
    return node.parentElement && node.parentElement !== document.body ? node : null;
  }

  // A Follow button in a post's header (above the media) marks an account you
  // don't follow. Buttons lower down belong to comments or tagged accounts.
  function inHeader(article, button) {
    const header = article.querySelector("header") || article.firstElementChild;
    return !!header && header.contains(button);
  }

  // Reconcile one attribute: exactly the wanted elements carry it after this.
  function markSet(attr, wanted) {
    for (const el of document.querySelectorAll(`[${attr}]`)) {
      if (!wanted.has(el)) el.removeAttribute(attr);
    }
    for (const el of wanted) el.setAttribute(attr, "");
  }

  // App nags come as a top banner, a bottom sheet or a dialog. Climb to the
  // container that is positioned or has a banner/dialog role; fall back to
  // the button itself so at least the tap target goes.
  function nagContainer(el) {
    let node = el;
    for (let i = 0; i < 8 && node && node !== document.body; i++, node = node.parentElement) {
      const role = node.getAttribute("role");
      if (role === "banner" || role === "dialog" || role === "alertdialog") return node;
      const position = getComputedStyle(node).position;
      if (position === "fixed" || position === "sticky") return node;
    }
    return el;
  }

  // ---- Scan ------------------------------------------------------------------

  function scan() {
    ensureStyle();
    applyRoute();
    if (!document.body) return;

    const hits = collectLabels(document.body);
    const home = route() === "home";
    const articles = [...document.querySelectorAll("article")];

    // Ads: a "Sponsored" label outside the caption, or ad plumbing in a link.
    const ads = new Set();
    for (const el of hits.ad) {
      const article = inArticle(el);
      if (article && !el.closest("h1, h2")) ads.add(article);
    }
    for (const article of articles) {
      if (article.querySelector('a[href*="/ads/"], a[href*="ig_redirect"]')) ads.add(article);
    }
    markSet("data-tc-ad", ads);

    // Suggested posts, home only: a Follow button in the header, a "Suggested
    // posts" heading (the heading's own slot and every article after it), or
    // anything after "You're all caught up".
    const suggested = new Set();
    let caughtUp = null;
    if (home) {
      for (const el of hits.follow) {
        const button = el.closest("button, [role=button]");
        const article = button && inArticle(button);
        if (article && inHeader(article, button)) suggested.add(article);
      }
      for (const el of hits.suggestedPosts) {
        const article = inArticle(el);
        if (article) { suggested.add(article); continue; }
        const slot = feedSlot(el);
        if (!slot) continue;
        suggested.add(slot);
        for (let sib = slot.nextElementSibling; sib; sib = sib.nextElementSibling) {
          for (const a of sib.matches("article") ? [sib] : sib.querySelectorAll("article")) suggested.add(a);
        }
      }
      caughtUp = hits.caughtUp.find((el) => !inArticle(el)) || null;
      if (caughtUp) {
        for (const article of articles) {
          if (caughtUp.compareDocumentPosition(article) & Node.DOCUMENT_POSITION_FOLLOWING) suggested.add(article);
        }
      }
    }
    markSet("data-tc-suggested", suggested);

    // Modules between posts on home: suggested accounts, Reels carousels.
    const accounts = new Set();
    const reelsModules = new Set();
    if (home) {
      for (const el of hits.suggestedAccounts) {
        if (inArticle(el)) continue;
        const slot = feedSlot(el);
        if (slot) accounts.add(slot);
      }
      for (const el of hits.reels) {
        if (inArticle(el)) continue;
        const slot = feedSlot(el);
        if (slot && slot.querySelector('a[href^="/reel/"]')) reelsModules.add(slot);
      }
      for (const link of document.querySelectorAll('a[href^="/reel/"]')) {
        if (inArticle(link)) continue;
        const slot = feedSlot(link);
        if (slot && slot.querySelectorAll('a[href^="/reel/"]').length >= 2) reelsModules.add(slot);
      }
    }
    markSet("data-tc-suggestedaccounts", accounts);
    markSet("data-tc-reelsmodule", reelsModules);

    // Past the stop point Instagram serves only suggestions. Hiding them one
    // by one leaves the infinite-scroll sentinel on screen and the site keeps
    // fetching pages nobody sees, so the rest of the list is hidden instead.
    // The stop point is the caught-up marker (with that setting on) or the
    // start of a long trailing run of hidden posts.
    const after = new Set();
    if (home) {
      let stop = settings.igStopAtCaughtUp ? caughtUp : null;
      if (!stop && settings.igHideSuggestedPosts) {
        let run = 0;
        while (run < articles.length) {
          const article = articles[articles.length - 1 - run];
          if (!suggested.has(article) && !ads.has(article)) break;
          run++;
        }
        if (run >= 8) stop = articles[articles.length - run];
      }
      const slot = stop && feedSlot(stop);
      for (let sib = slot && slot.nextElementSibling; sib; sib = sib.nextElementSibling) after.add(sib);
    }
    markSet("data-tc-aftercaughtup", after);

    // Stories tray on home: the smallest ancestor holding every story link,
    // or a list of avatars above the first post when the items are buttons.
    const stories = new Set();
    if (home && settings.igHideStories) {
      const links = [...document.querySelectorAll('a[href^="/stories/"]')].filter((l) => !inArticle(l));
      if (links.length >= 3) {
        let node = links[0];
        while (node.parentElement && node.parentElement !== document.body &&
               node.querySelectorAll('a[href^="/stories/"]').length < links.length) {
          node = node.parentElement;
        }
        if (!node.querySelector("article")) stories.add(node);
      } else if (articles.length) {
        for (const list of document.querySelectorAll("main ul")) {
          const items = list.querySelectorAll(":scope > li");
          if (items.length >= 4 && !list.querySelector("article") &&
              (articles[0].compareDocumentPosition(list) & Node.DOCUMENT_POSITION_PRECEDING) &&
              list.querySelector("canvas, img")) {
            stories.add(list);
            break;
          }
        }
      }
    }
    markSet("data-tc-stories", stories);

    const counts = new Set();
    if (settings.igHideCounts) for (const el of hits.count) counts.add(el);
    markSet("data-tc-count", counts);

    const nags = new Set();
    if (settings.igHideAppNags) {
      for (const link of document.querySelectorAll(
        'a[href*="apps.apple.com"], a[href*="itunes.apple.com"], a[href^="instagram://"], a[href*="play.google.com"]')) {
        nags.add(nagContainer(link));
      }
      for (const el of hits.nag) {
        const button = el.closest("button, [role=button], a");
        if (!button) continue;
        const container = nagContainer(button);
        // A bare "Open" only counts inside a banner or dialog.
        if (norm(el.textContent) === "open" && container === button) continue;
        nags.add(container);
      }
    }
    markSet("data-tc-appnag", nags);

    const promos = new Set();
    if (settings.igHidePromos) {
      for (const el of hits.promo) {
        const control = el.closest("a, button, [role=button], [role=menuitem]");
        if (control && !inArticle(control)) promos.add(control);
      }
    }
    markSet("data-tc-promo", promos);

    reportStats();
  }

  // Stats for the app: counts of marked elements per setting key.
  const STAT_MARKS = {
    igHideAds: "data-tc-ad",
    igHideSuggestedPosts: "data-tc-suggested",
    igHideSuggestedAccounts: "data-tc-suggestedaccounts",
    igHideReels: "data-tc-reelsmodule",
    igHideAppNags: "data-tc-appnag",
    igHidePromos: "data-tc-promo",
    igHideStories: "data-tc-stories",
    igHideCounts: "data-tc-count",
    igStopAtCaughtUp: "data-tc-aftercaughtup",
  };

  function collectStats() {
    const out = {};
    for (const [key, attr] of Object.entries(STAT_MARKS)) {
      out[key] = document.querySelectorAll(`[${attr}]`).length;
    }
    return out;
  }

  let lastStats = "";
  function reportStats() {
    const stats = collectStats();
    const json = JSON.stringify(stats);
    if (json === lastStats) return;
    lastStats = json;
    post({ type: "stats", stats });
  }

  let scanTimer = null;
  function scheduleScan() {
    if (scanTimer) return;
    scanTimer = setTimeout(() => {
      scanTimer = null;
      scan();
    }, 250);
  }

  // ---- App bridge ------------------------------------------------------------

  window.__d4nApplySettings = function (next) {
    settings = { ...DEFAULTS, ...next };
    applyRootFlags();
    scan();
  };

  window.__d4nStats = collectStats;

  function start() {
    applyRootFlags();
    scan();
    new MutationObserver(scheduleScan).observe(document.body, { childList: true, subtree: true, characterData: true });
    window.addEventListener("popstate", scheduleScan);
  }

  applyRootFlags();
  if (document.body) start();
  else document.addEventListener("DOMContentLoaded", start, { once: true });
})();
