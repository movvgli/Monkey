import assert from "node:assert/strict";
import test from "node:test";
import { readdir, readFile } from "node:fs/promises";
import { createRequire, Module } from "node:module";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { searchResults } from "../src/examples.js";

const require = createRequire(import.meta.url);
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");
const output = await build({ entryPoints: [fileURLToPath(new URL("../src/App.jsx", import.meta.url))], bundle: true, platform: "node", format: "cjs", jsx: "automatic", mainFields: ["module", "main"], external: ["react", "react/jsx-runtime"], write: false });
const filename = fileURLToPath(new URL("../render-test.cjs", import.meta.url));
const compiled = new Module(filename);
compiled.filename = filename;
compiled.paths = require.resolve.paths("react");
compiled._compile(output.outputFiles[0].text, compiled.filename);
const { App, Demo } = compiled.exports;

test("search renders only fictional examples and labels them", () => {
  const html = renderToStaticMarkup(React.createElement(Demo));
  for (const { title } of searchResults) assert.ok(html.includes(title));
  assert.ok(html.includes("실제 개인 설정이 아닙니다"));
  assert.ok(html.includes('aria-label="기능 예시 검색"'));
});

test("site renders distinct release channels and privacy details without storage", () => {
  const prior = Object.getOwnPropertyDescriptor(globalThis, "localStorage");
  Object.defineProperty(globalThis, "localStorage", { configurable: true, get() { throw new Error("Storage disabled"); } });
  try {
    const html = renderToStaticMarkup(React.createElement(App));
    for (const text of ["macOS 14 이상", "가상 예시", "손쉬운 사용", "입력 모니터링", "Apple 공증 전 빌드", "Pre-release"]) {
      assert.ok(html.includes(text), text);
    }
    assert.ok(html.includes('href="https://github.com/movvgli/Wookey/releases"'));
    assert.ok(html.includes('href="https://github.com/movvgli/Wookey/releases/latest"'));
    assert.ok(!html.includes("<form"));
    assert.ok(html.includes('src="./assets/wookey-icon.png"'));
    const privacy = html.match(/<section id="privacy"[\s\S]*?<\/section>/)?.[0];
    assert.ok(privacy);
    assert.ok(privacy.includes("개인 iCloud Drive 폴더"));
    assert.ok(privacy.includes("기본값은 꺼짐"));
    assert.ok(!privacy.includes("가상 예시"));
  } finally {
    if (prior) Object.defineProperty(globalThis, "localStorage", prior);
    else delete globalThis.localStorage;
  }
});

test("built entry uses relative assets for GitHub Pages project paths", async () => {
  const html = await readFile(new URL("../dist/client/index.html", import.meta.url), "utf8");
  assert.ok(!/(?:src|href)="\/assets\//.test(html));
  assert.ok(/src="\.\/assets\/[^\"]+\.js"/.test(html));
  assert.ok(/href="\.\/assets\/[^\"]+\.css"/.test(html));
});

test("only the app icon and public mascot artwork are copied from public assets", async () => {
  const files = await readdir(new URL("../public/assets/", import.meta.url));
  const approvedFiles = [
    "banana-3d.webp", "banana-fluffy.webp", "coral-3d.webp", "coral-fluffy.webp",
    "sharkey-3d.webp", "sharkey-fluffy.webp", "wookey-3d.webp", "wookey-fluffy.webp", "wookey-icon.png",
  ];
  assert.deepEqual(files.sort(), approvedFiles);
  const publicFiles = await readdir(new URL("../public/", import.meta.url));
  assert.deepEqual(publicFiles, ["assets"]);
});

test("built website contains no old capture, local user path, or private configuration", async () => {
  const root = new URL("../dist/client/", import.meta.url);
  const paths = await readdir(root, { recursive: true, withFileTypes: true });
  for (const entry of paths.filter((entry) => entry.isFile())) {
    assert.ok(!/wikey-workflows|design-reference|home\.png|config\.json|\.map$/.test(entry.name));
    if (!/\.(js|css|html)$/.test(entry.name)) continue;
    const body = await readFile(`${entry.parentPath}/${entry.name}`, "utf8");
    assert.ok(!/wikey-workflows\.png|design-reference\.png|\/Users\/|Library\/Application Support/.test(body));
  }
});
