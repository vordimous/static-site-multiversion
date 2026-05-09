// Loaded via mkdocs.yml's extra_javascript. Mounts the version-switcher
// element + loads the shared shim. data-mode="baked" demonstrates the
// no-fetch / snapshot-only mode of the static-site-multiversion shim.

(function () {
  function inject() {
    if (document.getElementById('version-switcher')) return;
    var div = document.createElement('div');
    div.id = 'version-switcher';
    div.setAttribute('data-mode', 'baked');
    div.setAttribute('data-fallback', '../next/');
    var seed = document.createElement('script');
    seed.type = 'application/json';
    seed.id = 'version-switcher-seed';
    seed.textContent = '[{"key":"current","label":"current"}]';
    div.appendChild(seed);
    document.body.appendChild(div);
    var s = document.createElement('script');
    s.src = './switcher.js';
    s.defer = true;
    document.body.appendChild(s);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }
})();
