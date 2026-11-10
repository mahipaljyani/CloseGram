import Foundation

/// The JavaScript that runs inside instagram.com at document start.
/// It does all the in-page work: hiding Reels, Explore, suggested posts, likes and stories,
/// the following-only and messages-only route guards, the feed stop, and grayscale.
/// Instagram's class names are obfuscated, so everything matches on URLs, structure and visible text.
enum InjectedScript {
    static func source(_ config: ScriptConfig) -> String {
        let json = (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "window.__qgCfg = \(json);\n" + body
    }

    private static let body = #"""
    (function () {
      if (window.__qgInstalled) { return; }
      window.__qgInstalled = true;
      var cfg = window.__qgCfg;

      function post(msg) { try { window.webkit.messageHandlers.qg.postMessage(msg); } catch (e) {} }
      function log() { post({ type: 'log', text: Array.prototype.join.call(arguments, ' ') }); }

      // ---- 1. Static CSS -------------------------------------------------
      var css = [];
      if (cfg.blockReels) {
        css.push('a[href="/reels/"]{display:none!important}');
      }
      if (cfg.blockExplore) {
        // On the Explore page keep the search bar, hide the recommendation grid.
        css.push('html[data-qg-route="explore"] main a[href^="/p/"],' +
                 'html[data-qg-route="explore"] main a[href*="/reel/"]{display:none!important}');
      }
      if (cfg.messagesOnly) {
        css.push('a[href="/"],a[href="/explore/"],a[href="/reels/"]{display:none!important}');
      }
      if (cfg.hideLikes) {
        css.push('a[href$="/liked_by/"]{display:none!important}');
      }
      if (cfg.grayscale) {
        css.push('html{filter:grayscale(1)!important}');
      }
      css.push('[data-qg-hidden="1"],[data-qg-cut="1"]{display:none!important}');
      css.push('.qg-stop{padding:56px 24px 72px;text-align:center;font:15px/1.4 -apple-system,system-ui,sans-serif;color:inherit}' +
               '.qg-stop b{display:block;font-size:20px;margin-bottom:6px}' +
               '.qg-stop span{opacity:.6}');
      // Make the website feel like an app: no tap flash, no long-press callout,
      // no text selection outside fields, no double-tap zoom.
      css.push('*{-webkit-tap-highlight-color:transparent!important;-webkit-touch-callout:none!important}');
      css.push('body{-webkit-user-select:none;user-select:none;touch-action:manipulation}');
      css.push('input,textarea,[contenteditable="true"],[contenteditable="true"] *{-webkit-user-select:text!important;user-select:text!important}');

      function addStyle() {
        if (document.getElementById('qg-style')) { return; }
        var style = document.createElement('style');
        style.id = 'qg-style';
        style.textContent = css.join('\n');
        (document.head || document.documentElement).appendChild(style);
      }
      addStyle();

      // Lock the zoom level. Instagram rewrites its own viewport tag, so this re-runs on every sweep.
      function lockViewport() {
        var want = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          if (!document.head) { return; }
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        if (meta.content !== want) { meta.content = want; }
      }

      // ---- 2. Route guard (Instagram is a single-page app) ----------------
      // Paths allowed in messages-only mode: the inbox and threads, a post or reel someone
      // sent you, and the login and account pages.
      var MESSAGES_OK = /^\/(direct|accounts|challenge|two_factor|p|reel)(\/|$)/;
      var route = 'other';

      function onRoute() {
        var path = location.pathname;
        route = 'other';
        if (path === '/') { route = 'home'; }
        else if (/^\/explore\/?$/.test(path)) { route = 'explore'; }
        document.documentElement.setAttribute('data-qg-route', route);
        post({ type: 'route', path: path });

        if (cfg.messagesOnly && !MESSAGES_OK.test(path)) {
          location.replace('/direct/inbox/');
          return;
        }
        if (cfg.blockReels) {
          // /reels/<id>/ is the endless swipe feed opened on one video.
          // /reel/<id>/ is the same video as a single post page, with no next video.
          var single = path.match(/^\/reels\/([^\/]+)\/?$/);
          if (single) { location.replace('/reel/' + single[1] + '/'); return; }
          if (/^\/reels\/?$/.test(path)) { location.replace('/'); return; }
        }
        if (cfg.followingOnly && path === '/' && !/[?&]variant=following/.test(location.search)) {
          // Guard against a loop if Instagram ever strips the parameter again.
          var last = 0;
          try { last = +sessionStorage.getItem('qgFollowRedirect') || 0; } catch (e) {}
          if (Date.now() - last > 5000) {
            try { sessionStorage.setItem('qgFollowRedirect', String(Date.now())); } catch (e) {}
            location.replace('/?variant=following');
            return;
          }
          log('following-only: redirect skipped, Instagram dropped the parameter again');
        }
      }

      ['pushState', 'replaceState'].forEach(function (name) {
        var original = history[name];
        history[name] = function () {
          var result = original.apply(this, arguments);
          onRoute();
          return result;
        };
      });
      window.addEventListener('popstate', onRoute);
      var lastPath = null;
      setInterval(function () {
        if (location.pathname !== lastPath) { lastPath = location.pathname; onRoute(); }
      }, 500);
      onRoute();

      // ---- 3. Feed helpers -------------------------------------------------
      function hide(el) { el.setAttribute('data-qg-hidden', '1'); }

      function collapseToWrapper(el, stopAt) {
        // Climb while the parent holds nothing but this element, so no empty box is left behind.
        while (el.parentElement && el.parentElement !== stopAt && el.parentElement.children.length === 1) {
          el = el.parentElement;
        }
        return el;
      }

      function postId(article) {
        var link = article.querySelector('a[href*="/p/"], a[href*="/reel/"]');
        if (!link) { return null; }
        var m = (link.getAttribute('href') || '').match(/\/(?:p|reel)\/([^\/?#]+)/);
        return m ? m[1] : null;
      }

      // -- Suggested posts and ads
      // Ads carry a small "Ad" or "Sponsored" label and link through Meta's ad redirect.
      var SUGGESTED = /Suggested for you|Suggested post/;
      var AD_LABEL = /^(Ad|Sponsored)$/;
      function isSuggested(article) {
        if (article.querySelector('a[href*="/ads/"], a[href*="a_mpk="], a[href*="enable_persistent_cta"]')) { return true; }
        var leaves = article.querySelectorAll('span, div');
        for (var j = 0; j < leaves.length; j++) {
          if (leaves[j].children.length === 0 && AD_LABEL.test((leaves[j].textContent || '').trim())) { return true; }
        }
        if (SUGGESTED.test(article.innerText || '')) { return true; }
        // Posts from accounts you already follow have no Follow button in the header.
        var buttons = article.querySelectorAll('button, [role="button"]');
        for (var i = 0; i < buttons.length; i++) {
          if ((buttons[i].textContent || '').trim() === 'Follow') { return true; }
        }
        return false;
      }

      // -- Seen posts, for "stop at posts I've already seen"
      function loadSeen() {
        try { return JSON.parse(localStorage.getItem('qgSeen') || '{}'); } catch (e) { return {}; }
      }
      var seenBefore = loadSeen();   // snapshot at page load: posts seen in earlier visits
      var seenNow = loadSeen();      // updated as you scroll
      var saveTimer = null;
      function saveSeen() {
        if (saveTimer) { return; }
        saveTimer = setTimeout(function () {
          saveTimer = null;
          var ids = Object.keys(seenNow).sort(function (a, b) { return seenNow[b] - seenNow[a]; }).slice(0, 3000);
          var trimmed = {};
          ids.forEach(function (id) { trimmed[id] = seenNow[id]; });
          seenNow = trimmed;
          try { localStorage.setItem('qgSeen', JSON.stringify(trimmed)); } catch (e) {}
        }, 1000);
      }
      var seenObserver = ('IntersectionObserver' in window) ? new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.5) {
            var id = postId(entry.target);
            if (id && !seenNow[id]) { seenNow[id] = Date.now(); saveSeen(); }
          }
        });
      }, { threshold: [0.5] }) : null;

      // -- Feed stop. Kept post ids are remembered, so a virtualised feed that drops
      //    old posts from the page cannot reset the count.
      var kept = {};
      var keptCount = 0;
      var cutReason = null;

      function stopCard() {
        var card = document.querySelector('.qg-stop');
        if (!card) {
          card = document.createElement('div');
          card.className = 'qg-stop';
        }
        var title = cutReason === 'seen' ? "You're caught up" : "That's " + cfg.feedCap + ' posts';
        var text = cutReason === 'seen'
          ? "You've seen everything new since your last visit."
          : 'Pull down at the top to refresh, or come back later.';
        var html = '<b>' + title + '</b><span>' + text + '</span>';
        if (card.innerHTML !== html) { card.innerHTML = html; }
        return card;
      }

      function feedLimits(articles) {
        var limiting = cfg.feedCap > 0 || cfg.stopAtSeen;
        var lastKept = null;
        var firstCut = null;
        articles.forEach(function (article) {
          if (article.getAttribute('data-qg-hidden') === '1') { return; }
          var id = postId(article);
          if (seenObserver && cfg.stopAtSeen && !article.hasAttribute('data-qg-obs')) {
            article.setAttribute('data-qg-obs', '1');
            seenObserver.observe(article);
          }
          if (!limiting) { return; }
          if (id && kept[id]) { article.removeAttribute('data-qg-cut'); lastKept = article; return; }
          if (!cutReason) {
            if (cfg.stopAtSeen && id && seenBefore[id]) { cutReason = 'seen'; log('feed: stopped at a seen post after', keptCount); }
            else if (cfg.feedCap > 0 && keptCount >= cfg.feedCap) { cutReason = 'cap'; log('feed: stopped at', keptCount, 'posts'); }
          }
          if (cutReason) {
            article.setAttribute('data-qg-cut', '1');
            if (!firstCut) { firstCut = article; }
            return;
          }
          if (id) { kept[id] = true; keptCount++; }
          article.removeAttribute('data-qg-cut');
          lastKept = article;
        });
        if (cutReason) {
          // Put the card right after the last post shown, or before the first one cut.
          // Only move it when it is out of place, so the MutationObserver settles.
          var card = stopCard();
          if (lastKept && lastKept.parentElement) {
            if (lastKept.nextSibling !== card) { lastKept.parentElement.insertBefore(card, lastKept.nextSibling); }
          } else if (firstCut && firstCut.parentElement) {
            if (firstCut.previousSibling !== card) { firstCut.parentElement.insertBefore(card, firstCut); }
          }
        }
      }

      // -- Reels inside the home feed: a post whose own link is /<user>/reel/<id>/.
      function isFeedReel(article) {
        var links = article.querySelectorAll('a[href*="/reel/"]');
        for (var i = 0; i < links.length; i++) {
          if (/\/reel\/[^\/?#]+\/?$/.test(links[i].getAttribute('href') || '')) { return true; }
        }
        return false;
      }

      // -- Likes and other counts. Instagram shows a bare number beside the heart, comment
      //    and repost buttons, and a "Liked by … and others" line that links to /liked_by/.
      var COUNT = /^[\d.,]+\s*[KkMm]?$/;
      var likesHidden = 0;
      function hideLikes(article) {
        var leaves = article.querySelectorAll('span, div');
        for (var i = 0; i < leaves.length; i++) {
          var el = leaves[i];
          if (el.children.length === 0 && el.getAttribute('data-qg-hidden') !== '1' &&
              COUNT.test((el.textContent || '').trim())) {
            hide(el);
            likesHidden++;
          }
        }
        article.querySelectorAll('a[href$="/liked_by/"]').forEach(function (link) {
          // Climb to the whole "Liked by … and others" line, stopping before the button row.
          var line = link;
          while (line.parentElement && line.parentElement !== article &&
                 !line.parentElement.querySelector('svg') &&
                 (line.parentElement.textContent || '').length < 160) {
            line = line.parentElement;
          }
          if (line.getAttribute('data-qg-hidden') !== '1') { hide(line); likesHidden++; }
        });
      }

      // -- Stories bar. Each story is labelled "Story by <name>"; the bar is the sideways
      //    scrolling strip that holds them.
      function hideStoriesBar() {
        if (document.querySelector('[data-qg-stories]')) { return; }
        var story = document.querySelector('[aria-label^="Story by"]');
        if (!story) { return; }
        var el = story.parentElement;
        while (el && el !== document.body && el.scrollWidth <= el.clientWidth + 20) { el = el.parentElement; }
        if (!el || el === document.body) { return; }
        var bar = collapseToWrapper(el, document.querySelector('main'));
        bar.setAttribute('data-qg-stories', '1');
        hide(bar);
        log('stories: bar hidden');
      }

      // ---- 4. Sweep ---------------------------------------------------------
      var suggestedHidden = 0;
      var feedReelsHidden = 0;
      function sweep() {
        addStyle();
        lockViewport();
        if (cfg.blockReels) {
          document.querySelectorAll('a[href="/reels/"]').forEach(function (a) { hide(collapseToWrapper(a)); });
        }
        var articles = Array.prototype.slice.call(document.querySelectorAll('article'));
        if (route === 'home') {
          // Checked on every sweep: a post's ad label can render after the post itself.
          articles.forEach(function (article) {
            if (article.getAttribute('data-qg-hidden') === '1') { return; }
            if (cfg.hideSuggested && isSuggested(article)) {
              hide(article);
              suggestedHidden++;
            } else if (cfg.hideFeedReels && isFeedReel(article)) {
              hide(article);
              feedReelsHidden++;
            }
          });
          feedLimits(articles);
          if (cfg.hideStories) { hideStoriesBar(); }
        }
        if (cfg.hideLikes) { articles.forEach(hideLikes); }
      }

      var pending = false;
      function scheduleSweep() {
        if (pending) { return; }
        pending = true;
        setTimeout(function () { pending = false; sweep(); }, 150);
      }

      new MutationObserver(scheduleSweep).observe(document.documentElement, { childList: true, subtree: true });
      scheduleSweep();

      // A short report for debugging, sent a few seconds after each page load.
      setTimeout(function () {
        log('report path=' + location.pathname + location.search,
            'articles=' + document.querySelectorAll('article').length,
            'suggestedHidden=' + suggestedHidden,
            'feedReelsHidden=' + feedReelsHidden,
            'likesHidden=' + likesHidden,
            'kept=' + keptCount, 'cut=' + (cutReason || 'none'),
            'stories=' + (document.querySelector('[data-qg-stories]') ? 'hidden' : 'not found'));
      }, 6000);
    })();
    """#
}
