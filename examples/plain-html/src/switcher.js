// Renders a version dropdown into <div id="version-switcher"> by fetching
// versions.json from the current version's root and replacing the version
// segment in window.location.pathname when the user picks a new version.
//
// Each deployed version contains its own copy of versions.json (the
// orchestrator merges deploy-versions.json with the site's seed manifest and
// copies the result into every clone before building). The dropdown navigates
// across versions by swapping the version slug in the URL path.

(function () {
  var mount = document.getElementById('version-switcher');
  if (!mount) return;

  fetch('./versions.json', { cache: 'no-cache' })
    .then(function (r) { return r.ok ? r.json() : []; })
    .then(function (versions) {
      if (!versions.length) return;

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

      mount.appendChild(document.createTextNode('Version: '));
      mount.appendChild(select);
    })
    .catch(function () { /* swallow: switcher is best-effort */ });
})();
