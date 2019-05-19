# Input variables
variable "aws_region" {
  type    = "string"
  default = "us-east-1"
}

variable "pipeline_name" {
  type    = "string"
  default = "baladigitalcloud-static-website"
}



# CodeCommit resources
#  resource "aws_codecommit_repository" "repo" {
#  repository_name = "${var.repo_name}"
#  description     = "${var.repo_name}"
#  default_branch  = "${var.repo_default_branch}"
#}

provider "aws" {
  region     = "${var.aws_region}"
}

#Static website
resource "aws_s3_bucket" "baladigitalcloud-static-site1-vu" {
  bucket = "${var.www_domain_name}"
  acl    = "public-read"
  policy = "${file("policy.json")}"

  website {
    index_document = "index.html"
    error_document = "error.html"

  }
}

##########

resource "aws_cloudfront_distribution" "www_distribution" {
  origin {

      custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
    domain_name = "${aws_s3_bucket.baladigitalcloud-static-site1-vu.website_endpoint}"
    origin_id   = "${var.www_domain_name}"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${var.www_domain_name}"
   
  forwarded_values {
    query_string = false
  
  cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
 
 aliases = ["${var.www_domain_name}"]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
#    cloudfront_default_certificate = true
    acm_certificate_arn = "arn:aws:acm:us-east-1:702401326258:certificate/b4606606-f041-4411-b8a8-e0a8daf76b9c"
    ssl_support_method  = "sni-only"
  }
}


##########

// We want AWS to host our zone so its nameservers can point to our CloudFront
// distribution.
#resource "aws_route53_zone" "zone" {
#  name = "${var.root_domain_name}"
#}

// This Route53 record will point at our CloudFront distribution.
resource "aws_route53_record" "baladigitalcloud-static-site1-vu" {
  zone_id = "Z1FTMWX6SDFIEW"
  name    = "${var.www_domain_name}"
  type    = "A"

  alias = {
    name                   = "${aws_cloudfront_distribution.www_distribution.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.www_distribution.hosted_zone_id}"
    evaluate_target_health = false
  }
}

##########

# CodePipeline resources
resource "aws_s3_bucket" "build_artifact_bucket" {
  bucket = "${var.pipeline_name}-artifact-bucket"
  acl    = "private"
}

data "aws_iam_policy_document" "codepipeline_assume_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "${var.pipeline_name}-codepipeline-role"
  assume_role_policy = "${data.aws_iam_policy_document.codepipeline_assume_policy.json}"
}

# CodePipeline policy needed to use CodeCommit and CodeBuild
resource "aws_iam_role_policy" "attach_codepipeline_policy" {
  name = "${var.pipeline_name}-codepipeline-policy"
  role = "${aws_iam_role.codepipeline_role.id}"

  policy = <<EOF
{
    "Statement": [
        {
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:GetBucketVersioning",
                "s3:PutObject"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "cloudwatch:*",
                "sns:*",
                "sqs:*",
                "iam:PassRole"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "codecommit:CancelUploadArchive",
                "codecommit:GetBranch",
                "codecommit:GetCommit",
                "codecommit:GetUploadArchiveStatus",
                "codecommit:UploadArchive"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "codebuild:BatchGetBuilds",
                "codebuild:StartBuild"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ],
    "Version": "2012-10-17"
}
EOF
}

# CodeBuild IAM Permissions
resource "aws_iam_role" "codebuild_assume_role" {
  name = "${var.pipeline_name}-codebuild-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.pipeline_name}-codebuild-policy"
  role = "${aws_iam_role.codebuild_assume_role.id}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
       "s3:PutObject",
       "s3:GetObject",
       "s3:GetObjectVersion",
       "s3:GetBucketVersioning"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Resource": [
        "${aws_codebuild_project.build_project.id}"
      ],
      "Action": [
        "codebuild:*"
      ]
    },
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    }
  ]
}
POLICY
}

# CodeBuild Section for the Package stage
resource "aws_codebuild_project" "build_project" {
  name          = "${var.pipeline_name}-build"
  description   = "The CodeBuild project for ${var.pipeline_name}"
  service_role  = "${aws_iam_role.codebuild_assume_role.arn}"
  build_timeout = "60"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/nodejs:8.11.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

# Full CodePipeline
resource "aws_codepipeline" "codepipeline" {
  name     = "${var.pipeline_name}-codepipeline"
  role_arn = "${aws_iam_role.codepipeline_role.arn}"

  artifact_store = {
    location = "${aws_s3_bucket.build_artifact_bucket.bucket}"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["code"]

      configuration {
        RepositoryName       = "vu-example-repo"
        BranchName           = "master"
        PollForSourceChanges = "true"
      }
    }
  }

  stage {
    name = "DeployToS3"

    action {
      name             = "DeployToS3"
      category         = "Test"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["code"]
      output_artifacts = ["deployed"]
      version          = "1"

      configuration {
        ProjectName = "${aws_codebuild_project.build_project.name}"
      }
    }
  }

}
