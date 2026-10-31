// Runs first in every plugin engine. It closes the engine's own network APIs,
// wires the host HTTP and fixed media bridges, and defines the globals plugins expect:
// console, env, process, require. The host replaces __ENV__,
// __MSG_NOT_LOADED__ and __MSG_NOT_ALLOWED__ with JS literals before running
// it. url.js and axios.js are evaluated right after.

// HTTP must go through __hostHttp, never a built-in network API.
delete globalThis.fetch;
delete globalThis.XMLHttpRequest;

var console = (function () {
  function log() {
    sendMessage('__log', Array.prototype.map.call(arguments, function (a) {
      if (typeof a === 'string') return a;
      try { return JSON.stringify(a); } catch (e) { return String(a); }
    }).join(' '));
  }
  return { log: log, info: log, warn: log, error: log, debug: log };
})();

// The host bridge: a request leaves through sendMessage and its promise is
// settled later by the host calling __resolveHost.
(function () {
  var pending = {};
  var nextId = 0;
  globalThis.__hostHttp = function (request) {
    return new Promise(function (resolve, reject) {
      var id = ++nextId;
      pending[id] = { resolve: resolve, reject: reject };
      sendMessage('__hostHttp', JSON.stringify({
        id: id,
        url: request.url,
        method: request.method || 'GET',
        headers: request.headers || {},
        params: request.params || null,
        data: request.data != null ? request.data : null,
        timeout: request.timeout || 0
      }));
    });
  };
  globalThis.__hostMedia = function (request) {
    return new Promise(function (resolve, reject) {
      var id = ++nextId;
      pending[id] = { resolve: resolve, reject: reject };
      sendMessage('__hostMedia', JSON.stringify({
        id: id, operation: request.operation, platform: request.platform,
        query: request.query, page: request.page, item: request.item, url: request.url
      }));
    });
  };
  globalThis.__resolveHost = function (id, ok, payload) {
    var p = pending[id];
    if (!p) return;
    delete pending[id];
    if (ok) {
      p.resolve(payload);
    } else {
      var error = new Error((payload && payload.message) || 'request failed');
      error.code = payload && payload.code;
      p.reject(error);
    }
  };
})();

// What the app tells a plugin about where it runs. Read-only; each
// getUserVariables() call returns a fresh copy.
var env = (function (described) {
  var variables = JSON.stringify(described.userVariables || {});
  return Object.freeze({
    appVersion: described.appVersion,
    os: described.os,
    lang: described.lang,
    getUserVariables: function () { return JSON.parse(variables); },
    media: Object.freeze({
      source: function (platform) { return __mediaSource(platform); },
      search: function (platform, query, page) {
        return __hostMedia({ operation: 'search', platform: platform, query: query, page: page });
      },
      resolve: function (platform, itemOrUrl) {
        return __hostMedia({ operation: 'resolve', platform: platform,
          item: typeof itemOrUrl === 'string' ? undefined : itemOrUrl,
          url: typeof itemOrUrl === 'string' ? itemOrUrl : undefined });
      }
    })
  });
})(__ENV__);

// Shared adapter so platform plugins only declare metadata, not four copies of
// search/link/resolve logic. The host still validates every operation and URL.
function __mediaSource(platform) {
  var hosts = {
    youtube: ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be'],
    bilibili: ['bilibili.com', 'www.bilibili.com', 'm.bilibili.com', 'b23.tv'],
    douyin: ['douyin.com', 'www.douyin.com', 'v.douyin.com', 'www.iesdouyin.com'],
    tiktok: ['tiktok.com', 'www.tiktok.com', 'm.tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com']
  };
  if (!Object.prototype.hasOwnProperty.call(hosts, platform)) throw new Error('Unsupported media platform');
  async function importItem(link) {
    return (await env.media.resolve(platform, link)).item;
  }
  return {
    search: async function (query, page, type) {
      if (type !== 'music') return { isEnd: true, data: [] };
      var link = String(query).match(/https?:\/\/[^\s<>"'，。！？；（）【】]+/i);
      if (link) {
        var url;
        try { url = new URL(link[0]); } catch (e) { return { isEnd: true, data: [] }; }
        if (hosts[platform].indexOf(url.hostname.toLowerCase()) < 0 || page !== 1) return { isEnd: true, data: [] };
        return { isEnd: true, data: [await importItem(query)] };
      }
      return env.media.search(platform, query, page);
    },
    getMediaSource: async function (item, quality) {
      if (quality !== 'standard') return null;
      return (await env.media.resolve(platform, item)).media;
    },
    importMusicItem: importItem
  };
}

var process = Object.freeze({ platform: env.os, version: env.appVersion, env: env });

// Only the libraries a plugin names are evaluated (see PluginShims).
function __shim(name, lib) {
  if (lib === undefined) throw new Error(__MSG_NOT_LOADED__ + name);
  return lib;
}
function require(name) {
  switch (name) {
    case 'axios': return globalThis.axios;
    case 'crypto-js': return __shim(name, globalThis.__lib_cryptojs);
    case 'he': return __shim(name, globalThis.__lib_he);
    case 'dayjs': return __shim(name, globalThis.__lib_dayjs);
    case 'qs': return __shim(name, globalThis.__lib_qs);
    case 'cheerio': return __shim(name, globalThis.__lib_cheerio);
    case 'big-integer': return __shim(name, globalThis.__lib_bigint);
    default: throw new Error(__MSG_NOT_ALLOWED__ + name);
  }
}
// The plugin object a module exported: module.exports, or its `default`
// when the plugin was compiled from an ES module (`exports.default = …`).
function __exportOf(module) {
  var exported = module.exports;
  var fallback = exported && exported.default;
  if (fallback && (typeof fallback === 'object' || typeof fallback === 'function') &&
      exported.platform === undefined) {
    return fallback;
  }
  return exported;
}
