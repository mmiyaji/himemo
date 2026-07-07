(() => {
  const storageKey = 'himemo-site-language';
  const languages = ['ja', 'en'];

  const readSavedLanguage = () => {
    try {
      return window.localStorage.getItem(storageKey);
    } catch {
      return null;
    }
  };

  const saveLanguage = (language) => {
    try {
      window.localStorage.setItem(storageKey, language);
    } catch {
      // Language switching still works for the current page.
    }
  };

  const readUrlLanguage = () => {
    const requested = new URLSearchParams(window.location.search).get('lang');
    return languages.includes(requested) ? requested : null;
  };

  const updateUrlLanguage = (language) => {
    const url = new URL(window.location.href);
    url.searchParams.set('lang', language);
    window.history.replaceState(null, '', `${url.pathname}${url.search}${url.hash}`);
  };

  const initialLanguage = () => {
    const requested = readUrlLanguage();
    if (requested) {
      return requested;
    }
    const saved = readSavedLanguage();
    if (languages.includes(saved)) {
      return saved;
    }
    return window.navigator.language.toLowerCase().startsWith('ja') ? 'ja' : 'en';
  };

  const setLanguage = (language, options = {}) => {
    const nextLanguage = languages.includes(language) ? language : 'ja';
    document.documentElement.lang = nextLanguage;
    document.documentElement.dataset.lang = nextLanguage;
    saveLanguage(nextLanguage);

    if (options.updateUrl) {
      updateUrlLanguage(nextLanguage);
    }

    document.querySelectorAll('[data-i18n-ja][data-i18n-en]').forEach((element) => {
      const text = nextLanguage === 'ja' ? element.dataset.i18nJa : element.dataset.i18nEn;
      if (text) {
        element.textContent = text;
      }
    });

    document.querySelectorAll('[data-i18n-aria-ja][data-i18n-aria-en]').forEach((element) => {
      const label =
        nextLanguage === 'ja' ? element.dataset.i18nAriaJa : element.dataset.i18nAriaEn;
      if (label) {
        element.setAttribute('aria-label', label);
      }
    });

    document.querySelectorAll('[data-lang-panel]').forEach((element) => {
      element.hidden = element.dataset.langPanel !== nextLanguage;
    });

    document.querySelectorAll('[data-media-ja][data-media-en]').forEach((element) => {
      const source = nextLanguage === 'ja' ? element.dataset.mediaJa : element.dataset.mediaEn;
      if (!source) {
        return;
      }
      if (element.tagName === 'IMG') {
        element.setAttribute('src', source);
      }
      if (element.tagName === 'A') {
        element.setAttribute('href', source);
      }
    });

    document.querySelectorAll('[data-lang-choice]').forEach((button) => {
      const selected = button.dataset.langChoice === nextLanguage;
      button.setAttribute('aria-pressed', selected ? 'true' : 'false');
    });
  };

  document.addEventListener('DOMContentLoaded', () => {
    setLanguage(initialLanguage());

    document.querySelectorAll('[data-lang-choice]').forEach((button) => {
      button.addEventListener('click', () => {
        setLanguage(button.dataset.langChoice, { updateUrl: true });
      });
    });
  });
})();
