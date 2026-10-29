// Runs first in every plugin engine. It closes the engine's own network APIs,
// wires the host HTTP bridge, and defines the globals plugins expect:
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
    getUserVariables: function () { return JSON.parse(variables); }
  });
})(__ENV__);

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
// The name some plugin builds call require by.
var __plugin_require = require;

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
