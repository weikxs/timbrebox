'use strict';

// Original shared parser: Node protocol tests and the opt-in native guest page.
(() => {
  const fail = (code, message) => { throw Object.assign(new Error(message), { code }); };
  const specs = {
    tiktok: { host: 'www.tiktok.com', path: /^\/api\/search\/(?:general|item)\/full\/?$/, milliseconds: false },
    douyin: { host: 'www.douyin.com', path: /^\/aweme\/v1\/web\/(?:general\/search\/single|search\/item)\/?$/, milliseconds: true },
  };
  const restrictedKeys = [
    'is_paid', 'isPaid', 'is_pay', 'isPay', 'is_vip', 'isVip', 'subscriber_only',
    'is_preview', 'isPreview', 'is_trial', 'isTrial', 'privateItem', 'secret',
    'is_private', 'isPrivate', 'isProhibited', 'is_prohibited', 'takeDown', 'forFriend',
  ];
  const text = (v, n) => typeof v === 'string' ? v.trim().slice(0, n) : '';
  const object = v => v && typeof v === 'object' && !Array.isArray(v);
  const yes = v => v === true || v === 1 || v === '1';
  function integer(v) {
    if (typeof v === 'string' && !/^\d+$/.test(v)) return null;
    if (typeof v !== 'string' && typeof v !== 'number') return null;
    const n = Number(v);
    return Number.isSafeInteger(n) && n >= 0 && n <= 1000000 ? n : null;
  }
  function restricted(item) {
    return [item, item.video, item.status].filter(object).some(node => restrictedKeys.some(k => yes(node[k])));
  }
  function summary(platform, item) {
    const id = platform === 'tiktok' ? item.id : item.aweme_id;
    if (typeof id !== 'string' || !/^\d{10,25}$/.test(id)) return null;
    const title = text(item.desc, 2000), author = item.author, duration = item.video?.duration;
    if (!title || !object(author) || !Number.isFinite(duration) || duration <= 0) return null;
    const handle = text(author.uniqueId, 40);
    if (platform === 'tiktok' && !/^[A-Za-z0-9_.-]{1,40}$/.test(handle)) return null;
    const artist = text(author.nickname, 200) || handle;
    if (!artist) return null;
    return {
      id, title, artist, duration: specs[platform].milliseconds ? duration / 1000 : duration,
      url: platform === 'tiktok' ? `https://www.tiktok.com/@${handle}/video/${id}` : `https://www.douyin.com/video/${id}`,
      contentKind: 'video_audio', access: 'unverified',
    };
  }
  function parseSearchResponse(platform, payload, { requestUrl, query, cursor = 0 } = {}) {
    const spec = specs[platform];
    if (!spec) fail('invalid_search_request', 'Unsupported search platform.');
    if (typeof query !== 'string' || !query.trim() || query.length > 200 || /[\x00-\x1f]/.test(query)) {
      fail('invalid_search_request', 'A valid keyword is required.');
    }
    let url;
    try { url = new URL(requestUrl); } catch { fail('invalid_search_request', 'An official search request is required.'); }
    const keyword = url.searchParams.get('keyword') ?? url.searchParams.get('q') ?? url.searchParams.get('search_keyword');
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hostname !== spec.host || !spec.path.test(url.pathname)
      || keyword !== query.trim() || integer(cursor) === null || integer(url.searchParams.get('cursor') ?? '0') !== cursor) {
      fail('search_request_mismatch', 'The response does not belong to the requested keyword and cursor.');
    }
    if (!object(payload) || typeof payload.status_code !== 'number') fail('invalid_search_response', 'The platform search response is invalid.');
    if (payload.status_code !== 0) fail('search_access_required', 'The official search request was refused or requires user verification.');
    const rows = payload.item_list ?? payload.data, more = payload.has_more, nextCursor = integer(payload.cursor);
    if (!Array.isArray(rows) || rows.length > 200 || ![true, false, 0, 1].includes(more) || nextCursor === null
      || (yes(more) && nextCursor <= cursor)) fail('invalid_search_response', 'The platform search pagination is invalid.');
    const items = [], ids = new Set();
    let excludedCount = 0, videoRows = 0;
    for (const row of rows) {
      if (!object(row)) continue;
      const item = platform === 'tiktok' ? (row.item ?? row) : row.aweme_info;
      if (!object(item) || !object(item.video)) continue;
      videoRows++;
      if (restricted(item)) { excludedCount++; continue; }
      const value = summary(platform, item);
      if (value && !ids.has(value.id)) { ids.add(value.id); items.push(value); }
    }
    if ((videoRows > 0 && !items.length && !excludedCount) || (rows.length > 0 && !videoRows && yes(more))) {
      fail('invalid_search_response', 'The search response contains no interpretable video results.');
    }
    return { data: items, isEnd: !yes(more), nextCursor, excludedCount };
  }
  class SearchResultCollector {
    #platform; #query; #cursor = 0; #ended = false; #ids = new Set();
    constructor(platform, query) { this.#platform = platform; this.#query = query; }
    append(payload, requestUrl) {
      if (this.#ended) fail('search_already_ended', 'This search has ended.');
      const page = parseSearchResponse(this.#platform, payload, { requestUrl, query: this.#query, cursor: this.#cursor });
      const data = page.data.filter(item => !this.#ids.has(item.id));
      if (this.#ids.size + data.length > 500) fail('search_limit_reached', 'The search result limit was reached.');
      for (const item of data) this.#ids.add(item.id);
      this.#cursor = page.nextCursor; this.#ended = page.isEnd;
      return { ...page, data };
    }
  }
  const api = Object.freeze({ parseSearchResponse, SearchResultCollector });
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') Object.defineProperty(window, 'TimbreBoxGuestSearchParser', { value: api });
})();
