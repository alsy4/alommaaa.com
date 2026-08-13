---
title: "CI/CD With GitHub Actions"
date: 2026-08-13
description: "Push to main, site goes live. OIDC instead of access keys, and why the CDN cache has to be invalidated"
tags: ["cicd", "github-actions", "aws"]
draft: false
projects:
  - alome-website
---

At this point the infrastructure exists and the site builds. What's missing
is the part where those two facts meet without me typing anything.

The manual version is four commands: build, sync, invalidate, and hope you
remembered all three of the last ones. It works right up until the evening
you're tired, you run the sync, you skip the invalidation, and then spend
twenty minutes convinced the deploy is broken because the new post isn't
showing up.

So the whole thing lives in `.github/workflows/deploy.yml` and runs itself.

## The pipeline

Push to `main`. Six steps, one job, about ninety seconds.

```
push to main
     |
     v
  checkout        pull the repo
     |
     v
  setup node      node 22, restore the npm cache
     |
     v
  npm ci          install exactly what the lockfile says
     |
     v
  npm run build   astro -> dist/
     |
     v
  aws creds       swap a GitHub OIDC token for a temporary AWS role
     |
     v
  s3 sync         upload dist/, delete what's no longer there
     |
     v
  invalidate      tell CloudFront to drop its cached copies
```

The trigger:

```yaml
on:
  push:
    branches:
      - main
  workflow_dispatch: {}
```

`workflow_dispatch` adds a manual "Run workflow" button. It's two lines and
it means I can force a redeploy without pushing an empty commit, which is
worth having the first time something goes sideways.

### npm ci, not npm install

Small thing, real difference. `npm install` will happily resolve a newer
version that matches your semver range and quietly update the lockfile.
`npm ci` installs exactly what's in `package-lock.json`, fails if the
lockfile and `package.json` disagree, and wipes `node_modules` first.

CI should build the same thing today that it built last week. `npm ci` is
how you get that.

## No AWS keys anywhere

This is the part I'd point at if someone asked what I learned building this.

The obvious way to give a CI runner AWS access is to make an IAM user,
generate an access key and secret, and paste them into repository secrets.
Loads of tutorials still do it that way. It works.

It's also a long-lived credential sitting in a third party's system with no
expiry, which will still be valid in two years when you've forgotten it
exists. If it leaks, it stays valid until someone notices and rotates it.

The alternative is OIDC federation. GitHub mints a short-lived signed token
describing the workflow run. AWS is configured to trust GitHub as an
identity provider, checks the token's claims, and hands back temporary
credentials that expire in an hour.

Nothing is stored. There is no key to leak.

Is it secured enough?

Maybe

### The trust policy is where it gets strict

On the AWS side, the role's trust policy decides who's allowed to do that
exchange. From `terraform/iam.tf`:

```hcl
Condition = {
  StringEquals = {
    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
  }
  StringLike = {
    "token.actions.githubusercontent.com:sub" = "repo:${owner}@${owner_id}/${repo}@${repo_id}:ref:refs/heads/${var.github_branch}"
  }
}
```

The `sub` claim describes exactly which workflow is asking. Pinning it
means:

- only this repository can assume the role
- only pushes to **this branch** can, so a pull request from a fork can't
  open a workflow that grabs my credentials
- getting the condition wrong fails closed, not open


Using this format does require configuring the subject claim template on the
GitHub side. If it's on the default, the claim looks like
`repo:owner/repo:ref:refs/heads/main` and you pin that instead.

### The role can do almost nothing

Least privilege, spelled out. The entire deploy policy:

```hcl
{
  Sid    = "S3Sync"
  Effect = "Allow"
  Action = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
  Resource = [
    aws_s3_bucket.site.arn,
    "${aws_s3_bucket.site.arn}/*",
  ]
},
{
  Sid      = "CloudFrontInvalidation"
  Effect   = "Allow"
  Action   = ["cloudfront:CreateInvalidation"]
  Resource = aws_cloudfront_distribution.site.arn
}
```

Three S3 actions on one bucket, and one CloudFront action on one
distribution. That's it.

If this role were somehow compromised, the worst available outcome is
defacing a blog I can rebuild with `npm run build && aws s3 sync`. It cannot
read other buckets, cannot touch IAM, cannot spin up an EC2 instance to mine
crypto on my card. Worth noting `s3:GetObject` isn't in there either,
because `sync` compares metadata via `ListBucket` and never needs to read
object contents.

