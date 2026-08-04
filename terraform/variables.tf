variable "aws_region" {
  description = "Primary AWS region for the S3 bucket and IAM resources."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Apex domain the site is served on."
  type        = string
  default     = "alommaaa.com"
}

variable "bucket_name" {
  description = "S3 bucket name. Defaults to the domain name if left null."
  type        = string
  default     = null
}

variable "create_route53_zone" {
  description = "Whether to create a new Route 53 hosted zone for domain_name, or use an existing one."
  type        = bool
  default     = true
}

variable "create_oidc_provider" {
  description = "Whether to create the GitHub Actions OIDC provider, or reuse an existing one already in this AWS account (only one is allowed per account)."
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the deploy role, as \"owner/repo\"."
  type        = string
  default     = "alsy4/alommaaa.com"
}

variable "github_branch" {
  description = "Branch allowed to assume the deploy role."
  type        = string
  default     = "main"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner (user/org) ID, from the OIDC sub claim."
  type        = string
  default     = "44989969"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID, from the OIDC sub claim."
  type        = string
  default     = "1322331341"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class. PriceClass_100 covers North America and Europe edge locations only, cheapest option."
  type        = string
  default     = "PriceClass_100"
}
