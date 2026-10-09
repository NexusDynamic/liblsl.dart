// The theme button: system (the default), light, dark. The choice is kept
// in localStorage and applied as data-theme on <html>, which style.css
// reads. Loaded in <head>, so a stored choice applies before first paint.
(function () {
  var key = 'liblsl-dart-theme';
  var root = document.documentElement;

  function stored() {
    try {
      var mode = localStorage.getItem(key);
      return mode === 'light' || mode === 'dark' ? mode : null;
    } catch (e) {
      return null;
    }
  }

  function apply(mode) {
    if (mode) root.setAttribute('data-theme', mode);
    else root.removeAttribute('data-theme');
  }

  apply(stored());

  document.addEventListener('DOMContentLoaded', function () {
    var button = document.querySelector('.theme-toggle');
    if (!button) return;
    function label() {
      button.textContent = 'Theme: ' + (stored() || 'system');
    }
    label();
    button.hidden = false;
    button.addEventListener('click', function () {
      var mode = stored();
      var next = mode === null ? 'light' : mode === 'light' ? 'dark' : null;
      try {
        if (next) localStorage.setItem(key, next);
        else localStorage.removeItem(key);
      } catch (e) {}
      apply(next);
      label();
    });
  });
})();
