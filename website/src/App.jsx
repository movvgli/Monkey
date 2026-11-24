import { useEffect, useState } from "react";
import {
  AppWindow, ArrowRight, ClipboardText, DownloadSimple, FileText, GithubLogo,
  LinkSimple, MagnifyingGlass, Moon, NotePencil, Sun, Lightning,
} from "@phosphor-icons/react";
import { englishSearchResults, searchResults } from "./examples.js";
import { copy } from "./copy.js";

const github = "https://github.com/movvgli/Wookey";
const releases = github + "/releases";
const stable = releases + "/latest";
const version = "1.2.62";
const releaseTag = "v" + version;
const dmg = releases + "/download/" + releaseTag + "/Wookey-" + version + ".dmg";
const docs = github + "/blob/" + releaseTag + "/docs/";
const asset = (file) => "./assets/" + file;
const searchIcons = { app: AppWindow, note: NotePencil, flow: Lightning };

function Download({ label }) {
  return <a className="button download" href={dmg}><DownloadSimple size={21} weight="bold" aria-hidden="true" />{label}</a>;
}

export function Demo({ language = "ko" } = {}) {
  const labels = copy[language].demo;
  const examples = language === "en" ? englishSearchResults : searchResults;
  const [query, setQuery] = useState("");
  const [highlight, setHighlight] = useState(0);
  const [message, setMessage] = useState("");
  const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  const results = examples.filter((item) => terms.every((term) =>
    (item.title + " " + item.keywords).toLowerCase().includes(term)));
  const selected = results[highlight];

  function activate(item) {
    setMessage(language === "en"
      ? `${labels.action} · ${item.action} ${item.title}`
      : `${labels.action} · ${item.title} ${item.action}`);
  }

  function handleKeyDown(event) {
    if (event.nativeEvent.isComposing || !results.length) return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const offset = event.key === "ArrowDown" ? 1 : -1;
      setHighlight((highlight + offset + results.length) % results.length);
    } else if (event.key === "Enter" && selected) {
      event.preventDefault();
      activate(selected);
    }
  }

  return (
    <figure className="demo">
      <div className="demo-stage">
        <img className="hero-wookey" src={asset("wookey-3d.webp")} alt="" fetchPriority="high" />
        <img className="hero-banana" src={asset("banana-3d.webp")} alt="" fetchPriority="high" />
        <div className="launcher">
          <div className="launcher-field">
            <MagnifyingGlass size={25} aria-hidden="true" />
            <input type="search" value={query} placeholder={labels.placeholder} aria-label={labels.search}
              onKeyDown={handleKeyDown} onChange={(event) => {
                setQuery(event.target.value);
                setHighlight(0);
                setMessage("");
              }} />
            <span className="keys" aria-label="Option Space"><kbd>⌥</kbd><kbd>Space</kbd></span>
          </div>
          <ul className="launcher-results" aria-label={labels.results}>
            {results.map((item, index) => {
              const Icon = searchIcons[item.kind];
              return (
                <li key={item.title}>
                  <button type="button" className={index === highlight ? "highlighted" : ""}
                    onFocus={() => setHighlight(index)} onClick={() => activate(item)}>
                    <span className={"app-symbol " + item.kind}><Icon size={20} weight="bold" aria-hidden="true" /></span>
                    <strong>{item.title}</strong><span className="result-detail">{item.detail}</span>
                    <kbd aria-hidden="true" className="result-key">↵</kbd>
                  </button>
                </li>
              );
            })}
            {!results.length && <li className="empty-result">{labels.empty}</li>}
          </ul>
          <p className="demo-status" aria-live="polite">{message || labels.caption}</p>
        </div>
      </div>
    </figure>
  );
}

function Features({ language }) {
  const { featuresTitle, search, drawer, workflow } = copy[language];
  return (
    <section id="features" className="features" aria-labelledby="features-title">
      <h2 id="features-title" className="ruled-heading">{featuresTitle}</h2>
      <div className="feature-grid">
        <article className="feature-card">
          <div className="feature-art feature-search" aria-hidden="true">
            <div className="mini-window">
              <div><MagnifyingGlass size={18} /> {search.preview[0]} <kbd>⌥ Space</kbd></div>
              <div className="mini-highlight"><NotePencil size={18} /> {search.preview[1]} <small>{search.preview[2]}</small></div>
              <div><LinkSimple size={18} /> {search.preview[3]} <small>{search.preview[4]}</small></div>
            </div>
          </div>
          <h3>{search.title}</h3>
          <p>{search.text[0]}<b className="shortcut">⌥ Space</b>
            {search.text[1]}<b className="shortcut">⌘ Enter</b>{search.text[2]}</p>
        </article>
        <article className="feature-card">
          <div className="feature-art feature-drawer" aria-hidden="true">
            <div className="mini-window">
              <div className="mini-highlight"><ClipboardText size={18} /> {drawer.preview[0]}</div>
              <div><FileText size={18} /> {drawer.preview[1]}</div>
              <div><LinkSimple size={18} /> {drawer.preview[2]}</div>
            </div>
          </div>
          <h3>{drawer.title}</h3>
          <p>{drawer.text}</p>
        </article>
        <article className="feature-card">
          <div className="feature-art feature-flow" aria-hidden="true">
            <div className="mini-window">
              <div><Lightning size={18} weight="fill" /> {workflow.preview[0]} <kbd>↵</kbd></div>
              <div className="mini-layout">
                <span><AppWindow size={20} /> {workflow.preview[1]}</span><span><NotePencil size={20} /> {workflow.preview[2]}</span>
              </div>
            </div>
          </div>
          <h3>{workflow.title}</h3>
          <p>{workflow.text}</p>
        </article>
      </div>
    </section>
  );
}

