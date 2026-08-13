---
title: "Terraform for the Whole Stack"
date: 2026-08-13
description: "Why the infrastructure is declared in code instead of clicked into existence"
tags: ["terraform", "aws", "iac"]
draft: false
projects:
  - alome-website
---

I had the AWS setup from the last post working through the console. Bucket
made, distribution made, cert validated, DNS pointed. It served the site
fine.

Then I went to change one thing and realised I could not remember which of
the five services I needed to touch, or why I'd set half the options the way
I had. There was no record of any of it anywhere except in my head, and my
head is not a durable storage medium.

So I tore it all down and wrote it as Terraform.

## The NixOS thing

This is going to sound familiar if you've read [the NixOS
posts](/blog/nixos/01-what-is-nixos/).

NixOS made me describe my entire machine in a file. Packages, services,
kernel parameters, users. You don't install things, you declare that they
exist and rebuild until reality matches the file. After a year of that,
going back to clicking through a web console to build infrastructure felt
genuinely wrong. Same disease, different layer.

Terraform is the same idea pointed at a cloud provider. You write down what
should exist, it works out what does exist, and it makes up the difference.
Nix calls that a rebuild, Terraform calls it an apply, but it's the same
loop: **declare desired state, converge on it, repeat.**

Once that clicks in one place you start wanting it everywhere.

## So why Terraform specifically

A few reasons, in the order I actually felt them.

### It works out the ordering for me

This is the one that sold me, and it's easy to miss until you've done it by
hand.

Look at what has to happen for this stack to come up:

1. The S3 bucket has to exist before CloudFront can point at it as an
   origin.
2. The ACM certificate has to be requested before you know which DNS records
   validate it.
3. Those records have to exist in Route 53 before the cert is issued.
4. The cert has to be **issued** before CloudFront will accept it.
5. The distribution has to exist before the bucket policy can name its ARN
   in the `SourceArn` condition.
6. The distribution has to exist before Route 53 can alias to it.

Six steps, strict order, and step 3 to 4 involves waiting on something
outside your control. Get it wrong in the console and the error doesn't
explain the ordering.

I never wrote that sequence down anywhere. Terraform derives it from the
fact that `cloudfront.tf` references
`aws_s3_bucket.site.bucket_regional_domain_name` and `s3.tf` references
`aws_cloudfront_distribution.site.arn`. It builds a dependency graph out of
the references and walks it in the right order, waiting where it needs to.

Note that steps 1, 5 and 6 look circular. Bucket, then distribution, then a
policy on the bucket. It works because the policy is its own resource rather
than a field inside the bucket, so the graph stays acyclic. Splitting
resources to break cycles like that is a real Terraform design skill.

### Nothing gets copy-pasted twice

The bucket name appears in the bucket, the bucket policy, the CloudFront
origin, and the IAM deploy policy. The distribution ID appears in the
CloudFront resource and in the GitHub Actions workflow. The domain appears
in ACM, in the distribution aliases, in four DNS records, and in the IAM
role name.

Every one of those is derived, not typed:

```hcl
locals {
  bucket_name = coalesce(var.bucket_name, var.domain_name)
}
```

Change `domain_name` in one place and the whole stack follows. In the
console, each of those is a chance to typo something and then spend an hour
finding out where.

### I can destroy it and it's actually gone

`terraform destroy` removes everything it created. All of it, in reverse
dependency order.

That sounds destructive but it's what makes experimenting safe. I rebuilt
this stack from scratch several times while working out the OAC policy. No
half-deleted distributions sitting around, no orphaned hosted zone quietly
billing me fifty cents a month for a domain I stopped using. If it isn't in
the state file, I didn't create it.

The console version of this is going through five services trying to
remember what you made. You always miss something.

### The code is the documentation

I could write a runbook explaining that the ACM certificate lives in
us-east-1 and the S3 bucket blocks all public access. Runbooks go stale the
moment someone changes something and doesn't update the doc.

The `.tf` files can't go stale, because they're what built the thing. And
where a decision needs explaining, the comment sits directly on it:

```hcl
# ACM certs for CloudFront must be requested in us-east-1.
resource "aws_acm_certificate" "this" {
  provider = aws.us_east_1
  ...
}
```

```hcl
# S3 returns 403 (not 404) for missing keys when locked down via OAC.
custom_error_response {
  error_code    = 403
  response_code = 404
}
```

Six months from now when I wonder why there's a 403 mapping in there, the
answer is on the line above it. Honestly, half of this blog series is just
me reading my own Terraform back.

