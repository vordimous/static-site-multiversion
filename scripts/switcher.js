// Shared multi-version switcher shim used by every examples/<builder>/.
//
// Reads `data-mode` from the host <div id="version-switcher"> and dispatches:
//
//   baked   — render the dropdown from an inline JSON seed (the snapshot
//             of versions known at build time). No fetch. Old version
//             stays frozen.
//   runtime — ignore the seed; fetch the canonical per-builder versions
//             list and render from that. If the fetch fails, render only
//             a "View all versions" link to data-fallback.
//   hybrid  — render the seed first (works without network), then fetch
//             the canonical list and replace the dropdown if it differs.
//             Falls back to seed on fetch failure. Default mode.
//
// Mount format:
//   <div id="version-switcher"
//        data-mode="hybrid"
//        data-canonical="/eleventy/versions.json"
//        data-fallback="/eleventy/next/">
//     <script type="application/json" id="version-switcher-seed">
//       [{"key":"0.9","label":"0.9"}]
//     </script>
//   </div>
//
// data-canonical and data-fallback should be ABSOLUTE URL paths so the
// switcher works from nested pages (/<builder>/<key>/sub/). If they're
// missing, the shim falls back to depth-0 relatives (../versions.json,
// ../next/) which only work from the per-version landing page.

(function () {
  var mount = document.getElementById('version-switcher');
  if (!mount) return;

  var mode = mount.getAttribute('data-mode') || 'hybrid';
  var fallbackHref = mount.getAttribute('data-fallback') || '../next/';
  var canonicalUrl = mount.getAttribute('data-canonical') || '../versions.json';

  var seed = readSeed();

  if (mode === 'baked') {
    if (seed.length) renderDropdown(seed);
    return;
  }

  if (mode === 'runtime') {
    fetchCanonical()
      .then(function (versions) {
        if (versions.length) renderDropdown(versions);
        else renderFallbackLink();
      })
      .catch(renderFallbackLink);
    return;
  }

  // hybrid (default)
  if (seed.length) renderDropdown(seed);
  fetchCanonical()
    .then(function (versions) {
      if (!versions.length) return;
      if (sameAsRendered(versions)) return;
      clearMount();
      renderDropdown(versions);
    })
    .catch(function () { /* keep the seed rendering */ });

  function readSeed() {
    var el = mount.querySelector('script[type="application/json"]#version-switcher-seed')
          || document.getElementById('version-switcher-seed');
    if (!el) return [];
    try { return JSON.parse(el.textContent || '[]') || []; }
    catch (_) { return []; }
  }

  function fetchCanonical() {
    return fetch(canonicalUrl, { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.json() : []; });
  }

  function clearMount() {
    while (mount.firstChild) mount.removeChild(mount.firstChild);
  }

  function renderFallbackLink() {
    clearMount();
    var a = document.createElement('a');
    a.href = fallbackHref;
    a.textContent = 'View all versions';
    mount.appendChild(a);
  }

  function sameAsRendered(versions) {
    var existing = mount.querySelector('select');
    if (!existing) return false;
    if (existing.options.length !== versions.length) return false;
    for (var i = 0; i < versions.length; i++) {
      var opt = existing.options[i];
      var expectedLabel = versions[i].label || versions[i].key;
      if (opt.value !== versions[i].key) return false;
      if (opt.textContent !== expectedLabel) return false;
    }
    return true;
  }

  function renderDropdown(versions) {
    var keys = versions.map(function (v) { return v.key; });
    var path = window.location.pathname;
    var segments = path.split('/').filter(Boolean);
    var idx = -1;
    for (var i = 0; i < segments.length; i++) {
      if (keys.indexOf(segments[i]) !== -1) { idx = i; break; }
    }
    var current = idx >= 0 ? segments[idx] : keys[0];

    var select = document.createElement('select');
    versions.forEach(function (v) {
      var opt = document.createElement('option');
      opt.value = v.key;
      opt.textContent = v.label || v.key;
      if (v.key === current) opt.selected = true;
      select.appendChild(opt);
    });

    select.addEventListener('change', function () {
      if (idx < 0) return;
      var next = segments.slice();
      next[idx] = select.value;
      window.location.pathname = '/' + next.join('/') + (path.endsWith('/') ? '/' : '');
    });

    var label = document.createElement('label');
    label.textContent = 'Version: ';
    label.appendChild(select);
    mount.appendChild(label);
  }
})();
