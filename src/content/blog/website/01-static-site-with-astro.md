---
title: "Building a Static Site With Astro"
date: 2026-08-13
description: "Why a static site generator, and why Astro specifically"
tags: ["astro", "web"]
draft: false
projects:
  - alome-website
---

Every time I sat down to start a personal site I ended up in the same hole.
Pick a framework, spend a weekend on the theme, write two posts, never touch
it again. The writing was never the hard part. The friction around the
writing was.

So this time I picked based on one question: what happens between "I have a
thought" and "the thought is live". If the answer involves anything other
than opening a file in neovim and typing, it's the wrong tool.

## Why Astro

I looked at Hugo, Eleventy, and Next.

Hugo is fast and I have nothing bad to say about it, but Go templates and I
have never gotten along. Next is a React app pretending to be a blog when I
need a blog pretending to be nothing. Eleventy was close. Although I am learning Go at the moment, better just to tone it down with TypeScript for now.

Astro won on a few things.

### It renders markdown properly

GitHub flavoured markdown works out of the box. Tables, task lists, fenced
code blocks, footnotes. I write markdown all day in READMEs and notes, so
there was nothing new to learn.

### Code blocks are highlighted at build time

This is the big one for me. Syntax highlighting is normally a client-side
JS bundle that runs on every page load, re-parses code the server already
knew about, and flashes unstyled text before it kicks in.

Astro ships with [Shiki](https://shiki.style/), which runs at build time.
A fence like this:

```go
func main() {
    fmt.Println("hello")
}
```

comes out the other side as HTML with the colours already applied. Zero
bytes of JavaScript. Configured once in `astro.config.mjs`:

```js
markdown: {
  shikiConfig: { theme: "vitesse-dark" },
}
```


### Math actually works

My final year project involved writing out a lot of equations, and I got
very used to typing LaTeX. I wanted that here too.


Same principle as the code blocks. KaTeX runs during `npm run build`, not
in your browser. The reader gets HTML and a stylesheet.

So typing this:

```latex
$$
\mathcal{L} = -\frac{1}{N}\sum_{i=1}^{N} y_i \log(\hat{y}_i)
$$
```

will result in this:
$$
\mathcal{L} = -\frac{1}{N}\sum_{i=1}^{N} y_i \log(\hat{y}_i)
$$


and I can go back to writing the sentence I was in the middle of. Thank you FYP.

## Content collections

The part I didn't expect to like this much.

Astro lets you declare a schema for your content and validates every file
against it at build time. Here's the real one from `src/content.config.ts`:

```ts
const blog = defineCollection({
  loader: glob({ pattern: "**/*.{md,mdx}", base: "./src/content/blog" }),
  schema: z.object({
    title: z.string(),
    date: z.coerce.date(),
    description: z.string(),
    tags: z.array(z.string()).default([]),
    draft: z.boolean().default(false),
    updated: z.coerce.date().optional(),
    projects: z.array(reference("projects")).default([]),
  }),
});
```

Misspell a frontmatter key, forget a description, typo a date, and the
build fails with the file name and the field. It doesn't quietly publish a
post with a blank title.

This is actually good to escape those *metadata hell* since everything is stored in the frontmatter.

## The actual writing loop

Which is what I optimised for in the first place.

```bash
nvim src/content/blog/website/01-static-site-with-astro.md
npm run dev      # localhost:4321, hot reloads on save
git add -A && git commit -m "new post" && git push
```

Push to `main`, and about ninety seconds later it's live. Post four covers
how. There's no CMS, no admin panel, no "publish" button. `git push` is the
publish button.

Setting `draft: true` in the frontmatter keeps a post out of the build
entirely, so half-finished thoughts can sit in the repo without leaking.

## It's just files in git

Two side effects of this that I didn't plan for but ended up mattering.

Everything is plain text in a git repo, so my homelab can clone it like any
other repo. There's no database to dump, no export step, no proprietary
format holding my writing hostage. If AWS disappeared tomorrow I'd still
have every post, and pointing them at a different host means changing where
`dist/` gets copied to.

The other one: markdown is what language models read natively. When I paste
a post into an LLM to check whether an explanation holds up, it reads the
same file I wrote. No stripping nav bars, no fighting a rendered DOM to get
at the text. The source of truth is already the format that's easiest to
parse, for me and for anything else that wants to read it.

## What it costs you

Astro's own component syntax (`.astro` files) is another thing to learn if
you want to touch the layouts. I did, because I wanted the terminal look and
nobody's theme was going to give me that. It's close enough to JSX that it
clicked in an afternoon, but it's not nothing.

And static means static. If I ever want comments or search across posts,
that's either a third-party service or a small island of JavaScript. I've
decided I want neither for now, and that's the whole point of picking this
end of the tradeoff.

[Next post](/blog/website/02-deploying-on-aws/): getting `dist/` onto the
internet with S3, CloudFront and Route 53.
