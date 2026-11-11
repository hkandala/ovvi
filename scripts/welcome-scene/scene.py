#!/usr/bin/env python3
"""Writes the welcome scene's repositories under <root>: shortlink (a small web app), api (a Go service), docs,
linkctl (a TypeScript CLI) and notes, each with a few weeks of history and, where the scene shows one, an uncommitted
change; and the agents' scripted turns about them to <turns.json>, which the stand-ins play (OVVI_STAND_IN_SCENE).
Usage: scene.py <root> <turns.json>"""
import difflib
import json
import os
import plistlib
import subprocess
import sys
import time

root = sys.argv[1]
DAY = 86400
PEOPLE = [("Alex Kim", "alex@shortlink.dev"), ("Jordan Lee", "jordan@shortlink.dev")]


def git(repo, *args, when=None, who=0):
    name, mail = PEOPLE[who]
    env = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_AUTHOR_NAME": name,
           "GIT_AUTHOR_EMAIL": mail, "GIT_COMMITTER_NAME": name, "GIT_COMMITTER_EMAIL": mail}
    if when:
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(when))
        env.update(GIT_AUTHOR_DATE=stamp, GIT_COMMITTER_DATE=stamp)
    subprocess.run(["git", "-C", repo, *args], env=env, check=True, capture_output=True)


# Each file opens with TextEdit (a per-file Open With, as Get Info sets it), so File Explorer's Open With names no
# app of the Mac's own choices.
TEXTEDIT = plistlib.dumps({"bundleidentifier": "com.apple.TextEdit", "path": "/System/Applications/TextEdit.app",
                           "version": 0}, fmt=plistlib.FMT_BINARY).hex()


def put(repo, files):
    for path, text in files.items():
        full = os.path.join(repo, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as file:
            file.write(text.lstrip("\n"))
        subprocess.run(["xattr", "-wx", "com.apple.LaunchServices.OpenWith", TEXTEDIT, full], check=True)


def repo(name, commits, uncommitted=None):
    """commits: (days ago, hour, author, message, files), oldest first; each commit writes its files whole."""
    path = os.path.join(root, name)
    os.makedirs(path)
    git(path, "init", "-q", "-b", "main")
    today = time.mktime(time.localtime()[:3] + (0, 0, 0, 0, 0, -1))
    for days, hour, who, message, files in commits:
        put(path, files)
        git(path, "add", "-A")
        git(path, "commit", "-q", "-m", message, when=min(today - days * DAY + hour * 3600, time.time() - 600),
            who=who)
    put(path, uncommitted or {})


# shortlink: a link shortener, Node with no dependencies (`npm run dev`, `npm test`).

LINKS_V1 = '''
// Short codes for long URLs, kept in memory.
import { randomBytes } from "node:crypto";

const ALPHABET = "0123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";

export function makeCode(length = 6) {
  return Array.from(randomBytes(length), (byte) => ALPHABET[byte % ALPHABET.length]).join("");
}

export class LinkStore {
  #links = new Map();

  create(url, { now = Date.now() } = {}) {
    if (!/^https?:\\/\\//.test(url)) throw new Error("not a web address");
    const link = { code: makeCode(), url, clicks: 0, created: now };
    this.#links.set(link.code, link);
    return link;
  }

  open(code) {
    const link = this.#links.get(code);
    if (link) link.clicks += 1;
    return link ?? null;
  }

  recent(limit = 10) {
    return [...this.#links.values()].sort((a, b) => b.created - a.created).slice(0, limit);
  }
}
'''

LINKS = '''
// Short codes for long URLs, kept in memory. A link expires after `days` (30 by default; 0 keeps it).
import { randomBytes } from "node:crypto";

const ALPHABET = "0123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";
export const DAY = 24 * 60 * 60 * 1000;

export function makeCode(length = 6) {
  return Array.from(randomBytes(length), (byte) => ALPHABET[byte % ALPHABET.length]).join("");
}

export class LinkStore {
  #links = new Map();

  create(url, { days = 30, now = Date.now() } = {}) {
    if (!/^https?:\\/\\//.test(url)) throw new Error("not a web address");
    const expiresAt = days > 0 ? now + days * DAY : null;
    const link = { code: makeCode(), url, clicks: 0, created: now, expiresAt };
    this.#links.set(link.code, link);
    return link;
  }

  open(code, now = Date.now()) {
    const link = this.#links.get(code);
    if (!link || (link.expiresAt !== null && link.expiresAt <= now)) return null;
    link.clicks += 1;
    return link;
  }

  recent(limit = 10) {
    return [...this.#links.values()].sort((a, b) => b.created - a.created).slice(0, limit);
  }
}
'''

SEED = '''
// A few links so the page is not empty in development.
import { DAY } from "./links.js";

const LINKS = [
  ["https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-color-scheme", 2, 41, 30],
  ["https://github.com/nodejs/node/blob/main/doc/api/test.md", 5, 128, 30],
  ["https://example.com/launch/2026/press-kit.pdf", 3, 312, 7],
  ["https://www.rfc-editor.org/rfc/rfc9110.html#name-redirection-3xx", 14, 57, 30],
  ["https://example.com/blog/how-we-picked-six-characters", 21, 903, 0],
];

export function seed(store, now = Date.now()) {
  for (const [url, age, clicks, days] of LINKS) {
    const link = store.create(url, { days, now: now - age * DAY });
    link.clicks = clicks;
  }
}
'''

SERVER = '''
// The dev server: the page from public/, the API under /api, and the short links themselves.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join } from "node:path";
import { LinkStore } from "./lib/links.js";
import { seed } from "./lib/seed.js";

const port = Number(process.env.PORT ?? 5173);
const links = new LinkStore();
seed(links);
const types = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml" };

function send(res, status, value) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(value));
}

async function body(req) {
  let text = "";
  for await (const chunk of req) text += chunk;
  return JSON.parse(text || "{}");
}

const server = createServer(async (req, res) => {
  const started = performance.now();
  const { pathname } = new URL(req.url, "http://localhost");
  try {
    if (pathname === "/api/links" && req.method === "GET") {
      send(res, 200, links.recent());
    } else if (pathname === "/api/links" && req.method === "POST") {
      const { url, days } = await body(req);
      send(res, 201, links.create(url, { days }));
    } else if (/^\\/[0-9a-zA-Z]{6}$/.test(pathname)) {
      const link = links.open(pathname.slice(1));
      res.writeHead(link ? 302 : 410, link ? { location: link.url } : {});
      res.end();
    } else {
      const file = join("public", pathname === "/" ? "index.html" : pathname);
      const data = await readFile(file);
      res.writeHead(200, { "content-type": types[extname(file)] ?? "text/plain" });
      res.end(data);
    }
  } catch (error) {
    send(res, error.code === "ENOENT" ? 404 : 400, { error: error.message });
  } finally {
    const ms = (performance.now() - started).toFixed(0);
    console.log(`  ${req.method.padEnd(5)} ${pathname.padEnd(16)} ${res.statusCode}  ${ms} ms`);
  }
});

server.listen(port, () => {
  console.log(`\\n  \\x1b[1mshortlink\\x1b[0m dev server\\n`);
  console.log(`  \\x1b[32m➜\\x1b[0m  Local:  \\x1b[36mhttp://localhost:${port}/\\x1b[0m`);
  console.log(`  \\x1b[32m➜\\x1b[0m  API:    \\x1b[36mhttp://localhost:${port}/api/links\\x1b[0m\\n`);
});
'''

INDEX = '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Links · shortlink</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <header>
    <a class="brand" href="/">shortlink</a>
    <nav><a href="/" class="here">Links</a><a href="/">Analytics</a><a href="/">Settings</a></nav>
  </header>
  <main>
    <div class="title"><h1>Links</h1><span id="total"></span></div>
    <form id="shorten">
      <input name="url" type="url" placeholder="Paste a long URL" aria-label="Long URL" required>
      <select name="days" aria-label="Expires"><option value="30">30 days</option><option value="7">7 days</option><option value="0">Never</option></select>
      <button>Shorten</button>
    </form>
    <ul id="links"></ul>
  </main>
  <script type="module" src="/app.js"></script>
</body>
</html>
'''

STYLE = '''
:root {
  --bg: #fbfbfa;
  --surface: #ffffff;
  --text: #1f2328;
  --muted: #656d76;
  --line: #e4e4e2;
  --accent: #1f6feb;
  --warn: #9a6700;
  font: 15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
  color-scheme: light;
}

* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); }
a { color: inherit; text-decoration: none; }

