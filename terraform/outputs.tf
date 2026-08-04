output "s3_bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.site.domain_name
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}

output "route53_nameservers" {
  description = "Only populated when create_route53_zone = true. Copy these into your registrar's nameserver settings."
  value       = var.create_route53_zone ? aws_route53_zone.this[0].name_servers : null
}