function Appearance({ labels }) {
  const [theme, setTheme] = useState("3d");
  return (
    <section id="appearance" className="appearance" aria-labelledby="appearance-title">
      <div className="appearance-copy">
        <h2 id="appearance-title">{labels.title}</h2>
        <p>{labels.text}</p>
        <div className="segmented" role="group" aria-label={labels.preview}>
          <button type="button" aria-pressed={theme === "3d"} onClick={() => setTheme("3d")}>3D</button>
          <button type="button" aria-pressed={theme === "fluffy"} onClick={() => setTheme("fluffy")}>{labels.fluffy}</button>
        </div>
      </div>
      <div className="characters">
        {Object.entries(labels.characters).map(([key, name]) => (
          <figure className="character" key={key}>
            <img src={asset(key + "-" + theme + ".webp")} alt="" loading="lazy" />
            <figcaption>{name}</figcaption>
          </figure>
        ))}
      </div>
    </section>
  );
}

function initialLanguage() {
  try {
    const stored = localStorage.getItem("wookey-site-language");
    if (stored === "ko" || stored === "en") return stored;
  } catch { /* Storage can be disabled. */ }
  const preferences = typeof navigator === "undefined" ? [] : (navigator.languages ?? [navigator.language]);
  return preferences.map((preference) => preference.toLowerCase().split("-")[0])
    .find((value) => value === "ko" || value === "en") ?? "ko";
}

export function App() {
  const [language, setLanguage] = useState(initialLanguage);
  const labels = copy[language];
  const { install, privacy, release } = labels;

  useEffect(() => {
    document.documentElement.lang = language;
    document.title = labels.title;
    document.querySelector('meta[name="description"]')?.setAttribute("content", labels.description);
    try { localStorage.setItem("wookey-site-language", language); }
    catch { /* The toggle also works with storage disabled. */ }
  }, [language, labels.title, labels.description]);
  const [dark, setDark] = useState(() => {
    try { return localStorage.getItem("wookey-site-theme") === "dark"; }
    catch { return false; }
  });
  useEffect(() => {
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    try { localStorage.setItem("wookey-site-theme", dark ? "dark" : "light"); }
    catch { /* The site also works with storage disabled. */ }
  }, [dark]);

  return (
    <div className="site" id="top">
      <a className="skip-link" href="#main">{labels.skip}</a>
      <header className="header">
        <a className="brand" href="#top"><img src={asset("wookey-icon.png")} alt="" width="44" height="44" />Wookey</a>
        <nav aria-label={labels.navigation}>
          <a href="#features">{labels.nav[0]}</a><a href="#appearance">{labels.nav[1]}</a><a href="#download">{labels.nav[2]}</a>
        </nav>
        <div className="header-actions">
          <div className="language-toggle" role="group" aria-label={labels.language}>
            <button type="button" lang="ko" aria-pressed={language === "ko"} onClick={() => setLanguage("ko")}>한국어</button>
            <button type="button" lang="en" aria-pressed={language === "en"} onClick={() => setLanguage("en")}>English</button>
          </div>
          <a className="button github-nav" href={github}><GithubLogo size={20} weight="fill" aria-hidden="true" /><span>GitHub</span></a>
        </div>
      </header>
      <main id="main">
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-copy">
            <h1 id="hero-title">{labels.heroTitle[0]} <br />{labels.heroTitle[1]}</h1>
            <p>{labels.heroText}</p>
            <div className="hero-actions"><Download label={labels.download} /><a className="button secondary" href="#install">{labels.installLink}</a></div>
            <p className="compatibility">{labels.compatibility}</p>
          </div>
          <Demo key={language} language={language} />
        </section>
        <Features language={language} />
        <Appearance labels={labels.appearance} />
        <div className="details">
          <section id="install" aria-labelledby="install-title">
            <h2 id="install-title">{install.title}</h2>
            <ol className="install-steps">
              <li>{install.first}</li>
              <li>{install.second[0]}<b>{install.second[1]}</b>{install.second[2]}</li>
              <li>{install.third[0]}<b className="shortcut">⌥ Space</b>{install.third[1]}</li>
            </ol>
            <p>{install.permissions}</p>
            <a className="text-link" href={docs + install.guide}>{labels.installLink} <ArrowRight size={16} aria-hidden="true" /></a>
          </section>
          <section id="privacy" aria-labelledby="privacy-title">
            <h2 id="privacy-title">{privacy.title}</h2>
            <p>{privacy.local}</p>
            <p>{privacy.sync}</p>
            <a className="text-link" href={docs + privacy.guide}>{privacy.link} <ArrowRight size={16} aria-hidden="true" /></a>
          </section>
        </div>
        <section id="download" className="download-banner" aria-labelledby="download-title">
          <div>
            <h2 id="download-title">{release.title}</h2>
            <p>{release.details(version)}</p>
            <p>{release.platform}</p>
          </div>
          <img src={asset("wookey-fluffy.webp")} alt="" loading="lazy" />
          <div className="download-actions">
            <Download label={labels.download} />
            <a className="text-link" href={stable}>{release.latest} <ArrowRight size={16} aria-hidden="true" /></a>
          </div>
        </section>
      </main>
      <footer className="footer">
        <a className="footer-brand" href="#top">Wookey</a>
        <div><a href={github}>GitHub</a><a href={releases}>{release.history}</a><a href="#privacy">{privacy.title}</a>
          <button className="mode" type="button" aria-label={dark ? labels.light : labels.dark}
            onClick={() => setDark(!dark)}>{dark ? <Sun size={20} /> : <Moon size={20} />}</button></div>
      </footer>
    </div>
  );
}