Compare that to the default instinct of attaching `AmazonS3FullAccess` and
moving on.

## The sync

```yaml
- name: Sync to S3
  run: aws s3 sync ./dist "s3://${{ secrets.AWS_S3_BUCKET }}" --delete
```

`aws s3 sync` compares source and destination and only uploads what differs,
by size and modification time. On a typical deploy where I've added one post,
that's a handful of files rather than the whole site.

`--delete` is the important flag. Without it, S3 accumulates every file the
site has ever had. Rename a post and the old URL keeps working forever,
serving content that no longer exists in the repo, and getting itself
indexed by search engines. The bucket should mirror `dist/` exactly, not be
a graveyard of every build.

The flip side, and it's worth being aware of: `--delete` means a build that
somehow produces an empty `dist/` will wipe the live site. The protection
here is that `npm run build` failing stops the workflow before it reaches
this step. Astro exits non-zero on a broken frontmatter schema or a bad
project reference, and GitHub Actions stops the job at the first failing
step, so an unbuildable commit never reaches the sync.

## Why the cache has to be invalidated

This is the step people leave out, and the reason it's needed isn't obvious
until it bites you.

**CloudFront doesn't know you deployed.** That's the whole thing. Nothing
about writing an object to S3 notifies the CDN. The edge locations are
sitting on copies they fetched earlier and they'll keep serving those copies
until their TTL expires. From the edge's point of view nothing has changed,
because from the edge's point of view nothing *has* changed.

How long is that? The distribution uses the managed `CachingOptimized`
policy, which respects `Cache-Control` headers from the origin and falls
back to a default TTL of 24 hours when there aren't any. S3 doesn't set
`Cache-Control` on objects unless you tell it to, and `aws s3 sync` doesn't
add one by default.

So: **up to a day of serving the old page.** Publish a post, tell someone
about it, watch them not see it.

It gets worse than just being slow. There are hundreds of edge locations and
they all cache and expire independently. Someone in London hits an edge that
happened to fetch after the deploy and sees the new post. Someone in
Singapore hits one that cached an hour before and doesn't. Same URL, two
different sites, no pattern. That's the kind of bug you can't reproduce by
refreshing, because your own browser is talking to a third edge with its own
opinion.

And it's the *stable* URLs that suffer most. Every new post rewrites
`/index.html`, the blog listing, the sitemap. Those paths never change, so
they're precisely the ones an edge already has cached. The new post's own
URL is fine, since nothing has ever requested it. It's the front page
linking to it that's stale, which means the post is live and unreachable.

An invalidation tells CloudFront to mark cached objects as expired, so the
next request for each path goes back to S3.

```yaml
- name: Invalidate CloudFront cache
  run: |
    aws cloudfront create-invalidation \
      --distribution-id "${{ secrets.AWS_CLOUDFRONT_DISTRIBUTION_ID }}" \
      --paths "/*"
```

### Why `/*` and why it's free

`/*` invalidates everything. It looks wasteful and it's the right call here.

AWS gives you 1,000 invalidation paths per month free. The billing detail
that matters: **a wildcard counts as one path.** `/*` is one, not one per
file. One deploy is one path, so thirty deploys a month uses 30 of the 1,000
and costs nothing.

Being surgical would mean listing changed files, and every listed file
counts separately. Invalidating forty individual paths burns forty of the
allowance to achieve the same result as one wildcard. The blunt instrument
is both simpler and cheaper.

The cost of `/*` is cache misses. The next request to each edge for each path
goes back to S3, so there's a brief window of slower responses. For a few
megabytes of static files this is nothing, and S3 requests are billed in
fractions of a cent.

### Why it's in the pipeline rather than a note somewhere

Because a deploy that needs a manual follow-up step is a deploy that will one
day not get it.

Sync and invalidate are one operation split across two APIs. Half of it
leaves the site in a state where the files are correct and what people see
isn't. Anything that must happen every single time belongs in the automation,
not in your memory of how the automation works.


## Where that leaves it

```bash
nvim src/content/blog/website/04-github-actions.md
git add -A && git commit -m "new post" && git push
```

Ninety seconds later it's on a CDN, on my domain, over TLS, out of a bucket
nobody can read directly, with the cache cleared, using credentials that
expired before I finished making tea.

Which is roughly what I wanted when I started: the writing and choosing which `.gif` to include is the hard part
again, and nothing else is.

