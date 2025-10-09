document.addEventListener('DOMContentLoaded', function () {
  var root = document.documentElement;
  var buttons = document.querySelectorAll('[data-theme-mode]');
  var mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');

  function resolveTheme(mode) {
    if (mode === 'system') {
      return mediaQuery.matches ? 'dark' : 'light';
    }
    return mode;
  }

  function setTheme(mode, persist) {
    if (persist === void 0) {
      persist = true;
    }
    var theme = resolveTheme(mode);
    root.dataset.theme = theme;
    root.dataset.themeMode = mode;

    buttons.forEach(function (btn) {
      var isActive = btn.dataset.themeMode === mode;
      btn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    });

    if (!persist) {
      return;
    }

    if (mode === 'system') {
      localStorage.removeItem('dartantic-theme');
    } else {
      localStorage.setItem('dartantic-theme', mode);
    }
  }

  var stored = localStorage.getItem('dartantic-theme');
  if (stored === 'light' || stored === 'dark') {
    setTheme(stored, false);
  } else {
    setTheme('system', false);
  }

  buttons.forEach(function (button) {
    button.addEventListener('click', function () {
      setTheme(button.dataset.themeMode);
    });
  });

  mediaQuery.addEventListener('change', function () {
    if (root.dataset.themeMode === 'system') {
      setTheme('system', false);
    }
  });

  var yearPlaceholder = document.getElementById('current-year');
  if (yearPlaceholder) {
    yearPlaceholder.textContent = new Date().getFullYear().toString();
  }
});