header {
  display: flex; flex-wrap: wrap; align-items: center; gap: 8px 24px;
  padding: 14px 24px; border-bottom: 1px solid var(--line);
}
.brand { font-weight: 600; letter-spacing: -0.01em; }
nav { display: flex; flex-wrap: wrap; gap: 4px 18px; font-size: 14px; color: var(--muted); }
nav .here { color: var(--text); }

main { max-width: 720px; margin: 0 auto; padding: 28px 24px 48px; }
.title { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 14px; }
h1 { margin: 0; font-size: 22px; font-weight: 600; letter-spacing: -0.015em; }
#total { color: var(--muted); font-size: 13px; font-variant-numeric: tabular-nums; }

form { display: flex; gap: 8px; margin-bottom: 20px; }
input, select, button { font: inherit; font-size: 14px; border-radius: 7px; }
input, select { border: 1px solid var(--line); background: var(--surface); color: var(--text); padding: 8px 10px; }
input { flex: 1; min-width: 0; }
select { color: var(--muted); }
button { border: 0; padding: 8px 14px; background: var(--text); color: var(--surface); font-weight: 500; cursor: pointer; }

ul { list-style: none; margin: 0; padding: 0; border-top: 1px solid var(--line); }
li {
  display: grid; grid-template-columns: minmax(0, 1fr) auto 96px; gap: 4px 20px; align-items: center;
  padding: 12px 2px; border-bottom: 1px solid var(--line);
}
.code { font-weight: 500; color: var(--accent); }
.url { margin-top: 2px; font-size: 13px; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.clicks { font-size: 13px; color: var(--muted); font-variant-numeric: tabular-nums; text-align: right; white-space: nowrap; }
.left { font-size: 13px; color: var(--muted); text-align: right; white-space: nowrap; }
.left.soon { color: var(--warn); }
.left.kept { color: var(--muted); }

/* A narrow window: the form stacks, each link puts its numbers under its address. */
@media (max-width: 560px) {
  header { padding: 12px 16px; }
  main { padding: 20px 16px 40px; }
  form { flex-wrap: wrap; }
  input { flex-basis: 100%; }
  select { flex: 1; }
  li { grid-template-columns: auto 1fr; }
  li > div { grid-column: 1 / -1; }
  .clicks, .left { text-align: left; }
}
'''

DARK = '''
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16171a;
    --surface: #1d1f23;
    --text: #e6e6e3;
    --muted: #9a9ea6;
    --line: #2b2d32;
    --accent: #6ea8fe;
    --warn: #d4a72c;
    color-scheme: dark;
  }
}

