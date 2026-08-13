---
title: "This Website"
description: "Building and deploying alommaaa.com with Astro, AWS, Terraform and GitHub Actions"
date: 2026-08-13
status: "active"
draft: false
---

# Intro

The site you are reading this on.

I wanted somewhere to dump what I learn, and I wanted the thing itself to be
worth writing about. So instead of pointing a domain at Vercel and calling
it a day, I built the whole path from markdown file to CDN edge myself.

The stack, roughly:

- **Astro** turns markdown into static HTML at build time
- **S3** stores the built files
- **CloudFront** serves them from edge locations over TLS
- **Route 53** points the domain at CloudFront
- **Terraform** declares all of the above so it can be torn down and rebuilt
- **GitHub Actions** builds and ships on every push to `main`

Four posts, one per layer. Written in the order I actually built them, which
means the mistakes are in there too.
