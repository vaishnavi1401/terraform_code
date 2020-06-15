provider "aws" {
  region                  = "ap-south-1"
  profile                 = "vaishnavi"
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
}
module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name   = "deployer-one"
  public_key = tls_private_key.this.public_key_openssh
}

data "aws_vpc" "default" {
  default = true
}
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow TCP inbound traffic"
   vpc_id      = data.aws_vpc.default.id

	
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow_http"
  }
}

resource "aws_instance" "myweb" {
  ami           = "ami-0447a12f28fddb066" 
  instance_type = "t2.micro"
  key_name = "deployer-one"
  vpc_security_group_ids=["${aws_security_group.allow_http.name}"]
 
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.this.private_key_pem}"
    host     = aws_instance.myweb.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
   tags={
    Name = "myweb"
}
}



resource "aws_ebs_volume" "external_volume" {
  availability_zone = "${aws_instance.myweb.availability_zone}"
  size              = 1
  tags={
    Name = "web-volume"
}
}
resource "aws_volume_attachment" "ebs_attach" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.external_volume.id}"
  instance_id = "${aws_instance.myweb.id}"
  force_detach = true
}
resource "null_resource" "nullvolume"  {

depends_on = [
    aws_volume_attachment.ebs_attach,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key =tls_private_key.this.private_key_pem
    host     = aws_instance.myweb.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/vaishnavi1401/devops-site-try.git /var/www/html/"
    ]
  }
}
resource "aws_s3_bucket" "images" {
  bucket = "my-test-bucket-images"
acl="public-read"
provisioner "local-exec" {
	    command = "  echo Y |rm -rf images "
  	}
provisioner "local-exec" {
	    command = " git clone https://github.com/vaishnavi1401/devops-site-try.git images"
  	}

}
output "myos_ip" {
  value = aws_s3_bucket.images.bucket
}


variable "var1" {default ="s3."}
locals {
  s3_origin_id = "${var.var1}${aws_s3_bucket.images.bucket}"
  image_url= "${aws_cloudfront_distribution.s3_distribution.domain_name}/{aws_s3_bucket_object.image.bucket}"
}
resource "aws_s3_bucket_object" "image" {
depends_on = [
   aws_s3_bucket.images,
  ]
  bucket = aws_s3_bucket.images.bucket
  key    = "1.png"
  source = "images/1.png"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.images.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

   
  }


  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.php"



  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

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



  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

