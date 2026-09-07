(() => {
  const root = document.documentElement;
  const themeToggle = document.querySelector("#themeToggle");
  const themeMeta = document.querySelector('meta[name="theme-color"]');

  function preferredTheme() {
    const saved = localStorage.getItem("theme");
    if (saved === "light" || saved === "dark") return saved;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function setTheme(theme, persist = true) {
    root.dataset.theme = theme;
    if (persist) localStorage.setItem("theme", theme);
    if (themeToggle) {
      themeToggle.setAttribute("aria-label", `${theme === "dark" ? "明るい" : "暗い"}表示に切り替える`);
    }
    if (themeMeta) themeMeta.content = theme === "dark" ? "#17141d" : "#f8f4f7";
  }

  setTheme(preferredTheme(), false);
  themeToggle?.addEventListener("click", () => {
    setTheme(root.dataset.theme === "dark" ? "light" : "dark");
  });

  const search = document.querySelector("#gameSearch");
  if (!search) return;

  const cards = [...document.querySelectorAll(".game-card")];
  const engineFilter = document.querySelector("#engineFilter");
  const editionFilter = document.querySelector("#editionFilter");
  const clearFilters = document.querySelector("#clearFilters");
  const emptyReset = document.querySelector("#emptyReset");
  const emptyState = document.querySelector("#emptyState");
  const resultStatus = document.querySelector("#resultStatus");
  const shareSearch = document.querySelector("#shareSearch");

  function normalize(value) {
    return String(value ?? "")
      .normalize("NFKC")
      .toLowerCase()
      .replace(/ヵ/g, "か")
      .replace(/ヶ/g, "け")
      .replace(/[ァ-ヴ]/g, (character) => String.fromCharCode(character.charCodeAt(0) - 0x60))
      .replace(/[\s\u3000・･~〜～ー‐‑‒–—―−_.,，。!！?？:：;；'"“”‘’「」『』【】［］\[\]（）()×]/g, "");
  }

  const indexes = new Map(
    cards.map((card) => [
      card,
      {
        text: normalize(card.dataset.search),
        engine: card.dataset.engine,
        editions: card.dataset.editions.split("|").filter(Boolean),
      },
    ])
  );

  function addOptions(select, values) {
    [...new Set(values)].sort((a, b) => a.localeCompare(b, "ja")).forEach((value) => {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = value;
      select.append(option);
    });
  }

  addOptions(engineFilter, cards.map((card) => card.dataset.engine));
  addOptions(editionFilter, cards.flatMap((card) => card.dataset.editions.split("|").filter(Boolean)));

  function readUrl() {
    const params = new URLSearchParams(location.search);
    search.value = params.get("q") ?? "";
    engineFilter.value = params.get("engine") ?? "";
    editionFilter.value = params.get("edition") ?? "";
  }

  function writeUrl() {
    const params = new URLSearchParams();
    if (search.value.trim()) params.set("q", search.value.trim());
    if (engineFilter.value) params.set("engine", engineFilter.value);
    if (editionFilter.value) params.set("edition", editionFilter.value);
    const query = params.toString();
    history.replaceState(null, "", `${location.pathname}${query ? `?${query}` : ""}${location.hash}`);
  }

  function applyFilters({ updateUrl = true } = {}) {
    const tokens = search.value.trim().split(/\s+/).map(normalize).filter(Boolean);
    let visible = 0;

    cards.forEach((card) => {
      const index = indexes.get(card);
      const matchesText = tokens.every((token) => index.text.includes(token));
      const matchesEngine = !engineFilter.value || index.engine === engineFilter.value;
      const matchesEdition = !editionFilter.value || index.editions.includes(editionFilter.value);
      const show = matchesText && matchesEngine && matchesEdition;
      card.hidden = !show;
      if (show) visible += 1;
    });

    resultStatus.innerHTML = `<strong>${visible}</strong>件見つかりました`;
    emptyState.hidden = visible !== 0;
    clearFilters.disabled = !search.value && !engineFilter.value && !editionFilter.value;
    if (updateUrl) writeUrl();
  }

  function reset() {
    search.value = "";
    engineFilter.value = "";
    editionFilter.value = "";
    applyFilters();
    search.focus();
  }

  readUrl();
  applyFilters({ updateUrl: false });

  search.addEventListener("input", () => applyFilters());
  engineFilter.addEventListener("change", () => applyFilters());
  editionFilter.addEventListener("change", () => applyFilters());
  clearFilters.addEventListener("click", reset);
  emptyReset.addEventListener("click", reset);

  document.querySelectorAll("[data-query]").forEach((button) => {
    button.addEventListener("click", () => {
      search.value = button.dataset.query;
      applyFilters();
      search.focus();
    });
  });

  document.querySelectorAll("[data-engine-query]").forEach((button) => {
    button.addEventListener("click", () => {
      engineFilter.value = button.dataset.engineQuery;
      applyFilters();
      document.querySelector("#search").scrollIntoView({ behavior: "smooth" });
    });
  });

  shareSearch.addEventListener("click", async () => {
    writeUrl();
    try {
      await navigator.clipboard.writeText(location.href);
      const label = shareSearch.querySelector("span");
      const original = label.textContent;
      label.textContent = "コピーしました";
      shareSearch.classList.add("copied");
      setTimeout(() => {
        label.textContent = original;
        shareSearch.classList.remove("copied");
      }, 1800);
    } catch {
      window.prompt("このURLをコピーしてください", location.href);
    }
  });

  window.addEventListener("popstate", () => {
    readUrl();
    applyFilters({ updateUrl: false });
  });

  document.addEventListener("keydown", (event) => {
    const typing = /input|textarea|select/i.test(document.activeElement?.tagName);
    if ((event.key === "/" && !typing) || ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k")) {
      event.preventDefault();
      search.focus();
      search.select();
    }
    if (event.key === "Escape" && document.activeElement === search) {
      if (search.value) reset();
      else search.blur();
    }
    if (event.key === "Enter" && document.activeElement === search) {
      const first = cards.find((card) => !card.hidden);
      first?.querySelector("h3 a")?.click();
    }
  });
})();
