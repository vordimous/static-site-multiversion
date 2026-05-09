// Shared multi-version switcher shim used by every examples/<builder>/.
//
// Reads `data-mode` from the host <div id="version-switcher"> and dispatches:
//
//   baked   — render the dropdown from an inline JSON seed (the snapshot
//             of versions known at build time). No fetch. Old version
//             stays frozen.
//   runtime — ignore the seed; fetch ../versions.json (the per-builder
//             canonical list, written by the orchestrator post-build) and
//             render from that. If the fetch fails, render only a
//             "View all versions" link to data-fallback.
//   hybrid  — render the seed first (works without network), then fetch
//             ../versions.json and replace the dropdown if the canonical
//             list differs from the seed. Falls back to seed on fetch
//             failure. Default mode.
//
// Seed format:
//   <div id="version-switcher" data-mode="hybrid" data-fallback="../next/">
//     <script type="application/json" id="version-switcher-seed">
//       [{"key":"0.9","label":"0.9"},{"key":"1.0","label":"1.0"}]
//     </script>
//   </div>

(function () {
  var mount = document.getElementById('version-switcher');
  if (!mount) return;

  var mode = mount.getAttribute('data-mode') || 'hybrid';
  var fallbackHref = mount.getAttribute('data-fallback') || '../next/';

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
    return fetch('../versions.json', { cache: 'no-cache' })
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
      if (existing.options[i].value !== versions[i].key) return false;
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
