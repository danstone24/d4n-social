/* d4n-social rules: x (content.js) */
// Ported from the TwitterCleanser extension for mobile x.com inside the app's
// WebView. Strategy is unchanged: JS finds and *marks* unwanted elements with
// data-tc-* attributes, x.cleanser.css does the hiding, gated on flags set on
// <html>. Toggling a setting off just removes the root flag.
//
// What changed from the extension: settings arrive from the app through
// window.__d4n (injected before this file) and window.__d4nApplySettings();
// hidden counts and the block log go back through
// window.webkit.messageHandlers.d4n; and the mobile layout has no sidebar,
// so trending and premium modules are found in timeline cells instead.
(function () {
  if (window.__d4nInstalled) return;
  window.__d4nInstalled = true;

  const D4N = window.__d4n || {};

  const DEFAULTS = {
    hideAds: true,          // promoted tweets and promoted trends
    hideTrending: true,     // "What's happening" / "Trends for you" modules
    hideWhoToFollow: true,  // follow suggestions, inline in timelines and on Explore
    hidePremium: true,      // premium upsell boxes and menu links
    hideGrok: true,         // Grok tab and per-tweet Grok buttons
    hideGrokMentions: true, // posts and replies whose text mentions @grok
    hideMentionOnlyReplies: true, // replies that are just @mentions, no words
    hideLinkOnlyPosts: true, // posts whose text is nothing but a link
    hideDiscoverMore: true, // suggested posts appended below conversations
    followingOnly: true,    // hide the "For You" tab and auto-switch to "Following"
    blockButtons: true,     // one-click block button on every post and reply

    auditMode: false,        // testing aid: dim and label matches instead of hiding them

    // Beta filters: off by default, tagged "beta" in the app until tested.
    betaMuteWords: false,      // hide posts containing custom mute words
    muteWordsList: "",         // the words, one per line (string, not a toggle)
    betaLowEffort: false,      // "This" / "W" / emoji-only replies
    betaEngagementBait: false, // "repost if", "tag a friend", giveaways
    betaHideReposts: false,    // strip retweets from timelines
    betaHashtagSpam: false,    // posts with 5+ hashtags
    betaSlimNav: false,        // hide unused nav entries
    betaHideNags: false,       // "Turn on notifications" style prompts
    betaHideViews: false,      // view counts in action bars
    betaMuteButton: false,     // one-click mute next to the block button
    betaHideAIPosts: false,    // posts that say they're AI-made, or carry X's "Made with AI" label
    betaHideParody: false,     // parody / fan / satire accounts
    betaHideVerifiedReplies: false, // blue-check replies in conversations
  };

  let settings = { ...DEFAULTS, ...(D4N.settings || {}) };

  function post(message) {
    try { window.webkit.messageHandlers.d4n.postMessage(message); } catch (e) { /* not in the app */ }
  }

  // The CSS comes in through the prelude; re-added if the page's hydration drops it.
  function ensureStyle() {
    if (document.getElementById("d4n-style")) return;
    const style = document.createElement("style");
    style.id = "d4n-style";
    style.textContent = D4N.css || "";
    (document.head || document.documentElement).appendChild(style);
  }

  // Module headings, matched case-insensitively.
  const HEADINGS = {
    trending: /^(what.s happening|trends for you|trending now|today.s news)/i,
    whoToFollow: /^(who to follow|you might like|suggested for you|creators for you)/i,
    premium: /^(subscribe to premium|get verified|premium)/i,
    discoverMore: /^(discover more|more tweets|more posts)/i,
  };

  function applyRootFlags() {
    const root = document.documentElement;
    for (const [key, on] of Object.entries(settings)) {
      if (typeof DEFAULTS[key] !== "boolean") continue; // e.g. muteWordsList
      root.toggleAttribute("data-tc-" + key.toLowerCase(), !!on);
    }
  }

  // Sidebar sections (desktop layout only; harmless on mobile).
  function sidebarContainer(heading) {
    const section = heading.closest("section, aside");
    if (!section) return heading.closest('div[data-testid="sidebarColumn"] > div div') || heading;
    const parent = section.parentElement;
    if (parent && parent.querySelectorAll("h2").length === section.querySelectorAll("h2").length) {
      return parent;
    }
    return section;
  }

  // Promoted posts carry an "Ad" label span, promoted trends a "Promoted by …"
  // one. Don't use data-testid="placementTracking" for this: X also wraps video
  // players in it, which made posts vanish when a video started playing.
  const AD_LABEL = /^(Ad|Promoted( by .+)?)$/;

  function hasAdLabel(root) {
    for (const span of root.querySelectorAll("span")) {
      const text = span.textContent.trim();
      if (text.length <= 40 && AD_LABEL.test(text) && !span.closest('[data-testid="tweetText"]')) {
        return true;
      }
    }
    return false;
  }

  function cellOf(article) {
    return article.closest('div[data-testid="cellInnerDiv"]') || article;
  }

  function markAds() {
    // Each article/trend is label-checked once (marked data-tc-adchecked) so the
    // debounced rescans stay cheap on long timelines.
    for (const article of document.querySelectorAll('article[data-testid="tweet"]:not([data-tc-adchecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue; // still rendering
      article.setAttribute("data-tc-adchecked", "");
      if (hasAdLabel(article)) cellOf(article).setAttribute("data-tc-ad", "");
    }
    for (const trend of document.querySelectorAll('[data-testid="trend"]:not([data-tc-adchecked])')) {
      trend.setAttribute("data-tc-adchecked", "");
      if (hasAdLabel(trend)) cellOf(trend).setAttribute("data-tc-ad", "");
    }
  }

  function markSidebar() {
    for (const h2 of document.querySelectorAll('div[data-testid="sidebarColumn"] h2')) {
      const text = h2.textContent.trim();
      let kind = null;
      if (HEADINGS.trending.test(text)) kind = "trending";
      else if (HEADINGS.whoToFollow.test(text)) kind = "whotofollow";
      else if (HEADINGS.premium.test(text)) kind = "premium";
      if (kind) sidebarContainer(h2).setAttribute("data-tc-" + kind, "");
    }
  }

  function markGrokMentions() {
    // Only the article's own text (first tweetText), not quoted content:
    // quoting a grok post isn't the author summoning grok.
    for (const article of document.querySelectorAll('article[data-testid="tweet"]:not([data-tc-grokchecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue;
      article.setAttribute("data-tc-grokchecked", "");
      const text = article.querySelector('[data-testid="tweetText"]');
      if (!text) continue;
      const mentions = text.querySelector('a[href="/grok"]') || /@grok\b/i.test(text.textContent);
      if (mentions) cellOf(article).setAttribute("data-tc-grokmention", "");
    }
  }

  function markMentionOnlyReplies() {
    // "Tag a friend" replies: @mentions and nothing else. Conversation pages
    // only, and never the focused post itself (it has tabindex="-1").
    if (!location.pathname.includes("/status/")) return;
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-tagonlychecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue;
      article.setAttribute("data-tc-tagonlychecked", "");
      const texts = article.querySelectorAll('[data-testid="tweetText"]');
      if (texts.length !== 1) continue; // no text at all, or quoted content
      // A photo, video or link card is real content even with mention-only text
      if (article.querySelector('[data-testid="tweetPhoto"], [data-testid="videoPlayer"], [data-testid="card.wrapper"]')) continue;
      const text = texts[0].textContent;
      if (/@\w/.test(text) && text.replace(/@\w{1,15}/g, "").trim() === "") {
        cellOf(article).setAttribute("data-tc-mentiononly", "");
      }
    }
  }

  function markLinkOnlyPosts() {
    // Posts whose text is just a URL and no words. Attached photos/videos are
    // real content and keep the post; a link preview card is generated from the
    // URL itself so it doesn't count. Never the focused post (tabindex="-1").
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-linkchecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue;
      article.setAttribute("data-tc-linkchecked", "");
      const texts = article.querySelectorAll('[data-testid="tweetText"]');
      if (texts.length !== 1) continue;
      if (article.querySelector('[data-testid="tweetPhoto"], [data-testid="videoPlayer"]')) continue;
      // Real URLs are absolute (t.co); mentions and hashtags use relative hrefs
      const links = texts[0].querySelectorAll("a");
      const hasUrl = [...links].some((a) => /^https?:\/\//.test(a.getAttribute("href") || ""));
      if (!hasUrl) continue;
      const clone = texts[0].cloneNode(true);
      for (const a of clone.querySelectorAll("a")) a.remove();
      if (clone.textContent.trim() === "") cellOf(article).setAttribute("data-tc-linkonly", "");
    }
  }

  // ---- Beta filters ----------------------------------------------------------

  function markMuteWords() {
    if (!settings.betaMuteWords) return;
    const words = (settings.muteWordsList || "")
      .toLowerCase()
      .split(/[\n,]/)
      .map((w) => w.trim())
      .filter(Boolean);
    if (!words.length) return;
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-mutechecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue;
      article.setAttribute("data-tc-mutechecked", "");
      const text = article.querySelector('[data-testid="tweetText"]');
      if (!text) continue;
      const t = text.textContent.toLowerCase();
      if (words.some((w) => t.includes(w))) cellOf(article).setAttribute("data-tc-muteword", "");
    }
  }

  // Whole-reply matches only: a reply that IS one of these, not one containing them
  const LOW_EFFORT_WORDS = new Set([
    "this", "w", "l", "first", "fr", "frfr", "real", "facts", "based", "same",
    "true", "lol", "lmao", "rip", "goat", "goated", "cap", "nocap", "bet",
  ]);

  function isLowEffort(raw) {
    const t = raw.trim().toLowerCase();
    if (!t) return false;
    // Emoji / punctuation-only replies (digits and letters count as content)
    const meaningful = t.replace(/[\p{Extended_Pictographic}\p{P}\p{S}\s‍️]/gu, "");
    if (meaningful === "") return true;
    return LOW_EFFORT_WORDS.has(t.replace(/[\s\p{P}]+/gu, ""));
  }

  function markLowEffortReplies() {
    if (!settings.betaLowEffort) return;
    if (!location.pathname.includes("/status/")) return;
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-loweffortchecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue;
      article.setAttribute("data-tc-loweffortchecked", "");
      const texts = article.querySelectorAll('[data-testid="tweetText"]');
      if (texts.length !== 1) continue;
      if (article.querySelector('[data-testid="tweetPhoto"], [data-testid="videoPlayer"]')) continue;
      if (isLowEffort(texts[0].textContent)) cellOf(article).setAttribute("data-tc-loweffort", "");
    }
  }

  const BAIT_PATTERNS = [
    /\brepost (this|if)\b/i,
    /\bretweet (this|if)\b/i,
    /\blike (and|if|this post)\b/i,
    /\btag (a friend|someone|your|3 )/i,
    /\bfollow (me|back|us|for)\b/i,
    /\bfollow \+/i,
    /\bcomment below\b/i,
    /\bdrop a\b[^.!?]*\bbelow\b/i,
    /\bgiveaway\b/i,
    /\bturn on (my )?notifications\b/i,
  ];

  function markEngagementBait() {
    if (!settings.betaEngagementBait) return;
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-baitchecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue;
      article.setAttribute("data-tc-baitchecked", "");
      const text = article.querySelector('[data-testid="tweetText"]');
      if (!text) continue;
      if (BAIT_PATTERNS.some((p) => p.test(text.textContent))) cellOf(article).setAttribute("data-tc-bait", "");
    }
  }

  function markReposts() {
    if (!settings.betaHideReposts) return;
    // "X reposted" social-context header above retweeted timeline cells
    for (const sc of document.querySelectorAll('[data-testid="socialContext"]')) {
      if (/\breposted\b/i.test(sc.textContent)) {
        sc.closest('div[data-testid="cellInnerDiv"]')?.setAttribute("data-tc-repost", "");
      }
    }
  }

  function markHashtagSpam() {
    if (!settings.betaHashtagSpam) return;
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-hashchecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue;
      article.setAttribute("data-tc-hashchecked", "");
      const text = article.querySelector('[data-testid="tweetText"]');
      if (!text) continue;
      if (text.querySelectorAll('a[href^="/hashtag/"]').length >= 5) cellOf(article).setAttribute("data-tc-hashtagspam", "");
    }
  }

  function markNags() {
    if (!settings.betaHideNags) return;
    // Inline prompts injected into timelines ("Turn on notifications" etc.)
    for (const prompt of document.querySelectorAll('[data-testid="inlinePrompt"]')) {
      cellOf(prompt).setAttribute("data-tc-nag", "");
    }
  }

  const AI_PATTERNS = [
    /\bmade (with|by|using) (ai|grok|midjourney|sora|dall[\s-]?e|stable diffusion)\b/i,
    /\bgenerated (with|by|using) (ai|grok|midjourney|sora|dall)/i,
    /\bai[- ]generated\b/i,
    /\bgrok imagine\b/i,
    /#(aiart|aiartwork|aiartcommunity|midjourney|stablediffusion|dalle|sora|grokimagine|aivideo|aiimages)\b/i,
  ];

  // X's own label under AI-generated media ("✦ Made with AI"), rendered outside
  // the post text, so it's found the same way as the "Ad" label.
  const AI_LABEL = /^(made with (ai|grok)|ai[- ]generated)$/i;

  function hasAILabel(article) {
    for (const span of article.querySelectorAll("span")) {
      const text = span.textContent.trim();
      if (text.length <= 20 && AI_LABEL.test(text) && !span.closest('[data-testid="tweetText"]')) return true;
    }
    return false;
  }

  function markAIPosts() {
    if (!settings.betaHideAIPosts) return;
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-aichecked])')) {
      if (!article.querySelector('div[data-testid="User-Name"]')) continue;
      article.setAttribute("data-tc-aichecked", "");
      const text = article.querySelector('[data-testid="tweetText"]');
      const saysAI = text && AI_PATTERNS.some((p) => p.test(text.textContent));
      if (saysAI || hasAILabel(article)) cellOf(article).setAttribute("data-tc-aipost", "");
    }
  }

  // X policy requires parody accounts to label themselves in the display name,
  // so the header text (name + @handle) is the reliable signal.
  const PARODY_PATTERN = /\b(parody|satire|fan account|fan page|commentary|not affiliated)\b/i;

  function markParody() {
    if (!settings.betaHideParody) return;
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-parodychecked])')) {
      const name = article.querySelector('div[data-testid="User-Name"]');
      if (!name) continue;
      article.setAttribute("data-tc-parodychecked", "");
      if (PARODY_PATTERN.test(name.textContent)) cellOf(article).setAttribute("data-tc-parody", "");
    }
  }

  function markVerifiedReplies() {
    if (!settings.betaHideVerifiedReplies) return;
    if (!location.pathname.includes("/status/")) return;
    for (const article of document.querySelectorAll('article[data-testid="tweet"][tabindex="0"]:not([data-tc-vrchecked])')) {
      // First User-Name is the reply's author; quoted posts come later in DOM
      const name = article.querySelector('div[data-testid="User-Name"]');
      if (!name) continue;
      article.setAttribute("data-tc-vrchecked", "");
      if (name.querySelector('svg[data-testid="icon-verified"]')) cellOf(article).setAttribute("data-tc-verifiedreply", "");
    }
  }

  // Marks a heading cell and the sibling cells that belong to its module,
  // stopping at the first cell that matches neither the items nor "show more".
  function markModuleRun(cell, attr, isItem, isShowMore) {
    cell.setAttribute(attr, "");
    let sib = cell.nextElementSibling;
    while (sib) {
      const item = isItem(sib);
      const more = isShowMore(sib);
      if (!item && !more) break;
      sib.setAttribute(attr, "");
      if (more) break;
      sib = sib.nextElementSibling;
    }
  }

  function markInlineModules() {
    // Inline modules in timelines and on the Explore tab: a heading cell
    // followed by content cells. On mobile this is where trending and premium
    // boxes live too, since there is no sidebar.
    const main = document.querySelector('main[role="main"]') || document.querySelector("main");
    if (!main) return;
    for (const h2 of main.querySelectorAll('div[data-testid="cellInnerDiv"] h2')) {
      const text = h2.textContent.trim();
      const cell = h2.closest('div[data-testid="cellInnerDiv"]');
      if (!cell) continue;

      if (HEADINGS.whoToFollow.test(text)) {
        markModuleRun(cell, "data-tc-whotofollow",
          (sib) => sib.querySelector('[data-testid="UserCell"]'),
          (sib) => sib.querySelector('a[href^="/i/connect_people"]'));
      } else if (HEADINGS.trending.test(text)) {
        markModuleRun(cell, "data-tc-trending",
          (sib) => sib.querySelector('[data-testid="trend"]'),
          (sib) => sib.querySelector('a[href^="/explore/tabs"], a[href="/i/trends"]'));
      } else if (HEADINGS.premium.test(text)) {
        cell.setAttribute("data-tc-premium", "");
      } else if (HEADINGS.discoverMore.test(text)) {
        // Everything after a "Discover more" heading is algorithmic filler.
        cell.setAttribute("data-tc-discovermore", "");
        for (let sib = cell.nextElementSibling; sib; sib = sib.nextElementSibling) {
          sib.setAttribute("data-tc-discovermore", "");
        }
      }
    }
  }

  function handleHomeTabs() {
    if (!settings.followingOnly) return;
    if (!/^\/(home)?\/?$/.test(location.pathname)) return;
    const tabs = document.querySelectorAll('[role="tablist"] [role="tab"]');
    let forYou = null;
    let following = null;
    for (const tab of tabs) {
      const text = tab.textContent.trim();
      if (/^for you$/i.test(text)) forYou = tab;
      else if (/^following$/i.test(text)) following = tab;
    }
    if (forYou) forYou.setAttribute("data-tc-foryou", "");
    // If "For You" is the active tab, hop over to "Following".
    if (forYou?.getAttribute("aria-selected") === "true" && following) following.click();
  }

  // ---- One-click block -------------------------------------------------------
  // Blocks via X's own web API (same endpoint the official Block menu item hits),
  // authenticated by the logged-in session's cookies + csrf token. This is the
  // web client's long-standing public bearer token, not a secret.
  const BLOCK_BEARER =
    "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA";

  function csrfToken() {
    return document.cookie.match(/(?:^|;\s*)ct0=([^;]+)/)?.[1];
  }

  async function blockApi(endpoint, handle) {
    const csrf = csrfToken();
    if (!csrf) throw new Error("not logged in");
    const res = await fetch(`${location.origin}/i/api/1.1/${endpoint}.json`, {
      method: "POST",
      credentials: "include",
      headers: {
        authorization: BLOCK_BEARER,
        "x-csrf-token": csrf,
        "x-twitter-auth-type": "OAuth2Session",
        "x-twitter-active-user": "yes",
        "content-type": "application/x-www-form-urlencoded",
      },
      body: "screen_name=" + encodeURIComponent(handle),
    });
    if (!res.ok) throw new Error("HTTP " + res.status);
  }

  // Toast with an Undo action, reused across blocks.
  let toastEl = null;
  let toastTimer = null;

  function hideToast() {
    toastEl?.classList.remove("tc-visible");
  }

  function showToast(text, onUndo) {
    if (!toastEl) {
      toastEl = document.createElement("div");
      toastEl.className = "tc-toast";
      document.body.appendChild(toastEl);
    }
    toastEl.textContent = text;
    if (onUndo) {
      const undo = document.createElement("button");
      undo.textContent = "Undo";
      undo.addEventListener("click", () => {
        hideToast();
        onUndo();
      });
      toastEl.appendChild(undo);
    }
    toastEl.classList.add("tc-visible");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, 8000);
  }

  // The block log lives in the app (Filters > Block log).
  function logBlock(handle) { post({ type: "blocklog", action: "add", handle }); }
  function unlogBlock(handle) { post({ type: "blocklog", action: "remove", handle }); }

  async function blockUser(handle, article) {
    const cell = cellOf(article);
    try {
      await blockApi("blocks/create", handle);
      logBlock(handle);
      cell.setAttribute("data-tc-blockedhide", "");
      showToast(`Blocked @${handle}`, async () => {
        cell.removeAttribute("data-tc-blockedhide");
        try {
          await blockApi("blocks/destroy", handle);
          unlogBlock(handle);
          showToast(`Unblocked @${handle}`);
        } catch (err) {
          showToast(`Unblock failed: ${err.message}`);
        }
      });
    } catch (err) {
      showToast(`Block failed: ${err.message}`);
    }
  }

  async function muteUser(handle, article) {
    const cell = cellOf(article);
    try {
      await blockApi("mutes/create", handle);
      cell.setAttribute("data-tc-blockedhide", "");
      showToast(`Muted @${handle}`, async () => {
        cell.removeAttribute("data-tc-blockedhide");
        try {
          await blockApi("mutes/destroy", handle);
          showToast(`Unmuted @${handle}`);
        } catch (err) {
          showToast(`Unmute failed: ${err.message}`);
        }
      });
    } catch (err) {
      showToast(`Mute failed: ${err.message}`);
    }
  }

  function blockIcon() {
    // Circle-with-slash matching X's own Block menu icon, drawn as strokes.
    const NS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    const circle = document.createElementNS(NS, "circle");
    circle.setAttribute("cx", "12");
    circle.setAttribute("cy", "12");
    circle.setAttribute("r", "8.25");
    const line = document.createElementNS(NS, "line");
    line.setAttribute("x1", "6.17");
    line.setAttribute("y1", "17.83");
    line.setAttribute("x2", "17.83");
    line.setAttribute("y2", "6.17");
    svg.append(circle, line);
    return svg;
  }

  function muteIcon() {
    // Speaker with an X, matching the stroke style of the block icon
    const NS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    const speaker = document.createElementNS(NS, "polygon");
    speaker.setAttribute("points", "11 5 6 9 2 9 2 15 6 15 11 19 11 5");
    const x1 = document.createElementNS(NS, "line");
    x1.setAttribute("x1", "23");
    x1.setAttribute("y1", "9");
    x1.setAttribute("x2", "17");
    x1.setAttribute("y2", "15");
    const x2 = document.createElementNS(NS, "line");
    x2.setAttribute("x1", "17");
    x2.setAttribute("y1", "9");
    x2.setAttribute("x2", "23");
    x2.setAttribute("y2", "15");
    svg.append(speaker, x1, x2);
    return svg;
  }

  // The profile link only exists in the mobile account drawer, so remember it
  // once seen; until then own posts get buttons too, which is harmless.
  let cachedHandle = null;
  function ownHandle() {
    const link =
      document.querySelector('a[data-testid="AppTabBar_Profile_Link"]') ||
      document.querySelector('nav a[aria-label="Profile"]');
    if (link) cachedHandle = link.getAttribute("href").slice(1).toLowerCase();
    return cachedHandle;
  }

  function authorHandle(article) {
    // First User-Name in the article is the outer author (quoted tweets nest later).
    const link = article.querySelector('div[data-testid="User-Name"] a[href^="/"]');
    const handle = link?.getAttribute("href").split("/")[1] || "";
    return /^[A-Za-z0-9_]{1,15}$/.test(handle) ? handle : null;
  }

  function makeActionButton(className, label, icon, onClick) {
    const btn = document.createElement("button");
    btn.className = className;
    btn.setAttribute("aria-label", label);
    btn.title = label;
    btn.appendChild(icon);
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      onClick();
    });
    return btn;
  }

  function injectActionButtons() {
    const me = ownHandle();
    for (const article of document.querySelectorAll('article[data-testid="tweet"]:not([data-tc-blockbtn])')) {
      const bar = article.querySelector('div[role="group"]');
      const handle = authorHandle(article);
      if (!bar || !handle) continue; // not rendered yet, retry on next scan
      article.setAttribute("data-tc-blockbtn", "");
      if (handle.toLowerCase() === me) continue; // no buttons on own posts

      // Mute button (beta) sits before block; CSS hides it unless enabled
      bar.appendChild(makeActionButton("tc-mute-btn", `Mute @${handle}`, muteIcon(), () => muteUser(handle, article)));
      bar.appendChild(makeActionButton("tc-block-btn", `Block @${handle}`, blockIcon(), () => blockUser(handle, article)));
    }
  }

  // Stats for the app: counts of marked elements per setting key, shown next
  // to each toggle and on the audit screen.
  const STAT_MARKS = {
    hideAds: "data-tc-ad",
    hideTrending: "data-tc-trending",
    hideWhoToFollow: "data-tc-whotofollow",
    hidePremium: "data-tc-premium",
    hideDiscoverMore: "data-tc-discovermore",
    hideGrokMentions: "data-tc-grokmention",
    hideMentionOnlyReplies: "data-tc-mentiononly",
    hideLinkOnlyPosts: "data-tc-linkonly",
    followingOnly: "data-tc-foryou",
    betaMuteWords: "data-tc-muteword",
    betaLowEffort: "data-tc-loweffort",
    betaEngagementBait: "data-tc-bait",
    betaHideReposts: "data-tc-repost",
    betaHashtagSpam: "data-tc-hashtagspam",
    betaHideNags: "data-tc-nag",
    betaHideAIPosts: "data-tc-aipost",
    betaHideParody: "data-tc-parody",
    betaHideVerifiedReplies: "data-tc-verifiedreply",
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

  function scan() {
    ensureStyle();
    markAds();
    markGrokMentions();
    markMentionOnlyReplies();
    markLinkOnlyPosts();
    markMuteWords();
    markLowEffortReplies();
    markEngagementBait();
    markReposts();
    markHashtagSpam();
    markNags();
    markAIPosts();
    markParody();
    markVerifiedReplies();
    markSidebar();
    markInlineModules();
    handleHomeTabs();
    injectActionButtons();
    reportStats();
  }

  // Debounced rescan on DOM changes; X re-renders constantly.
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
    const wordsChanged = (next.muteWordsList || "") !== (settings.muteWordsList || "");
    settings = { ...DEFAULTS, ...next };
    if (wordsChanged) {
      // Word list changed: throw away cached verdicts so posts get re-checked
      for (const el of document.querySelectorAll("[data-tc-mutechecked]")) el.removeAttribute("data-tc-mutechecked");
      for (const el of document.querySelectorAll("[data-tc-muteword]")) el.removeAttribute("data-tc-muteword");
    }
    applyRootFlags();
    scan();
  };

  window.__d4nUnblock = async function (handle) {
    await blockApi("blocks/destroy", handle);
    unlogBlock(handle);
    return true;
  };

  window.__d4nStats = collectStats;

  function start() {
    applyRootFlags();
    scan();
    new MutationObserver(scheduleScan).observe(document.body, { childList: true, subtree: true });
  }

  applyRootFlags();
  if (document.body) start();
  else document.addEventListener("DOMContentLoaded", start, { once: true });
})();
