import { useEffect, useState } from "react";
import {
  AppWindow, ArrowDown, ArrowRight, ClipboardText, FileText, GithubLogo,
  LinkSimple, MagnifyingGlass, Moon, NotePencil, Sun, Lightning,
} from "@phosphor-icons/react";
import { searchResults } from "./examples.js";

const github = "https://github.com/movvgli/Wookey";
const releases = github + "/releases";
const stable = releases + "/latest";
const docs = github + "/blob/main/docs/";
const asset = (file) => "./assets/" + file;
const searchIcons = { app: AppWindow, note: NotePencil, flow: Lightning };

function Download({ children = "Mac용 프리뷰 받기" }) {
  return <a className="download" href={releases}>{children}<ArrowDown size={19} weight="bold" /></a>;
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
                    <kbd aria-label="Enter">↵</kbd>
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
      <h2 id="features-title">찾고, 꺼내 쓰고,<br className="mobile-break" /> 한 번에 실행.</h2>
      <div className="feature-grid">
        <article className="feature-card feature-search">
          <h3>빠른 검색</h3>
          <div className="mini-window mini-search" aria-hidden="true">
            <div><MagnifyingGlass size={18} /> 회의 <kbd>⌥ Space</kbd></div>
            <div className="mini-highlight"><NotePencil size={18} /> 회의 노트 <small>템플릿</small></div>
            <div><LinkSimple size={18} /> 회의실 예약 <small>링크</small></div>
          </div>
          <p><b>⌥ Space</b>로 앱·링크·템플릿·워크플로를 찾고, <b>⌘ Enter</b>로 웹을 검색하세요. 계산과 환율 변환도 바로 할 수 있어요.</p>
        </article>
        <article className="feature-card feature-drawer">
          <h3>클립보드와 서랍</h3>
          <div className="mini-window mini-drawer" aria-hidden="true">
            <div className="mini-title"><ClipboardText size={18} /> 우키 서랍</div>
            <div><FileText size={18} /> 회의 자료.pdf</div>
            <div><LinkSimple size={18} /> 참고 링크</div>
          </div>
          <p>이전에 복사한 내용을 다시 꺼내 쓰세요. 파일이나 링크를 끌다가 두 번 흔들면 서랍이 열립니다.</p>
        </article>
        <article className="feature-card feature-flow">
          <h3>워크플로와 창 배치</h3>
          <div className="mini-window mini-flow" aria-hidden="true">
            <div className="mini-title"><Lightning size={19} weight="fill" /> 작업 시작 <kbd>↵</kbd></div>
            <div className="mini-layout"><span><AppWindow size={20} /> 브라우저</span><span><NotePencil size={20} /> 메모</span></div>
          </div>
          <p>앱 열기, 서식 있는 템플릿 붙여넣기, 창 배치를 원하는 순서로 묶어 단축키로 실행하세요.</p>
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
        <h2 id="appearance-title">내 취향대로 꾸미기</h2>
        <p>우키와 바나나, 샤키와 산호 중에서 골라보세요. 아이콘은 3D와 플러피, 화면은 하늘색을 포함한 다섯 가지 테마로 바꿀 수 있어요.</p>
        <div className="segmented" role="group" aria-label="아이콘 테마 미리보기">
          <button type="button" aria-pressed={theme === "3d"} onClick={() => setTheme("3d")}>3D</button>
          <button type="button" aria-pressed={theme === "fluffy"} onClick={() => setTheme("fluffy")}>플러피</button>
        </div>
      </div>
      <div className="characters">
        {characters.map(([key, name]) => (
          <div className={"character " + key} key={key}>
            <img src={asset(key + "-" + theme + ".webp")} alt={name} loading="lazy" />
          </div>
        ))}
      </div>
    </section>
  );
}

export function App() {
  const [dark, setDark] = useState(() => {
    try { return localStorage.getItem("wikey-site-theme") === "dark"; }
    catch { return false; }
  });
  useEffect(() => {
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    try { localStorage.setItem("wikey-site-theme", dark ? "dark" : "light"); }
    catch { /* The site also works with storage disabled. */ }
  }, [dark]);

  return (
    <div className="site" id="top">
      <a className="skip-link" href="#main">본문으로 바로가기</a>
      <header className="header">
        <a className="brand" href="#top"><img src={asset("wookey-icon.png")} alt="" width="44" height="44" />Wookey</a>
        <nav aria-label="주요 메뉴">
          <a href="#features">기능</a><a href="#appearance">꾸미기</a><a href="#install">다운로드</a>
          <a className="github-nav" href={github}><GithubLogo size={24} weight="fill" /><span>GitHub</span></a>
        </nav>
      </header>
      <main id="main">
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-copy">
            <h1 id="hero-title">Mac에서<br />자주 쓰는 것들을<br />한곳에.</h1>
            <p>앱과 링크를 검색하고, 복사한 내용과 파일을 꺼내 쓰고, 반복 작업은 단축키로 실행하세요.</p>
            <div className="hero-actions"><Download /><a href={stable}>정식 버전</a></div>
            <p className="compatibility">macOS 14 이상 · Apple Silicon 및 Intel</p>
          </div>
          <Demo />
        </section>
        <Features />
        <Appearance />
        <div className="details">
          <section id="install" aria-labelledby="install-title">
            <h2 id="install-title">설치와 다운로드</h2>
            <p>DMG를 열고 앱을 응용 프로그램 폴더로 옮긴 뒤 <b>⌥ Space</b>로 빠른 검색을 열어보세요.</p>
            <dl className="channels">
              <div><dt>프리뷰</dt><dd>이 페이지의 기능을 먼저 써 볼 수 있는 Apple 공증 전 빌드입니다. 릴리스 목록에서 <b>Pre-release</b>가 붙은 Wookey DMG를 받으세요.</dd></div>
              <div><dt>정식 버전</dt><dd>Apple 공증을 마친 버전입니다. 파일에 이전 이름인 Monkey가 표시될 수 있습니다.</dd></div>
            </dl>
            <div className="detail-actions"><Download /><a className="text-link" href={stable}>정식 버전 <ArrowRight size={16} /></a></div>
            <p className="small-copy">자동 붙여넣기와 창 배치에는 손쉬운 사용, 두 단계 단축키에는 입력 모니터링도 필요합니다.</p>
            <a className="text-link" href={docs + "INSTALL.md"}>설치 및 권한 안내 <ArrowRight size={16} /></a>
          </section>
          <section id="privacy" aria-labelledby="privacy-title">
            <h2 id="privacy-title">개인정보</h2>
            <p>워크플로, 템플릿, 클립보드와 서랍은 기본적으로 Mac에 저장됩니다.</p>
            <p>선택적 동기화를 켜면 워크플로와 템플릿 등의 설정 및 첨부 파일 사본을 개인 iCloud Drive 폴더에 보관할 수 있습니다. 기본값은 꺼짐입니다.</p>
            <a className="text-link" href={docs + "PRIVACY.md"}>개인정보 및 동기화 안내 <ArrowRight size={16} /></a>
          </section>
        </div>
      </main>
      <footer className="footer">
        <a className="text-link" href={github}><GithubLogo weight="fill" size={22} /> GitHub</a>
        <div><a href={releases}>릴리스 내역</a><a href="#privacy">개인정보</a>
          <button className="mode" type="button" aria-label={dark ? "밝은 화면으로 전환" : "어두운 화면으로 전환"}
            onClick={() => setDark(!dark)}>{dark ? <Sun size={20} /> : <Moon size={20} />}</button></div>
      </footer>
    </div>
  );
}