:root[data-theme="dark"] { color-scheme: dark; }
:root[data-theme="light"] { color-scheme: light; }

.theme {
  border: 1px solid var(--line); border-radius: 7px; padding: 3px 8px;
  background: transparent; color: var(--muted); font-size: 13px;
}
'''

APP = '''
// The page: recent links, and the form that makes a new one.
const list = document.querySelector("#links");
const DAY = 24 * 60 * 60 * 1000;

function left(link) {
  if (link.expiresAt === null) return `<span class="left kept">Never expires</span>`;
  const days = Math.ceil((link.expiresAt - Date.now()) / DAY);
  return `<span class="left${days <= 7 ? " soon" : ""}">${days} days left</span>`;
}

async function load() {
  const links = await (await fetch("/api/links")).json();
  document.querySelector("#total").textContent = `${links.length} links · ${links.reduce((n, l) => n + l.clicks, 0).toLocaleString()} clicks`;
  list.innerHTML = links.map((link) => `
    <li>
      <div><div class="code">sl.ink/${link.code}</div><div class="url">${link.url}</div></div>
      <span class="clicks">${link.clicks} clicks</span>
      ${left(link)}
    </li>`).join("");
}

document.querySelector("#shorten").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = new FormData(event.target);
  await fetch("/api/links", { method: "POST", body: JSON.stringify({ url: form.get("url"), days: Number(form.get("days")) }) });
  event.target.reset();
  load();
});

load();
'''

TESTS = '''
import { test } from "node:test";
import assert from "node:assert/strict";
import { DAY, LinkStore, makeCode } from "../lib/links.js";

test("a code has six letters or digits", () => {
  assert.match(makeCode(), /^[0-9a-zA-Z]{6}$/);
});

test("codes do not repeat", () => {
  const codes = new Set(Array.from({ length: 1000 }, () => makeCode()));
  assert.equal(codes.size, 1000);
});

test("a link opens its address and counts the click", () => {
  const store = new LinkStore();
  const link = store.create("https://example.com/a");
  assert.equal(store.open(link.code).url, "https://example.com/a");
  assert.equal(link.clicks, 1);
});

test("an unknown code opens nothing", () => {
  assert.equal(new LinkStore().open("zzzzzz"), null);
});

test("only web addresses are shortened", () => {
  assert.throws(() => new LinkStore().create("ftp://example.com"), /not a web address/);
});

test("recent links come newest first", () => {
  const store = new LinkStore();
  store.create("https://example.com/old", { now: 1 });
  store.create("https://example.com/new", { now: 2 });
  assert.deepEqual(store.recent().map((link) => link.url), ["https://example.com/new", "https://example.com/old"]);
});

test("a link expires after 30 days by default", () => {
  const store = new LinkStore();
  const link = store.create("https://example.com/a", { now: 0 });
  assert.equal(link.expiresAt, 30 * DAY);
  assert.equal(store.open(link.code, 30 * DAY), null);
});

test("an expired link counts no click", () => {
  const store = new LinkStore();
  const link = store.create("https://example.com/a", { days: 7, now: 0 });
  store.open(link.code, 8 * DAY);
  assert.equal(link.clicks, 0);
});

test("days: 0 keeps a link", () => {
  const store = new LinkStore();
  const link = store.create("https://example.com/a", { days: 0, now: 0 });
  assert.equal(store.open(link.code, 365 * DAY).url, "https://example.com/a");
});
'''

PACKAGE = '''
{
  "name": "shortlink",
  "version": "0.4.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "node server.js",
    "test": "node --test"
  }
}
'''

README = '''
# shortlink

A small link shortener: paste a long address, share a six-letter one.

```sh
npm run dev     # the page and the API on http://localhost:5173
npm test        # node's test runner, no dependencies
```

## API

| Method | Path | What it does |
|---|---|---|
| `GET` | `/api/links` | the ten newest links |
| `POST` | `/api/links` | makes a link: `{ "url": "…", "days": 30 }` |
| `GET` | `/<code>` | redirects, or `410 Gone` once the link expired |

Links expire after 30 days by default. `days: 0` keeps a link.
'''

INDEX_THEME = INDEX.replace(
    '<nav><a href="/" class="here">Links</a><a href="/">Analytics</a><a href="/">Settings</a></nav>',
    '<nav><a href="/" class="here">Links</a><a href="/">Analytics</a><a href="/">Settings</a>\n'
    '      <button class="theme" id="theme" title="Switch appearance">◐</button></nav>')

APP_THEME = APP + '''\

