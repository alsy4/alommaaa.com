terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state to start. Once a dedicated state bucket exists, switch to a
  # remote backend so state isn't only on one machine:
  #
  # backend "s3" {
  #   bucket       = "alommaaa-com-tfstate"
  #   key          = "alome-website/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}
