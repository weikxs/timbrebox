// URL and URLSearchParams for plugins. The engines TimbreBox embeds have
// neither; plugins written for browsers or React Native use both. This covers
// what plugins need from them: parsing and building http(s) URLs, resolving a
// relative URL against a base (RFC 3986, section 5) and reading and writing
// the query. Hosts are taken as written, without IDNA conversion.
(function (global) {
  'use strict';

  var DEFAULT_PORTS = { 'http:': '80', 'https:': '443', 'ws:': '80', 'wss:': '443', 'ftp:': '21' };
  var HIERARCHICAL = { 'http:': true, 'https:': true, 'ws:': true, 'wss:': true, 'ftp:': true, 'file:': true };

  // Characters left as they are in a path or query; everything else is
  // percent-encoded as UTF-8. An existing %XX escape is kept.
  function encodePart(text, keep) {
    var out = '';
    for (var i = 0; i < text.length; i++) {
      var c = text.charAt(i);
      if (c === '%' && /^[0-9A-Fa-f]{2}$/.test(text.substr(i + 1, 2))) {
        out += c;
      } else if (keep.test(c)) {
        out += c;
      } else {
        var code = text.charCodeAt(i);
        if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
          c += text.charAt(++i);
        }
        out += encodeURIComponent(c);
      }
    }
    return out;
  }
  var PATH_KEEP = /[A-Za-z0-9\-._~!$&'()*+,;=:@\/]/;
  var QUERY_KEEP = /[A-Za-z0-9\-._~!$&'()*+,;=:@\/?]/;

  // application/x-www-form-urlencoded: only * - . _ and alphanumerics stay,
  // a space becomes '+'.
  function formEncode(text) {
    return encodeURIComponent(String(text))
      .replace(/[!'()~]/g, function (c) {
        return '%' + c.charCodeAt(0).toString(16).toUpperCase();
      })
      .replace(/%20/g, '+');
  }

  function formDecode(text) {
    var spaced = text.replace(/\+/g, ' ');
    try {
      return decodeURIComponent(spaced);
    } catch (e) {
      return spaced;
    }
  }

  function removeDotSegments(path) {
    var input = path.split('/');
    var output = [];
    for (var i = 0; i < input.length; i++) {
      var segment = input[i];
      if (segment === '..') {
        if (output.length > 1) output.pop();
        if (i === input.length - 1) output.push('');
      } else if (segment === '.') {
        if (i === input.length - 1) output.push('');
      } else {
        output.push(segment);
      }
    }
    var joined = output.join('/');
    return joined.charAt(0) === '/' ? joined : '/' + joined;
  }

  // { scheme, authority, path, query, fragment } of an absolute or relative
  // reference (RFC 3986, appendix B); undefined parts are absent.
  function split(text) {
    var m = /^(?:([A-Za-z][A-Za-z0-9+.\-]*):)?(?:\/\/([^\/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/.exec(text);
    return {
      scheme: m[1] === undefined ? undefined : m[1].toLowerCase() + ':',
      authority: m[2],
      path: m[3],
      query: m[4],
      fragment: m[5]
    };
  }

  function parseAuthority(authority) {
    var at = authority.lastIndexOf('@');
    var userinfo = at === -1 ? '' : authority.slice(0, at);
    var hostport = at === -1 ? authority : authority.slice(at + 1);
    var colon = userinfo.indexOf(':');
    var hostMatch = /^(\[[^\]]*\]|[^:]*)(?::(\d*))?$/.exec(hostport);
    if (!hostMatch) return null;
    return {
      username: colon === -1 ? userinfo : userinfo.slice(0, colon),
      password: colon === -1 ? '' : userinfo.slice(colon + 1),
      hostname: hostMatch[1].toLowerCase(),
      port: hostMatch[2] || ''
    };
  }

  function invalid(text) {
    return new TypeError('Invalid URL: ' + text);
  }

  // Resolves [ref] against [base] (both split) into absolute parts.
  function resolve(ref, base) {
    if (ref.scheme !== undefined) return ref;
    if (!base) return null;
    var out = { scheme: base.scheme };
    if (ref.authority !== undefined) {
      out.authority = ref.authority;
      out.path = ref.path;
      out.query = ref.query;
    } else {
      out.authority = base.authority;
      if (ref.path === '') {
        out.path = base.path;
        out.query = ref.query !== undefined ? ref.query : base.query;
      } else {
        if (ref.path.charAt(0) === '/') {
          out.path = ref.path;
        } else {
          var basePath = base.path || '/';
          out.path = basePath.slice(0, basePath.lastIndexOf('/') + 1) + ref.path;
        }
        out.query = ref.query;
      }
    }
    out.fragment = ref.fragment;
    return out;
  }

  function URLSearchParams(init) {
    if (!(this instanceof URLSearchParams)) throw new TypeError("Constructor URLSearchParams requires 'new'");
    this._pairs = [];
    this._owner = null;
    if (init == null) return;
    if (typeof init === 'string') {
      this._parse(init);
    } else if (init instanceof URLSearchParams) {
      this._pairs = init._pairs.slice();
    } else if (Array.isArray(init)) {
      for (var i = 0; i < init.length; i++) this._pairs.push([String(init[i][0]), String(init[i][1])]);
    } else if (typeof init === 'object') {
      for (var key in init) {
        if (Object.prototype.hasOwnProperty.call(init, key)) this._pairs.push([key, String(init[key])]);
      }
    }
  }

  URLSearchParams.prototype = {
    _parse: function (text) {
      this._pairs = [];
      var query = text.charAt(0) === '?' ? text.slice(1) : text;
      if (query === '') return;
      var parts = query.split('&');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i] === '') continue;
        var eq = parts[i].indexOf('=');
        var name = eq === -1 ? parts[i] : parts[i].slice(0, eq);
        var value = eq === -1 ? '' : parts[i].slice(eq + 1);
        this._pairs.push([formDecode(name), formDecode(value)]);
      }
    },
    _changed: function () {
      if (this._owner) this._owner._query = this._pairs.length ? this.toString() : undefined;
    },
    append: function (name, value) {
      this._pairs.push([String(name), String(value)]);
      this._changed();
    },
    delete: function (name) {
      name = String(name);
      this._pairs = this._pairs.filter(function (p) { return p[0] !== name; });
      this._changed();
    },
    get: function (name) {
      for (var i = 0; i < this._pairs.length; i++) if (this._pairs[i][0] === String(name)) return this._pairs[i][1];
      return null;
    },
    getAll: function (name) {
      return this._pairs.filter(function (p) { return p[0] === String(name); }).map(function (p) { return p[1]; });
    },
    has: function (name) {
      return this.get(name) !== null;
    },
    set: function (name, value) {
      name = String(name);
      var found = false;
      var kept = [];
      for (var i = 0; i < this._pairs.length; i++) {
        if (this._pairs[i][0] !== name) {
          kept.push(this._pairs[i]);
        } else if (!found) {
          kept.push([name, String(value)]);
          found = true;
        }
      }
      if (!found) kept.push([name, String(value)]);
      this._pairs = kept;
      this._changed();
    },
    sort: function () {
      this._pairs.sort(function (a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0; });
      this._changed();
    },
    forEach: function (callback, thisArg) {
      for (var i = 0; i < this._pairs.length; i++) callback.call(thisArg, this._pairs[i][1], this._pairs[i][0], this);
    },
    keys: function () { return this._pairs.map(function (p) { return p[0]; })[Symbol.iterator](); },
    values: function () { return this._pairs.map(function (p) { return p[1]; })[Symbol.iterator](); },
    entries: function () { return this._pairs.map(function (p) { return [p[0], p[1]]; })[Symbol.iterator](); },
    toString: function () {
      return this._pairs.map(function (p) { return formEncode(p[0]) + '=' + formEncode(p[1]); }).join('&');
    }
  };
  URLSearchParams.prototype[Symbol.iterator] = URLSearchParams.prototype.entries;
  Object.defineProperty(URLSearchParams.prototype, 'size', { get: function () { return this._pairs.length; } });

  function URL(url, base) {
    if (!(this instanceof URL)) throw new TypeError("Constructor URL requires 'new'");
    var text = String(url).trim();
    var baseParts;
    if (base !== undefined) {
      baseParts = split(String(base instanceof URL ? base.href : base).trim());
      if (baseParts.scheme === undefined) throw invalid(base);
    }
    var parts = resolve(split(text), baseParts);
    if (!parts || parts.scheme === undefined) throw invalid(text);
    this._scheme = parts.scheme;
    this._query = parts.query;
    this._fragment = parts.fragment;
    if (HIERARCHICAL[this._scheme]) {
      if (parts.authority === undefined || (parts.authority === '' && this._scheme !== 'file:')) throw invalid(text);
      var authority = parseAuthority(parts.authority);
      if (!authority) throw invalid(text);
      this._username = authority.username;
      this._password = authority.password;
      this._hostname = authority.hostname;
      this._port = authority.port === DEFAULT_PORTS[this._scheme] ? '' : authority.port;
      this._path = encodePart(removeDotSegments(parts.path === '' ? '/' : parts.path), PATH_KEEP);
    } else {
      this._username = this._password = this._hostname = this._port = '';
      this._path = parts.path;
    }
    if (this._query !== undefined) this._query = encodePart(this._query, QUERY_KEEP);
    this._params = new URLSearchParams(this._query || '');
    this._params._owner = this;
  }

  function prop(name, get, set) {
    Object.defineProperty(URL.prototype, name, { get: get, set: set, enumerable: true });
  }

  prop('protocol', function () { return this._scheme; });
  prop('username', function () { return this._username; });
  prop('password', function () { return this._password; });
  prop('hostname', function () { return this._hostname; });
  prop('port', function () { return this._port; });
  prop('host', function () { return this._hostname + (this._port ? ':' + this._port : ''); });
  prop('origin', function () {
    return HIERARCHICAL[this._scheme] && this._scheme !== 'file:' ? this._scheme + '//' + this.host : 'null';
  });
  prop('pathname', function () { return this._path; }, function (value) {
    this._path = encodePart(removeDotSegments(String(value)), PATH_KEEP);
  });
  prop('search', function () { return this._query ? '?' + this._query : ''; }, function (value) {
    var text = String(value);
    this._query = text === '' || text === '?' ? undefined : encodePart(text.charAt(0) === '?' ? text.slice(1) : text, QUERY_KEEP);
    this._params._parse(this._query || '');
  });
  prop('hash', function () { return this._fragment ? '#' + this._fragment : ''; }, function (value) {
    var text = String(value);
    this._fragment = text === '' || text === '#' ? undefined : (text.charAt(0) === '#' ? text.slice(1) : text);
  });
  prop('searchParams', function () { return this._params; });
  prop('href', function () {
    var out = this._scheme;
    if (HIERARCHICAL[this._scheme]) {
      out += '//';
      if (this._username || this._password) {
        out += this._username + (this._password ? ':' + this._password : '') + '@';
      }
      out += this.host;
    }
    return out + this._path + this.search + this.hash;
  });

  URL.prototype.toString = function () { return this.href; };
  URL.prototype.toJSON = function () { return this.href; };
  URL.canParse = function (url, base) {
    try {
      new URL(url, base);
      return true;
    } catch (e) {
      return false;
    }
  };

  global.URL = URL;
  global.URLSearchParams = URLSearchParams;
})(globalThis);