// The appearance follows the system until the toggle picks one; the choice is kept.
const theme = localStorage.getItem("theme");
if (theme) document.documentElement.dataset.theme = theme;
document.querySelector("#theme").addEventListener("click", () => {
  const dark = matchMedia("(prefers-color-scheme: dark)").matches;
  const next = (document.documentElement.dataset.theme ?? (dark ? "dark" : "light")) === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  localStorage.setItem("theme", next);
});
'''

repo("shortlink", [
    (24, 10, 0, "Initial commit", {"package.json": PACKAGE, ".gitignore": "node_modules/\n.DS_Store\n",
                                   "README.md": README.split("## API")[0]}),
    (23, 15, 0, "Add the link store with six-letter codes", {"lib/links.js": LINKS_V1}),
    (22, 11, 1, "Serve the page and the API", {"server.js": SERVER.replace("import { seed } from \"./lib/seed.js\";\n", "")
                                                .replace("seed(links);\n", ""), "public/index.html": INDEX,
                                                "public/style.css": STYLE}),
    (20, 16, 0, "Show recent links with their clicks", {"public/app.js": APP.replace("      ${left(link)}\n", "")}),
    (17, 9, 1, "Seed a few links in development", {"lib/seed.js": SEED.replace("import { DAY } from \"./links.js\";\n",
                                                                              "const DAY = 24 * 60 * 60 * 1000;\n"),
                                                  "server.js": SERVER}),
    (13, 14, 0, "Test the store with node's test runner", {"test/links.test.js": "\ntest(".join(TESTS.split("\ntest(")[:7])}),
    (8, 10, 1, "Document the API", {"README.md": README}),
    (1, 17, 0, "Expire links after 30 days by default", {"lib/links.js": LINKS, "lib/seed.js": SEED,
                                                         "public/app.js": APP, "test/links.test.js": TESTS}),
], uncommitted={"public/style.css": STYLE + "\n" + DARK, "public/index.html": INDEX_THEME, "public/app.js": APP_THEME})

# api: the Go service behind shortlink.dev, with a rate limit Codex just added (uncommitted).

GO_MAIN = '''
package main

import (
	"log"
	"net/http"
	"os"

	"example.com/api/internal/links"
)

