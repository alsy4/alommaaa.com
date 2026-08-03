# alome-website

A personal blog/portfolio styled as a Unix/terminal interface — monospace, minimal, dark-first,
compiled entirely to static HTML with zero client-side JavaScript by default.

## Stack

- **Astro** (static output, no SSR adapter) — content in `.md`/`.mdx` via content collections
- **Shiki** for code highlighting, built into Astro's markdown pipeline (build-time, no client JS)
- **remark-math** + **rehype-katex** for LaTeX math, rendered to static HTML at build time
  (`katex` is a dependency only for its CSS — no KaTeX JS ships to the browser)
- **@astrojs/mdx**, **@astrojs/sitemap**
- Hand-written CSS (no framework) — system monospace font stack, CSS custom properties for theming
- TypeScript, `astro/tsconfigs/strict`

## Project structure

```
/
├── public/                  static assets (favicon, etc.)
├── src/
│   ├── content.config.ts    blog collection schema (Content Layer API)
│   ├── content/blog/        Markdown/MDX posts
│   ├── layouts/             Layout.astro (root shell), BlogPost.astro (article chrome)
│   ├── components/          Header, Footer, PostList
│   ├── pages/                index, about, blog/[...slug]
│   └── styles/global.css    terminal theme (dark palette, monospace, focus states)
└── astro.config.mjs
```

Note: the content collection schema lives at `src/content.config.ts`, not the older
`src/content/config.ts` — Astro 7 removed that legacy location.

## Writing a post

Add a Markdown file under `src/content/blog/`, e.g. `src/content/blog/my-post.md`:

```yaml
---
title: "Post title"
date: 2026-08-04
description: "One-line summary."
tags: ["tag1", "tag2"]
draft: false
---
```

Inline math (`$x^2$`), block math (`$$...$$`), and fenced code blocks (` ```rust `, ` ```go `, etc.)
render fully at build time — no client-side MathJax or syntax highlighter is loaded.

## Commands

| Command           | Action                                      |
| :----------------- | :------------------------------------------- |
| `npm install`       | Install dependencies                         |
| `npm run dev`       | Start local dev server at `localhost:4321`   |
| `npm run build`     | Build the static site to `./dist/`           |
| `npm run preview`   | Preview the production build locally         |
| `npm run check`     | Run `astro check` (type checking)            |

## Deployment (target shape)

Static output in `./dist` is intended to be synced to an S3 bucket (locked down via Origin
Access Control) and served through CloudFront. The GitHub Actions CI/CD pipeline for this has
not been added yet — see `CLAUDE.md` for the planned shape.
