(function () {
  const root = document.documentElement;
  const saved = localStorage.getItem("himemo-legal-theme");
  const prefersDark = window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches;
  const initial = saved || (prefersDark ? "dark" : "light");

  function applyTheme(theme) {
    root.dataset.theme = theme;
    localStorage.setItem("himemo-legal-theme", theme);
    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      button.textContent = theme === "dark" ? "Light" : "Dark";
      button.setAttribute(
        "aria-label",
        theme === "dark" ? "Switch to light mode" : "Switch to dark mode",
      );
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyTheme(initial);
    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      button.addEventListener("click", function () {
        applyTheme(root.dataset.theme === "dark" ? "light" : "dark");
      });
    });
  });
})();