func main() {
	addr := ":" + env("PORT", "8080")
	mux := http.NewServeMux()
	store := links.NewStore()
	mux.HandleFunc("GET /links", store.List)
	mux.HandleFunc("POST /links", store.Create)
	mux.HandleFunc("GET /{code}", store.Open)
	log.Printf("api listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
'''

GO_LINKS = '''
// Package links keeps short links and serves them over HTTP.
package links

import (
	"crypto/rand"
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

const alphabet = "0123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"

type Link struct {
	Code    string    `json:"code"`
	URL     string    `json:"url"`
	Clicks  int       `json:"clicks"`
	Created time.Time `json:"created"`
}

type Store struct {
	mu    sync.Mutex
	links map[string]*Link
}

func NewStore() *Store { return &Store{links: map[string]*Link{}} }

func code() string {
	b := make([]byte, 6)
	rand.Read(b)
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	return string(b)
}

func (s *Store) Create(w http.ResponseWriter, r *http.Request) {
	var body struct{ URL string }
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.URL == "" {
		http.Error(w, "a url is needed", http.StatusBadRequest)
		return
	}
	s.mu.Lock()
	link := &Link{Code: code(), URL: body.URL, Created: time.Now()}
	s.links[link.Code] = link
	s.mu.Unlock()
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(link)
}

func (s *Store) List(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	list := make([]*Link, 0, len(s.links))
	for _, link := range s.links {
		list = append(list, link)
	}
	json.NewEncoder(w).Encode(list)
}

func (s *Store) Open(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	link, ok := s.links[r.PathValue("code")]
	if ok {
		link.Clicks++
	}
	s.mu.Unlock()
	if !ok {
		http.NotFound(w, r)
		return
	}
	http.Redirect(w, r, link.URL, http.StatusFound)
}
'''

GO_LINKS_TEST = '''
package links

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCreateThenOpen(t *testing.T) {
	s := NewStore()
	rec := httptest.NewRecorder()
	s.Create(rec, httptest.NewRequest("POST", "/links", strings.NewReader(`{"url":"https://example.com"}`)))
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: %d", rec.Code)
	}
}

func TestCreateNeedsAURL(t *testing.T) {
	rec := httptest.NewRecorder()
	NewStore().Create(rec, httptest.NewRequest("POST", "/links", strings.NewReader(`{}`)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("got %d", rec.Code)
	}
}
'''

GO_LIMIT = '''
// Package ratelimit allows a number of requests per key in a sliding minute.
package ratelimit

import (
	"net/http"
	"strconv"
	"sync"
	"time"
)

type Limiter struct {
	mu    sync.Mutex
	limit int
	every time.Duration
	seen  map[string][]time.Time
	now   func() time.Time
}

func New(limit int, every time.Duration) *Limiter {
	return &Limiter{limit: limit, every: every, seen: map[string][]time.Time{}, now: time.Now}
}

// Allow records a request for key and says whether it fits, and if not, when the next one will.
func (l *Limiter) Allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	kept := l.seen[key][:0]
	for _, at := range l.seen[key] {
		if now.Sub(at) < l.every {
			kept = append(kept, at)
		}
	}
	if len(kept) >= l.limit {
		l.seen[key] = kept
		return false, l.every - now.Sub(kept[0])
	}
	l.seen[key] = append(kept, now)
	return true, 0
}

// Wrap answers 429 with Retry-After once a key goes over its limit.
func (l *Limiter) Wrap(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ok, wait := l.Allow(r.Header.Get("X-Api-Key"))
		if !ok {
			w.Header().Set("Retry-After", strconv.Itoa(int(wait.Seconds())+1))
			http.Error(w, "too many requests", http.StatusTooManyRequests)
			return
		}
		next(w, r)
	}
}
'''

GO_LIMIT_TEST = '''
package ratelimit

import (
	"testing"
	"time"
)

func TestTenAMinute(t *testing.T) {
	l := New(10, time.Minute)
	for i := 0; i < 10; i++ {
		if ok, _ := l.Allow("key"); !ok {
			t.Fatalf("request %d refused", i+1)
		}
	}
	if ok, wait := l.Allow("key"); ok || wait <= 0 {
		t.Fatalf("the 11th request: ok=%v wait=%v", ok, wait)
	}
}

func TestKeysAreSeparate(t *testing.T) {
	l := New(1, time.Minute)
	l.Allow("a")
	if ok, _ := l.Allow("b"); !ok {
		t.Fatal("b was limited by a")
	}
}

func TestAMinuteLater(t *testing.T) {
	now := time.Unix(0, 0)
	l := New(1, time.Minute)
	l.now = func() time.Time { return now }
	l.Allow("key")
	now = now.Add(61 * time.Second)
	if ok, _ := l.Allow("key"); !ok {
		t.Fatal("still limited after a minute")
	}
}
'''

repo("api", [
    (30, 11, 1, "Start the links service", {"go.mod": "module example.com/api\n\ngo 1.22\n",
                                            "main.go": GO_MAIN.replace('\tlog.Printf("api listening on %s", addr)\n', ""),
                                            "README.md": "# api\n\nThe service behind shortlink: `go run .`, then "
                                                         "`curl localhost:8080/links`.\n"}),
    (27, 15, 1, "Keep links in a store with six-letter codes", {"internal/links/links.go": GO_LINKS}),
    (19, 10, 0, "Test creating links", {"internal/links/links_test.go": GO_LINKS_TEST}),
    (6, 16, 1, "Log the address on start", {"main.go": GO_MAIN}),
], uncommitted={"internal/ratelimit/ratelimit.go": GO_LIMIT, "internal/ratelimit/ratelimit_test.go": GO_LIMIT_TEST,
                "main.go": GO_MAIN.replace('"example.com/api/internal/links"',
                                           '"example.com/api/internal/links"\n\t"example.com/api/internal/ratelimit"')
                .replace('mux.HandleFunc("POST /links", store.Create)',
                         'limit := ratelimit.New(10, time.Minute)\n\tmux.HandleFunc("POST /links", limit.Wrap(store.Create))')
                .replace('"os"\n', '"os"\n\t"time"\n')})

# docs: the user guide, which pi is writing a page of.

GETTING_STARTED = '''
# Getting started

shortlink turns a long address into a short one you can share anywhere. This guide takes about five minutes.

## Make your first link

1. Open **shortlink** and paste an address into the box.
2. Pick how long it lives: **30 days**, **7 days** or **Keep**.
3. Click **Shorten**. The new link shows at the top of **Links**, ready to copy.

> **Tip:** links that expire within a week show their time left in orange.

## Share it

A short link looks like `sl.ink/a8Kf2q`. Anyone who opens it goes straight to the long address, and the click
counts on your list.

## From the command line

```sh
npx linkctl create https://example.com/launch --days 7
```

| Command | What it does |
|---|---|
| `linkctl create <url>` | makes a link and copies it |
| `linkctl list` | your ten newest links |
| `linkctl stats <code>` | clicks per day for one link |

## Next

- [Custom domains](custom-domains.md): links on your own domain.
- [API reference](../reference/api.md): make links from your own code.
'''

DOMAINS = '''
# Custom domains

Links can use your own domain, such as `go.example.com/launch`, instead of `sl.ink`.

## Before you start

You need a domain you control and access to its DNS records.

## Add the domain

1. In **Settings ▸ Domains**, click **Add Domain** and type the domain.
2. Add the `CNAME` record that shortlink shows to your DNS:

   ```text
   go.example.com.  CNAME  edge.shortlink.dev.
   ```

3. Wait for the check to turn green. DNS can take up to an hour.
'''

docs = {"README.md": "# shortlink docs\n\nThe user guide and the API reference, in Markdown.\n",
        "guide/getting-started.md": GETTING_STARTED,
        "reference/api.md": "# API reference\n\nAll requests take and return JSON.\n\n## POST /api/links\n\n"
                            "```json\n{ \"url\": \"https://example.com/launch\", \"days\": 7 }\n```\n\n"
                            "Answers `201` with the new link. `days: 0` keeps it.\n",
        "changelog.md": "# Changelog\n\n## 0.4.0\n\n- Links expire after 30 days by default.\n- The page shows each "
                        "link's time left.\n\n## 0.3.0\n\n- The API reference.\n"}
repo("docs", [
    (26, 12, 1, "Start the docs", {"README.md": docs["README.md"]}),
    (18, 15, 0, "Write the getting started guide", {"guide/getting-started.md": GETTING_STARTED}),
    (8, 11, 1, "Document POST /api/links", {"reference/api.md": docs["reference/api.md"]}),
    (1, 18, 0, "Changelog for 0.4.0", {"changelog.md": docs["changelog.md"]}),
], uncommitted={"guide/custom-domains.md": DOMAINS})

# linkctl: the command line client, which OpenCode is getting ready to publish.

CHANGELOG = """
# Changelog

## 0.3.0

- `linkctl create <url> --days 7` sets how long a link lives; `--days 0` keeps it.
- `linkctl stats <code>` prints the clicks per day of one link.
- `linkctl list` shows the time left on each link.
- Errors from the API print their message instead of a stack trace.

## 0.2.0

- `linkctl list` prints the ten newest links.
- `SHORTLINK` points the client at another server, such as `http://localhost:5173`.

## 0.1.0

- `linkctl create <url>` makes a link and prints it.
"""

repo("linkctl", [
    (16, 10, 0, "Start linkctl", {"package.json": '{\n  "name": "linkctl",\n  "version": "0.2.0",\n  "type": "module",\n'
                                                  '  "bin": { "linkctl": "dist/index.js" },\n  "scripts": { "build": '
                                                  '"tsc", "test": "node --test dist" }\n}\n',
                                  "README.md": "# linkctl\n\nshortlink from the command line.\n",
                                  "src/index.ts": 'import { create } from "./create.js";\nimport { list } from '
                                                  '"./list.js";\n\nconst [command, ...rest] = process.argv.slice(2);\n'
                                                  'const commands = { create, list };\nawait (commands[command] ?? '
                                                  'list)(rest);\n'}),
    (12, 14, 0, "Add create and list", {"src/create.ts": 'export async function create([url]: string[]) {\n  const res '
                                                         '= await fetch(`${process.env.SHORTLINK ?? "https://sl.ink"}'
                                                         '/api/links`, { method: "POST", body: JSON.stringify({ url }) '
                                                         '});\n  const link = await res.json();\n  console.log(`sl.ink/'
                                                         '${link.code}`);\n}\n',
                                        "src/list.ts": 'export async function list() {\n  const res = await fetch(`${'
                                                       'process.env.SHORTLINK ?? "https://sl.ink"}/api/links`);\n  for '
                                                       '(const link of await res.json()) console.log(link.code, '
                                                       'link.url);\n}\n'}),
    (3, 11, 1, "Prepare 0.3.0", {"CHANGELOG.md": CHANGELOG}),
])

# notes: plans and meeting notes in Markdown.

ROADMAP = '''
# Roadmap

## This month
- [x] Links expire after 30 days by default
- [x] Time left on each link
- [ ] Dark mode on the page
- [ ] Rate limit the API: 10 new links a minute per key
- [ ] Custom domains guide

## Next
- [ ] Analytics: clicks per day, per country
- [ ] QR codes for each link
- [ ] Teams: shared links and roles

## Open questions
- Should a kept link still expire after a year without clicks?
- Six letters gives 42 billion codes. Enough, or plan for seven?
'''

repo("notes", [
    (20, 9, 0, "Notes", {"README.md": "# notes\n\nPlans and meeting notes.\n"}),
    (9, 16, 0, "Roadmap for this month", {"roadmap.md": ROADMAP.replace("- [x] Links", "- [ ] Links")
                                          .replace("- [x] Time", "- [ ] Time")}),
    (2, 10, 0, "Weekly sync", {"meetings/weekly-sync.md": "# Weekly sync\n\n- Expiry ships in 0.4.0.\n- Dark mode "
                                                          "next, then the rate limit.\n- Docs: a guide for custom "
                                                          "domains.\n"}),
], uncommitted={"roadmap.md": ROADMAP})

# The agents' turns, by agent and prompt: each step's `secs` is how long it took (the lines are dated back from now).
# Claude Code's and pi's paths are absolute, as theirs are, under the real folder (the chat shows them from the cwd).
real = os.path.realpath(root)


def lines(text):
    return text.lstrip("\n").splitlines()


def patch(old, new):
    """Claude Code's structuredPatch of an edit: its hunks with three lines around each change."""
    a, b = lines(old), lines(new)
    hunks = []
    for group in difflib.SequenceMatcher(None, a, b).get_grouped_opcodes(3):
        body = []
        for tag, i1, i2, j1, j2 in group:
            body += [" " + line for line in a[i1:i2]] if tag == "equal" else \
                ["-" + line for line in a[i1:i2]] + ["+" + line for line in b[j1:j2]]
        first = group[0]
        hunks.append({"oldStart": first[1] + 1, "oldLines": group[-1][2] - first[1], "newStart": first[3] + 1,
                      "newLines": group[-1][4] - first[3], "lines": body})
    return hunks


def unified(old, new, path):
    return "".join(difflib.unified_diff(*(t.lstrip("\n").splitlines(True) for t in (old, new)), "a/" + path,
                                        "b/" + path))


def read(repo, path, text, secs=1):
    full = f"{real}/{repo}/{path}"
    body = lines(text)
    return {"tool": "Read", "input": {"file_path": full}, "secs": secs,
            "output": "\n".join(f"{n:6}→{line}" for n, line in enumerate(body, 1)),
            "result": {"type": "text", "file": {"filePath": full, "content": "\n".join(body), "numLines": len(body),
                                                "startLine": 1, "totalLines": len(body)}}}


def edit(repo, path, old, new, secs=3):
    full = f"{real}/{repo}/{path}"
    hunks = patch(old, new)
    removed = [line[1:] for h in hunks for line in h["lines"] if line[0] in " -"]
    added = [line[1:] for h in hunks for line in h["lines"] if line[0] in " +"]
    return {"tool": "Edit", "input": {"file_path": full, "old_string": "\n".join(removed),
                                      "new_string": "\n".join(added)}, "secs": secs,
            "output": f"The file {full} has been updated.",
            "result": {"filePath": full, "oldString": "\n".join(removed), "newString": "\n".join(added),
                       "structuredPatch": hunks}}


NPM_TEST = """
> shortlink@0.4.0 test
> node --test

✔ a code has six letters or digits (0.61ms)
✔ codes do not repeat (2.84ms)
✔ a link opens its address and counts the click (0.12ms)
✔ an unknown code opens nothing (0.05ms)
✔ only web addresses are shortened (0.31ms)
✔ recent links come newest first (0.09ms)
✔ a link expires after 30 days by default (0.07ms)
✔ an expired link counts no click (0.06ms)
✔ days: 0 keeps a link (0.05ms)
ℹ tests 9
ℹ pass 9
ℹ fail 0
ℹ duration_ms 96.4"""

TESTS_V1 = "\ntest(".join(TESTS.split("\ntest(")[:7])
EXPIRY_REPLY = """Links expire now. A new link lives **30 days** unless you pick another time, and `days: 0` keeps it.

- **lib/links.js**: `create` stores `expiresAt`, and `open` refuses an expired code, so it counts no click.
- **server.js**: an expired code answers `410 Gone` instead of redirecting.
- **public/app.js**: each link shows its time left, in orange for the last week.

```js
const link = store.create(url, { days: 7 });
store.open(link.code); // null after 7 days
```

All 9 tests pass, 3 of them new. Reload the browser card to see the time left on each link."""

claude = {
    "Links should expire. Add an expiry to each link, 30 days by default, show the time left on the page, and keep "
    "the tests green.": {"model": "claude-opus-4-5", "steps": [
        {"text": "I'll look at how links are stored and served first.", "secs": 4},
        read("shortlink", "lib/links.js", LINKS_V1),
        read("shortlink", "server.js", SERVER),
        {"tool": "Grep", "input": {"pattern": "open\\(|recent\\(", "output_mode": "files_with_matches"}, "secs": 1,
         "output": "Found 3 files\nserver.js\npublic/app.js\nlib/links.js",
         "result": {"mode": "files_with_matches", "numFiles": 3,
                    "filenames": ["server.js", "public/app.js", "lib/links.js"]}},
        read("shortlink", "test/links.test.js", TESTS_V1),
        {"text": "Links carry no time yet. I'll add `expiresAt` to the store, refuse expired codes in `open`, and "
                 "show the days left in the list.", "secs": 9},
        edit("shortlink", "lib/links.js", LINKS_V1, LINKS, secs=21),
        edit("shortlink", "public/app.js", APP.replace("      ${left(link)}\n", ""), APP, secs=13),
        edit("shortlink", "test/links.test.js", TESTS_V1, TESTS, secs=17),
        {"tool": "Bash", "input": {"command": "npm test", "description": "Run the tests"}, "secs": 6,
         "output": NPM_TEST.strip()},
        {"text": EXPIRY_REPLY, "secs": 7},
    ]},
    "Add a dark mode that follows the system, with a toggle in the header that remembers the choice.": {
        "model": "claude-opus-4-5", "working": True, "steps": [
            {"text": "I'll start with the page's colors: they are all custom properties, so dark mode is one block.",
             "secs": 5},
            read("shortlink", "public/style.css", STYLE),
            read("shortlink", "public/index.html", INDEX),
            edit("shortlink", "public/style.css", STYLE, STYLE + "\n" + DARK, secs=14),
            edit("shortlink", "public/index.html", INDEX, INDEX_THEME, secs=6),
            {"text": "The colors follow the system now. Next, the toggle: it sets `data-theme` on the page and keeps "
                     "the choice in `localStorage`.", "secs": 8},
            edit("shortlink", "public/app.js", APP, APP_THEME, secs=11),
            {"tool": "Bash", "input": {"command": "npm test", "description": "Run the tests"}, "secs": 2},
        ]},
}

GO_MAIN_LIMIT = GO_MAIN.replace('"example.com/api/internal/links"',
                                '"example.com/api/internal/links"\n\t"example.com/api/internal/ratelimit"') \
    .replace('mux.HandleFunc("POST /links", store.Create)',
             'limit := ratelimit.New(10, time.Minute)\n\tmux.HandleFunc("POST /links", limit.Wrap(store.Create))') \
    .replace('"os"\n', '"os"\n\t"time"\n')


def shell(script, output, secs, read_path=None):
    parsed = [{"type": "read", "cmd": script, "name": os.path.basename(read_path), "path": read_path}] \
        if read_path else [{"type": "unknown", "cmd": script}]
    return {"type": "CommandExecution", "secs": secs, "command": ["/bin/zsh", "-lc", script], "parsed_cmd": parsed,
            "status": "completed", "aggregated_output": output, "exit_code": 0,
            "duration": {"secs": int(secs), "nanos": int(secs % 1 * 1e9)}}


codex = {
    "Rate limit POST /links to 10 a minute per API key. Over the limit, answer 429 with Retry-After.": {
        "model": "gpt-5.1-codex", "steps": [
            {"type": "AgentMessage", "content": [{"type": "Text", "text": "I'll find where the routes are set up."}],
             "phase": "commentary", "secs": 6},
            shell('rg -n "HandleFunc" .', './main.go:17:\tmux.HandleFunc("GET /links", store.List)\n'
                  './main.go:18:\tmux.HandleFunc("POST /links", store.Create)\n'
                  './main.go:19:\tmux.HandleFunc("GET /{code}", store.Open)\n', 1),
            shell("sed -n '1,80p' main.go", GO_MAIN.lstrip("\n"), 1, "main.go"),
            shell("sed -n '1,120p' internal/links/links.go", GO_LINKS.lstrip("\n"), 1, "internal/links/links.go"),
            {"type": "AgentMessage", "content": [{"type": "Text", "text":
             "A sliding minute per key needs no dependency. I'll add `internal/ratelimit` and wrap only "
             "`POST /links`, so reads stay free."}], "phase": "commentary", "secs": 14},
            {"type": "FileChange", "status": "completed", "secs": 22, "changes": {
                "internal/ratelimit/ratelimit.go": {"type": "add", "content": GO_LIMIT.lstrip("\n")},
                "internal/ratelimit/ratelimit_test.go": {"type": "add", "content": GO_LIMIT_TEST.lstrip("\n")},
                "main.go": {"type": "update", "unified_diff": unified(GO_MAIN, GO_MAIN_LIMIT, "main.go")}}},
            shell("gofmt -l . && go vet ./...", "", 4),
            shell("go test ./...", "?   \texample.com/api\t[no test files]\nok  \texample.com/api/internal/links"
                  "\t0.214s\nok  \texample.com/api/internal/ratelimit\t0.187s\n", 9),
            {"type": "AgentMessage", "phase": "final_answer", "secs": 6, "content": [{"type": "Text", "text":
             "`POST /links` is limited to **10 requests a minute** per `X-Api-Key`. The 11th gets `429 Too Many "
             "Requests` with `Retry-After` in seconds.\n\n- `internal/ratelimit`: a sliding window per key, with "
             "its clock as a field so the tests need no sleep.\n- `main.go`: only `POST /links` is wrapped; reading "
             "and opening links stay unlimited.\n\n`go vet` is clean and the tests pass, 3 of them new. Not "
             "committed yet."}]},
        ]},
}

pi = {
    "Write the custom domains guide: adding the domain, the DNS record, checking it, and what to do when the check "
    "fails.": {"model": "claude-sonnet-4-5", "working": True, "steps": [
        {"tool": "read", "arguments": {"path": f"{real}/docs/guide/getting-started.md"}, "secs": 1,
         "output": GETTING_STARTED.lstrip("\n")},
        {"tool": "read", "arguments": {"path": f"{real}/docs/reference/api.md"}, "secs": 1,
         "output": docs["reference/api.md"]},
        {"text": "I'll follow the getting started guide's shape: numbered steps, one record to copy, then the "
                 "check.", "secs": 7},
        {"tool": "write", "arguments": {"path": f"{real}/docs/guide/custom-domains.md", "content": DOMAINS.lstrip()},
         "secs": 16, "output": "Wrote 21 lines to guide/custom-domains.md"},
        {"text": "The first half is written. Now the part for when the check fails: the three errors it can show "
                 "and what fixes each.", "secs": 6},
        {"tool": "edit", "arguments": {"path": f"{real}/docs/guide/custom-domains.md",
                                       "edits": [{"oldText": "DNS can take up to an hour.",
                                                  "newText": "DNS can take up to an hour.\n\n## When the check fails"}]},
         "secs": 2},
    ]},
}

for turns in (claude, codex, pi):
    for turn in turns.values():
        turn["secs"] = sum(step.get("secs", 2) for step in turn["steps"])
with open(sys.argv[2], "w") as file:
    json.dump({"claude": claude, "codex": codex, "pi": pi}, file, indent=1)
