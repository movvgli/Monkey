import { useEffect, useState } from "react";
import {
  AppWindow, ArrowRight, ClipboardText, DownloadSimple, FileText, GithubLogo,
  LinkSimple, MagnifyingGlass, Moon, NotePencil, Sun, Lightning,
} from "@phosphor-icons/react";
import { searchResults } from "./examples.js";

const github = "https://github.com/movvgli/Wookey";
const releases = github + "/releases";
const stable = releases + "/latest";
const version = "1.2.60";
const releaseTag = "v" + version;
const dmg = releases + "/download/" + releaseTag + "/Wookey-" + version + ".dmg";
const docs = github + "/blob/" + releaseTag + "/docs/";
const asset = (file) => "./assets/" + file;
const searchIcons = { app: AppWindow, note: NotePencil, flow: Lightning };

function Download() {
  return <a className="button download" href={dmg}><DownloadSimple size={21} weight="bold" aria-hidden="true" />Mac용 다운로드</a>;
}

export function Demo() {
  const [query, setQuery] = useState("");
  const [highlight, setHighlight] = useState(0);
  const [message, setMessage] = useState("");
  const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  const results = searchResults.filter((item) => terms.every((term) =>
    (item.title + " " + item.keywords).includes(term)));
  const selected = results[highlight];

  function activate(item) {
    setMessage("예시 동작 · " + item.title + " " + item.action);
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
            <input type="search" value={query} placeholder="Wookey에서 검색…" aria-label="기능 예시 검색"
              onKeyDown={handleKeyDown} onChange={(event) => {
                setQuery(event.target.value);
                setHighlight(0);
                setMessage("");
              }} />
            <span className="keys" aria-label="Option Space"><kbd>⌥</kbd><kbd>Space</kbd></span>
          </div>
          <ul className="launcher-results" aria-label="예시 검색 결과">
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
            {!results.length && <li className="empty-result">일치하는 예시가 없어요.</li>}
          </ul>
          <p className="demo-status" aria-live="polite">{message || "가상 예시 · 실제 개인 설정이 아닙니다"}</p>
        </div>
      </div>
    </figure>
  );
}

function Features() {
  return (
    <section id="features" className="features" aria-labelledby="features-title">
      <h2 id="features-title" className="ruled-heading">키보드에서 바로 시작</h2>
      <div className="feature-grid">
        <article className="feature-card">
          <div className="feature-art feature-search" aria-hidden="true">
            <div className="mini-window">
              <div><MagnifyingGlass size={18} /> 회의 <kbd>⌥ Space</kbd></div>
              <div className="mini-highlight"><NotePencil size={18} /> 회의 노트 <small>템플릿</small></div>
              <div><LinkSimple size={18} /> 회의실 예약 <small>링크</small></div>
            </div>
          </div>
          <h3>빠른 검색</h3>
          <p><b className="shortcut">⌥ Space</b>로 앱, 파일, 폴더, 링크와 워크플로를 찾아보세요. 최근 클립보드와 폴더 항목도 바로 열 수 있어요. <b className="shortcut">⌘ Enter</b>를 누르면 웹에서 검색합니다.</p>
        </article>
        <article className="feature-card">
          <div className="feature-art feature-drawer" aria-hidden="true">
            <div className="mini-window">
              <div className="mini-highlight"><ClipboardText size={18} /> 우키 서랍</div>
              <div><FileText size={18} /> 회의 자료.pdf</div>
              <div><LinkSimple size={18} /> 참고 링크</div>
            </div>
          </div>
          <h3>클립보드와 서랍</h3>
          <p>복사 기록을 다시 쓰고, 파일이나 링크를 끌다가 두 번 흔들어 서랍에 담으세요. 캐릭터를 잡고 서랍을 옮기거나, 여러 항목을 골라 한꺼번에 꺼낼 수 있어요.</p>
        </article>
        <article className="feature-card">
          <div className="feature-art feature-flow" aria-hidden="true">
            <div className="mini-window">
              <div><Lightning size={18} weight="fill" /> 작업 시작 <kbd>↵</kbd></div>
              <div className="mini-layout">
                <span><AppWindow size={20} /> 브라우저</span><span><NotePencil size={20} /> 메모</span>
              </div>
            </div>
          </div>
          <h3>워크플로와 창 배치</h3>
          <p>앱 열기, 템플릿 붙여넣기, 창 배치를 묶어 단축키로 실행하세요. 템플릿에 단축키를 바로 지정하거나 설정에서 Hyper 키를 사용할 수 있어요.</p>
        </article>
      </div>
    </section>
  );
}

