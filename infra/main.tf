# Everything the pipeline needs in AWS, and nothing more:
#   1. A private storage bucket for the site's files.
#   2. A CloudFront "storefront" that serves those files over HTTPS.
#   3. A trust relationship with GitHub (OIDC), so no AWS password is ever stored,
#      that only accepts releases a lead engineer has approved.
#   4. A role for the pipeline that can write to that one bucket and do nothing else.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = var.project }
  }
}

# ---- Inputs ------------------------------------------------------------------

variable "project" {
  description = "Short name used for every AWS resource. setup.sh sets it from the repository name."
  type        = string
  default     = "secure-cicd-demo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.project))
    error_message = "Use 3 to 30 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
}

variable "aws_region" {
  description = "Region for the bucket. Keep this the same as AWS_REGION in the pipeline file."
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub username or organisation that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "Repository name."
  type        = string
}

variable "github_owner_id" {
  description = "Permanent numeric ID of the GitHub owner."
  type        = string
}

variable "github_repo_id" {
  description = "Permanent numeric ID of the repository."
  type        = string
}

variable "deploy_environment" {
  description = "The GitHub environment whose approved jobs may deploy. Must match 'environment:' in the pipeline file."
  type        = string
  default     = "production"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.deploy_environment))
    error_message = "Use letters, digits, hyphens or underscores only."
  }
}

variable "create_oidc_provider" {
  description = "An AWS account can register GitHub as an identity provider only once. Set to false if it already exists."
  type        = bool
  default     = true
}

# ---- 1. Private bucket -------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket_prefix = "${var.project}-"
  force_destroy = true # lets teardown delete the bucket even when it holds files
}

# No public door at all. The only way in for visitors is through CloudFront.
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- 2. CloudFront storefront ------------------------------------------------

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = var.project
  description                       = "Lets CloudFront, and only CloudFront, read the site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = var.project
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    origin_id                = "site-bucket"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "site-bucket"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    # AWS managed policy "CachingDisabled": every release shows up immediately.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "CloudFrontReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = data.aws_iam_policy_document.site_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---- 3. Trust GitHub as an identity provider (OIDC) --------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # Who GitHub says is knocking. Because the deploy job uses the "production"
  # environment, GitHub only issues this identity to a job that a required
  # reviewer (the lead engineer) has approved, from a branch the environment
  # allows (main). A pull request, an unapproved run or another repository
  # presents a different identity and is refused.
  #
  # Repositories created after 15 July 2026 are identified by name AND
  # permanent numeric ID, so nobody who later takes over the username or
  # repository name can impersonate this pipeline. The name-only form is what
  # older repositories send; it is listed so the demo works either way.
  trusted_identities = [
    "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:environment:${var.deploy_environment}",
    "repo:${var.github_owner}/${var.github_repo}:environment:${var.deploy_environment}",
  ]
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "OnlyApprovedProductionReleases"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The lock: an approved production release of this repository, and
    # nothing else.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.trusted_identities
    }
  }
}

# ---- 4. The pipeline's role: least privilege ---------------------------------

resource "aws_iam_role" "deploy" {
  name                 = "${var.project}-deploy"
  description          = "Assumed by the GitHub Actions pipeline to publish the ${var.project} site"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "SeeWhatIsInTheSiteBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }

  statement {
    sid       = "AddAndRemoveSiteFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "publish-site-only"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---- Outputs -----------------------------------------------------------------

output "AWS_ROLE_ARN" {
  description = "GitHub variable AWS_ROLE_ARN"
  value       = aws_iam_role.deploy.arn
}

output "S3_BUCKET" {
  description = "GitHub variable S3_BUCKET"
  value       = aws_s3_bucket.site.bucket
}

output "SITE_URL" {
  description = "GitHub variable SITE_URL"
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}
