'use strict';

// Fixed read-only capture for the opt-in official guest search, not a script API.
(() => {
  const config = window.TimbreBoxGuestSearchConfig;
  const api = window.TimbreBoxGuestSearchParser;
  if (!config || !api) return;
  const collector = new api.SearchResultCollector(config.platform, config.query);
  const host = config.platform === 'tiktok' ? 'www.tiktok.com' : 'www.douyin.com';
  const paths = config.platform === 'tiktok'
    ? /^\/api\/search\/(?:general|item)\/full\/?$/
    : /^\/aweme\/v1\/web\/(?:general\/search\/single|search\/item)\/?$/;
  const seen = new Set(config.seenIds);
  const items = [];
  let stopped = false, cursor = 0, pages = 0, excludedCount = 0, isEnd = false;
  let pendingScroll = false, lastError = null, sourceStatus = null;
  let diagnostic = { phase: 'waiting', bytes: 0 };
  Object.defineProperty(window, 'TimbreBoxGuestSearchState', { get: () => ({ stopped, pages, cursor, items: items.length, lastError, sourceStatus, diagnostic }) });
  function send(value) {
    window.webkit.messageHandlers.timbreboxGuestSearch.postMessage({ jobId: config.jobId, ...value });
  }
  function complete() {
    stopped = true;
    send({ data: items, isEnd, excludedCount, pageCount: pages });
  }
  // Called only by the fixed host deadline. Never turn an empty observation or
  // a failed subsequent response into successful partial search results.
  Object.defineProperty(window, 'TimbreBoxGuestSearchFinish', { value: () => {
    if (stopped || lastError || pages === 0 || items.length === 0) return false;
    complete();
    return true;
  } });
  function scroll() {
    if (stopped || pendingScroll || lastError) return;
    pendingScroll = true;
    setTimeout(() => {
      pendingScroll = false;
      if (stopped || lastError) return;
      window.scrollTo(0, document.body?.scrollHeight || 0);
      for (const element of Array.from(document.querySelectorAll('main,main *,[data-e2e="search-page"]')).slice(0, 1500)) {
        if (element.clientHeight > 100 && element.scrollHeight > element.clientHeight + 10) element.scrollTop = element.scrollHeight;
      }
    }, 650);
  }
  function matches(address) {
    try {
      const u = new URL(address, location.href);
      const keyword = u.searchParams.get('keyword') ?? u.searchParams.get('q') ?? u.searchParams.get('search_keyword');
      return u.protocol === 'https:' && u.host === host && paths.test(u.pathname) && keyword === config.query;
    } catch { return false; }
  }
  function record(address, payload) {
    if (stopped || !matches(address)) return;
    try {
      const u = new URL(address, location.href);
      const requested = Number(u.searchParams.get('cursor') || 0);
      if (requested < cursor) return; // A repeated old response is not a new page.
      sourceStatus = typeof payload?.status_code === 'number' ? payload.status_code : null;
      const rows = payload?.item_list ?? payload?.data;
      diagnostic = { phase: 'protocol', sourceStatus, rows: Array.isArray(rows) ? rows.length : -1,
        cursor: Number.isFinite(Number(payload?.cursor)) ? Number(payload.cursor) : -1,
        hasMore: typeof payload?.has_more === 'boolean' || typeof payload?.has_more === 'number' ? payload.has_more : -1 };
      const page = collector.append(payload, u.href);
      lastError = null;
      cursor = page.nextCursor;
      isEnd = page.isEnd;
      pages++;
      excludedCount += page.excludedCount;
      for (const item of page.data) {
        if (!seen.has(item.id) && items.length < Math.min(50 - config.seenIds.length, Math.max(config.wanted, 12))) { seen.add(item.id); items.push(item); }
      }
      if (items.length >= config.wanted || page.isEnd || pages >= 5) {
        complete();
      } else {
        scroll();
      }
    } catch (error) {
      // The official frontend may initialize its own anonymous session and
      // naturally issue another request. Do not create requests or identities
      // ourselves, and never convert a refusal into empty success.
      if (error.code === 'search_access_required') { lastError = error.code; return; }
      stopped = true;
      const allowed = new Set(['search_access_required', 'search_request_mismatch', 'invalid_search_response', 'search_limit_reached']);
      send({ errorCode: allowed.has(error.code) ? error.code : 'invalid_search_response', diagnostic });
    }
  }
  async function capture(response, address) {
    if (stopped || !matches(address)) return;
    const reader = response.clone().body?.getReader();
    if (!reader) return;
    const chunks = []; let size = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 2 * 1024 * 1024) { diagnostic = { phase: 'oversize', bytes: size }; void reader.cancel(); throw new Error('oversize'); }
        chunks.push(value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      diagnostic = { phase: 'json', bytes: size };
      record(address, JSON.parse(new TextDecoder().decode(bytes)));
    } catch {
      if (!stopped) {
        lastError = 'invalid_search_response';
        if (diagnostic.phase === 'oversize') { stopped = true; send({ errorCode: lastError, diagnostic }); }
      }
    } finally { reader.releaseLock(); }
  }
  const originalFetch = window.fetch;
  window.fetch = async function(...args) {
    const response = await originalFetch.apply(this, args);
    const address = typeof args[0] === 'string' ? args[0] : args[0]?.url;
    void capture(response, address);
    return response;
  };
  const addressKey = Symbol('guestSearchAddress');
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, address, ...args) {
    this[addressKey] = address;
    return originalOpen.call(this, method, address, ...args);
  };
  const originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function(...args) {
    this.addEventListener('load', () => {
      if (!matches(this[addressKey]) || stopped) return;
      try {
        const raw = this.responseType === 'json' ? this.response : this.responseText;
        if (typeof raw === 'string' && raw.length > 2 * 1024 * 1024) throw new Error('oversize');
        record(this[addressKey], typeof raw === 'string' ? JSON.parse(raw) : raw);
      } catch {
        lastError = 'invalid_search_response';
      }
    });
    return originalSend.apply(this, args);
  };
  // Some layouts do not trigger infinite scroll until the document settles.
  const retry = setInterval(() => { if (stopped) clearInterval(retry); else if (pages > 0) scroll(); }, 1200);
})();