### Infrastructure gets git history

Every change to the stack is a commit. `git log` on `terraform/` is a
timeline of how this site's infrastructure evolved, with a message on each
step explaining why.

`git blame` on any line tells you when a setting appeared and what else
changed alongside it. There is no equivalent in a web console. CloudTrail
tells you *that* someone changed a setting, never *why*.

It also means infrastructure changes can be reviewed in a pull request
before they touch anything real, same as application code.

### plan tells me what's about to happen

`terraform plan` is a dry run. It diffs the config against reality and
prints exactly what it would create, change, or destroy, before doing any of
it.

Two things fall out of that. First, you catch the scary ones. A change that
says `# forces replacement` on a CloudFront distribution means a rebuild and
downtime, and you want to know that before you hit apply, not during.

Second, drift detection. If someone (me, at 2am, in the console) toggles a
setting by hand, the next plan shows it as a difference. The config stays
the source of truth and anything that wandered off gets pulled back.

### It's portable

The whole stack is parameterised:

```hcl
variable "domain_name" {
  description = "Apex domain the site is served on."
  type        = string
  default     = "alommaaa.com"
}
```

Point that at another domain, `terraform apply`, and I have the same
architecture for a different site in about fifteen minutes. The thing I
built once is now a template.

### It's the thing people actually use

The less romantic reason. Terraform is the industry default for this, and
being able to read someone else's modules and explain why a resource is laid
out the way it is is a directly employable skill. Every hour spent on this
is an hour spent on something that transfers.

## How the files are laid out

One file per concern, which is convention rather than a requirement.
Terraform reads every `.tf` in the directory and treats them as one config,
so the split is purely for humans.

```
terraform/
├── versions.tf     # terraform + provider version constraints, backend
├── providers.tf    # aws provider, plus the us-east-1 alias
├── variables.tf    # every input, with descriptions and defaults
├── locals.tf       # derived values, conditional lookups
├── s3.tf           # bucket, public access block, bucket policy
├── cloudfront.tf   # OAC, cache policy, distribution
├── acm.tf          # certificate + validation
├── route53.tf      # hosted zone, validation records, alias records
├── iam.tf          # OIDC provider, deploy role, deploy policy
└── outputs.tf      # values the workflow and I need afterwards
```

If you can't tell what's in a file from its name, the split isn't earning
its keep.

## Two things worth stealing

### Conditional create-or-lookup

Some resources you might already have. AWS only allows one GitHub OIDC
provider per account, so if another project already made one, creating a
second fails.

The pattern is a boolean variable, `count` on the resource, an inverted
`count` on a data source, and a local that picks whichever exists:

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
  ...
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}
```

```hcl
locals {
  github_oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}
```

Everything downstream uses `local.github_oidc_provider_arn` and doesn't care
which branch produced it. The same pattern handles `create_route53_zone`,
for the case where the hosted zone already exists.

### for_each over a computed set

ACM hands back one validation record per domain, and this cert covers both
the apex and `www`. Rather than hardcoding two records:

```hcl
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options :
      dvo.domain_name => {
        name   = dvo.resource_record_name
        record = dvo.resource_record_value
        type   = dvo.resource_record_type
      }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.zone_id
}
```

Add a third subject alternative name to the certificate and the right number
of records appears. Nothing else changes.

## The part I haven't finished

Honesty section.

State is still local. `terraform.tfstate` lives on my laptop, which means if
that disk dies, Terraform loses track of everything it built. The resources
keep running, but Terraform no longer knows they're its, and fixing that
means importing every resource by hand.

The fix is a remote backend, which is sitting commented out in `versions.tf`
waiting for me:

```hcl
# backend "s3" {
#   bucket       = "alommaaa-com-tfstate"
#   key          = "alome-website/terraform.tfstate"
#   region       = "us-east-1"
#   use_lockfile = true
# }
```

State in S3, versioned, with locking so two applies can't run at once. The
chicken-and-egg problem is that the state bucket has to exist before you can
use it as a backend, so it either gets made by hand or lives in its own tiny
bootstrap config.

Also worth saying out loud: **state files contain secrets in plaintext**.
Not an issue for this stack, but the moment there's a database password in
there, that file needs encryption and access control like any other
credential store. It is not something to casually commit.

[Next post](/blog/website/04-github-actions/): wiring it all to `git push`
with GitHub Actions, and why the cache has to be invalidated.
