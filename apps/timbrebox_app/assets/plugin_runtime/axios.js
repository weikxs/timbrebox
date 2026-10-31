// An axios-compatible HTTP client for plugins. Requests go through the host
// (__hostHttp), which applies the egress policy; this file only shapes them
// the way axios does: instances and defaults, interceptors, the method
// shorthands, JSON bodies, validateStatus and axios-style errors.
(function (global) {
  'use strict';

  var METHODS_WITHOUT_BODY = ['get', 'delete', 'head', 'options'];
  var METHODS_WITH_BODY = ['post', 'put', 'patch'];
  var MAX_TIMEOUT_MS = 20000;

  function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value) &&
      !(global.URLSearchParams && value instanceof global.URLSearchParams);
  }

  function copyInto(target, source) {
    if (!isPlainObject(source)) return target;
    for (var key in source) {
      if (!Object.prototype.hasOwnProperty.call(source, key)) continue;
      var value = source[key];
      target[key] = isPlainObject(value) ? copyInto(isPlainObject(target[key]) ? target[key] : {}, value) : value;
    }
    return target;
  }

  // A new config: [base] deep-copied, then [override] on top.
  function mergeConfig(base, override) {
    return copyInto(copyInto({}, base), override);
  }

  function defaultHeaders() {
    var headers = { common: { Accept: 'application/json, text/plain, */*' } };
    METHODS_WITHOUT_BODY.concat(METHODS_WITH_BODY).forEach(function (m) { headers[m] = {}; });
    return headers;
  }

  // The headers sent: defaults.common, then defaults[method], then the
  // request's own; later names win regardless of letter case.
  function flattenHeaders(headers, method) {
    var out = {};
    function put(source) {
      if (!isPlainObject(source)) return;
      for (var name in source) {
        if (!Object.prototype.hasOwnProperty.call(source, name)) continue;
        var value = source[name];
        if (isPlainObject(value) || value === undefined) continue;
        for (var existing in out) {
          if (existing.toLowerCase() === name.toLowerCase()) delete out[existing];
        }
        if (value !== null && value !== false) out[name] = String(value);
      }
    }
    if (isPlainObject(headers)) {
      put(headers.common);
      put(headers[method]);
      put(headers);
    }
    return out;
  }

  function hasHeader(headers, name) {
    for (var key in headers) if (key.toLowerCase() === name) return true;
    return false;
  }

  function isAbsolute(url) {
    return /^([a-z][a-z\d+\-.]*:)?\/\//i.test(url);
  }

  function fullUrl(config) {
    var url = config.url || '';
    if (!config.baseURL || isAbsolute(url)) return url;
    return config.baseURL.replace(/\/+$/, '') + (url ? '/' + url.replace(/^\/+/, '') : '');
  }

  function paramsObject(params) {
    if (!params) return null;
    var out = {};
    if (global.URLSearchParams && params instanceof global.URLSearchParams) {
      params.forEach(function (value, key) { out[key] = value; });
      return out;
    }
    for (var key in params) {
      if (!Object.prototype.hasOwnProperty.call(params, key)) continue;
      var value = params[key];
      if (value === undefined || value === null) continue;
      out[key] = value instanceof Date ? value.toISOString()
        : typeof value === 'object' ? JSON.stringify(value) : String(value);
    }
    return out;
  }

  function serializeBody(data, headers) {
    if (data === undefined || data === null) return null;
    if (typeof data === 'string') return data;
    if (global.URLSearchParams && data instanceof global.URLSearchParams) {
      if (!hasHeader(headers, 'content-type')) headers['Content-Type'] = 'application/x-www-form-urlencoded;charset=utf-8';
      return data.toString();
    }
    if (!hasHeader(headers, 'content-type')) headers['Content-Type'] = 'application/json;charset=utf-8';
    return JSON.stringify(data);
  }

  function parseBody(text, config) {
    var type = config.responseType;
    if (type === 'text' || type === 'arraybuffer' || type === 'blob' || typeof text !== 'string') return text;
    try {
      return JSON.parse(text);
    } catch (e) {
      return text;
    }
  }

  function applyTransforms(transforms, data, headers) {
    if (!transforms) return data;
    var list = Array.isArray(transforms) ? transforms : [transforms];
    for (var i = 0; i < list.length; i++) {
      if (typeof list[i] === 'function') data = list[i](data, headers);
    }
    return data;
  }

  function AxiosError(message, code, config, response) {
    var error = new Error(message);
    error.name = 'AxiosError';
    error.code = code;
    error.config = config;
    error.request = {};
    if (response) {
      error.response = response;
      error.status = response.status;
    }
    error.isAxiosError = true;
    error.toJSON = function () {
      return { message: message, name: 'AxiosError', code: code, status: error.status };
    };
    return error;
  }

  function dispatch(config) {
    var method = (config.method || 'get').toLowerCase();
    var headers = flattenHeaders(config.headers, method);
    var body = METHODS_WITHOUT_BODY.indexOf(method) === -1
      ? serializeBody(applyTransforms(config.transformRequest, config.data, headers), headers)
      : null;
    var timeout = Number(config.timeout) > 0 ? Math.min(Number(config.timeout), MAX_TIMEOUT_MS) : 0;
    return global.__hostHttp({
      url: fullUrl(config),
      method: method.toUpperCase(),
      headers: headers,
      params: paramsObject(config.params),
      data: body,
      timeout: timeout
    }).then(function (raw) {
      var response = {
        data: applyTransforms(config.transformResponse, parseBody(raw.data, config), raw.headers),
        status: raw.status,
        statusText: raw.statusText || '',
        headers: raw.headers || {},
        config: config,
        request: { responseURL: raw.url || fullUrl(config) }
      };
      // validateStatus: null accepts every status, as in axios.
      var validate = config.validateStatus;
      if (validate === null || (validate || defaultValidateStatus)(response.status)) return response;
      throw AxiosError(
        'Request failed with status code ' + response.status,
        response.status >= 500 ? 'ERR_BAD_RESPONSE' : 'ERR_BAD_REQUEST',
        config,
        response
      );
    }, function (failure) {
      if (failure && failure.code === 'timeout') {
        throw AxiosError('timeout of ' + timeout + 'ms exceeded', 'ECONNABORTED', config);
      }
      if (failure && failure.code === 'cancelled') {
        var cancelled = AxiosError('canceled', 'ERR_CANCELED', config);
        cancelled.__CANCEL__ = true;
        throw cancelled;
      }
      throw AxiosError((failure && failure.message) || 'Network Error', 'ERR_NETWORK', config);
    });
  }

  function defaultValidateStatus(status) {
    return status >= 200 && status < 300;
  }

  function InterceptorManager() {
    this.handlers = [];
  }
  InterceptorManager.prototype.use = function (fulfilled, rejected) {
    this.handlers.push({ fulfilled: fulfilled, rejected: rejected });
    return this.handlers.length - 1;
  };
  InterceptorManager.prototype.eject = function (id) {
    if (this.handlers[id]) this.handlers[id] = null;
  };
  InterceptorManager.prototype.clear = function () {
    this.handlers = [];
  };
  InterceptorManager.prototype.forEach = function (fn) {
    this.handlers.forEach(function (h) { if (h) fn(h); });
  };

  function create(instanceDefaults) {
    var defaults = mergeConfig({ headers: defaultHeaders(), timeout: 0 }, instanceDefaults);
    var interceptors = { request: new InterceptorManager(), response: new InterceptorManager() };

    function request(configOrUrl, maybeConfig) {
      var own = typeof configOrUrl === 'string'
        ? mergeConfig(maybeConfig || {}, { url: configOrUrl })
        : configOrUrl || {};
      var config = mergeConfig(instance.defaults, own);
      // As in axios: request interceptors run last-added first, response
      // interceptors in the order they were added.
      var chain = [];
      interceptors.request.forEach(function (h) { chain.unshift(h); });
      chain.push({ fulfilled: dispatch, rejected: undefined });
      interceptors.response.forEach(function (h) { chain.push(h); });
      var promise = Promise.resolve(config);
      chain.forEach(function (h) { promise = promise.then(h.fulfilled, h.rejected); });
      return promise;
    }

    function instance(configOrUrl, maybeConfig) {
      return request(configOrUrl, maybeConfig);
    }
    instance.defaults = defaults;
    instance.interceptors = interceptors;
    instance.request = request;
    METHODS_WITHOUT_BODY.forEach(function (method) {
      instance[method] = function (url, config) {
        return request(mergeConfig(config || {}, { url: url, method: method }));
      };
    });
    METHODS_WITH_BODY.forEach(function (method) {
      instance[method] = function (url, data, config) {
        var merged = mergeConfig(config || {}, { url: url, method: method });
        merged.data = data;
        return request(merged);
      };
    });
    instance.getUri = function (config) {
      return fullUrl(mergeConfig(instance.defaults, config || {}));
    };
    instance.create = function (more) {
      return create(mergeConfig(instance.defaults, more || {}));
    };
    return instance;
  }

  var axios = create({});
  axios.AxiosError = AxiosError;
  axios.isAxiosError = function (value) { return !!(value && value.isAxiosError); };
  axios.isCancel = function (value) { return !!(value && value.__CANCEL__); };
  axios.all = function (promises) { return Promise.all(promises); };
  axios.spread = function (callback) { return function (args) { return callback.apply(null, args); }; };
  axios.default = axios;
  global.axios = axios;
})(globalThis);
