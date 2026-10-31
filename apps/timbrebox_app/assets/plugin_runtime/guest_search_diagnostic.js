// Fixed host deadline snapshot: counters and states only, never page text/URLs.
(() => {
  const body = document.body?.innerText || '';
  const videoLinks = document.querySelectorAll('a[href*="/video/"]').length;
  const shell = videoLinks === 0 && body.trim().length <= 200;
  const challengeShell = shell && /验证中|安全验证|完成验证|人机验证|验证码|security check|verify you are human|captcha|verification required|checking your browser/i.test(body + ' ' + (document.title || ''));
  const needsLogin = shell && /请先登录|登录后|需要登录|log in to|sign in to/i.test(body);
  return {
    flushed: window.TimbreBoxGuestSearchFinish?.() === true,
    needsAction: challengeShell || needsLogin,
    challengeShell,
    parser: !!window.TimbreBoxGuestSearchParser,
    config: !!window.TimbreBoxGuestSearchConfig,
    capture: window.TimbreBoxGuestSearchState || null,
    hidden: document.hidden,
    readyState: document.readyState,
    bodyChars: body.length,
    htmlBytes: (document.documentElement?.outerHTML || '').length,
    scripts: document.scripts.length,
    videoLinks,
  };
})();