function Appearance() {
  const [theme, setTheme] = useState("3d");
  const characters = [
    ["wookey", "우키"], ["banana", "바나나"], ["sharkey", "샤키"], ["coral", "산호"],
  ];
  return (
    <section id="appearance" className="appearance" aria-labelledby="appearance-title">
      <div className="appearance-copy">
        <h2 id="appearance-title">나만의 우키</h2>
        <p>설정의 테마 탭에서 화면 색, 캐릭터 조합, 3D·플러피 아이콘을 각각 고를 수 있어요.</p>
        <div className="segmented" role="group" aria-label="아이콘 테마 미리보기">
          <button type="button" aria-pressed={theme === "3d"} onClick={() => setTheme("3d")}>3D</button>
          <button type="button" aria-pressed={theme === "fluffy"} onClick={() => setTheme("fluffy")}>플러피</button>
        </div>
      </div>
      <div className="characters">
        {characters.map(([key, name]) => (
          <figure className="character" key={key}>
            <img src={asset(key + "-" + theme + ".webp")} alt="" loading="lazy" />
            <figcaption>{name}</figcaption>
          </figure>
        ))}
      </div>
    </section>
  );
}

export function App() {
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
      <a className="skip-link" href="#main">본문으로 바로가기</a>
      <header className="header">
        <a className="brand" href="#top"><img src={asset("wookey-icon.png")} alt="" width="44" height="44" />Wookey</a>
        <nav aria-label="주요 메뉴">
          <a href="#features">기능</a><a href="#appearance">꾸미기</a><a href="#download">다운로드</a>
        </nav>
        <a className="button github-nav" href={github}><GithubLogo size={20} weight="fill" aria-hidden="true" /><span>GitHub</span></a>
      </header>
      <main id="main">
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-copy">
            <h1 id="hero-title">Mac에서 자주 쓰는 일, <br />단축키 하나로</h1>
            <p>앱과 파일을 찾고, 복사한 내용을 꺼내 쓰고, 반복 작업을 실행하세요.</p>
            <div className="hero-actions"><Download /><a className="button secondary" href="#install">설치 안내</a></div>
            <p className="compatibility">macOS 14 이상 · Apple Silicon 및 Intel</p>
          </div>
          <Demo />
        </section>
        <Features />
        <Appearance />
        <div className="details">
          <section id="install" aria-labelledby="install-title">
            <h2 id="install-title">설치와 권한</h2>
            <ol className="install-steps">
              <li>정식 DMG를 다운로드해 엽니다.</li>
              <li>Wookey를 <b>응용 프로그램</b> 폴더로 옮깁니다.</li>
              <li>Wookey를 실행하고 <b className="shortcut">⌥ Space</b>를 눌러보세요.</li>
            </ol>
            <p>자동 붙여넣기와 창 배치에는 손쉬운 사용 권한이 필요합니다. 두 단계 단축키와 Hyper 키는 입력 모니터링도 사용합니다.</p>
            <a className="text-link" href={docs + "INSTALL.md"}>설치 안내 <ArrowRight size={16} aria-hidden="true" /></a>
          </section>
          <section id="privacy" aria-labelledby="privacy-title">
            <h2 id="privacy-title">개인정보</h2>
            <p>워크플로, 템플릿, 클립보드 기록과 서랍 항목은 기본적으로 Mac에 저장됩니다.</p>
            <p>설정에서 동기화를 켜면 워크플로와 템플릿 등을 개인 iCloud Drive 폴더에 보관할 수 있습니다. 기본값은 꺼짐입니다.</p>
            <a className="text-link" href={docs + "PRIVACY.md"}>개인정보 및 동기화 안내 <ArrowRight size={16} aria-hidden="true" /></a>
          </section>
        </div>
        <section id="download" className="download-banner" aria-labelledby="download-title">
          <div>
            <h2 id="download-title">Wookey 다운로드</h2>
            <p>정식 버전 {version} · macOS 14 이상</p>
            <p>Apple Silicon 및 Intel · 무료 오픈소스</p>
          </div>
          <img src={asset("wookey-fluffy.webp")} alt="" loading="lazy" />
          <div className="download-actions">
            <Download />
            <a className="text-link" href={stable}>최신 릴리스 <ArrowRight size={16} aria-hidden="true" /></a>
          </div>
        </section>
      </main>
      <footer className="footer">
        <a className="footer-brand" href="#top">Wookey</a>
        <div><a href={github}>GitHub</a><a href={releases}>릴리스 내역</a><a href="#privacy">개인정보</a>
          <button className="mode" type="button" aria-label={dark ? "밝은 화면으로 전환" : "어두운 화면으로 전환"}
            onClick={() => setDark(!dark)}>{dark ? <Sun size={20} /> : <Moon size={20} />}</button></div>
      </footer>
    </div>
  );
}
