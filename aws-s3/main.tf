terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "demo-bucket" {
    bucket = "demogaruav123820"  
}

resource "aws_s3_object" "bucket-data" {
    bucket = aws_s3_bucket.demo-bucket.bucket
    source = "./myfile.txt"
    key = "mydata.txt"
}