locals {
  bucket_name = coalesce(var.bucket_name, var.domain_name)

  zone_id = var.create_route53_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.this[0].zone_id

  github_oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}
