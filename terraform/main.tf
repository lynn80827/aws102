provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "us-west-2"
}

# Network
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags {
    Name = "tf-demo-vpc"
  }
}

resource "aws_subnet" "public_subnet_2a" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags {
    Name = "tf-demo-public-subnet-2a"
  }
}

resource "aws_subnet" "public_subnet_2b" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  tags {
    Name = "tf-demo-public-subnet-2b"
  }
}

resource "aws_subnet" "private_subnet_2a" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.0.5.0/24"
  availability_zone = "us-west-2a"
  tags {
    Name = "tf-demo-private-subnet-2a"
  }
}

resource "aws_subnet" "private_subnet_2b" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.0.6.0/24"
  availability_zone = "us-west-2b"
  tags {
    Name = "tf-demo-private-subnet-2b"
  }
}

resource "aws_internet_gateway" "public_facing" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags {
    Name = "tf-internet-gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = "${aws_vpc.vpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.public_facing.id}"
  }
}

resource "aws_route_table_association" "public_subnet_2a_routing" {
  subnet_id = "${aws_subnet.public_subnet_2a.id}"
  route_table_id = "${aws_route_table.public_route_table.id}"
}

resource "aws_route_table_association" "public_subnet_2b_routing" {
  subnet_id = "${aws_subnet.public_subnet_2b.id}"
  route_table_id = "${aws_route_table.public_route_table.id}"
}

resource "aws_security_group" "sg_webserver_lb" {
  name = "tf-demo-sg-webserver-lb"
  vpc_id = "${aws_vpc.vpc.id}"
  ingress {
    from_port = 80
    to_port = 80
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "tf-demo-sg-webserver"
  }
}

resource "aws_security_group" "sg_webserver_ecs_instance" {
  name = "tf-demo-sg-webserver-ecs-instance"
  vpc_id = "${aws_vpc.vpc.id}"
  ingress {
    from_port = 0
    to_port = 32777
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "tf-demo-sg-webserver"
  }
}

# Database
resource "aws_security_group" "sg_mysql" {
  name = "tf-demo-sg-mysql"
  vpc_id = "${aws_vpc.vpc.id}"
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "TCP"
    security_groups = ["${aws_security_group.sg_webserver_ecs_instance.id}"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "tf-demo-sg-mysql"
  }
}

resource "aws_db_subnet_group" "mysql_subnet_group" {
  name = "tf-demo-mysql-subnet-group"
  subnet_ids = ["${aws_subnet.private_subnet_2a.id}", "${aws_subnet.private_subnet_2b.id}"]
  tags {
    Name = "tf-demo-mysql-subnet-group"
  }
}

resource "aws_db_parameter_group" "mysql_parameters" {
  name = "tf-demo-mysql-paramters"
  family = "mysql5.6"
  parameter {
    name  = "character_set_server"
    value = "utf8"
  }
}

resource "aws_db_option_group" "mysql_options" {
  name = "tf-demo-mysql-options"
  engine_name = "mysql"
  major_engine_version = "5.6"
}

resource "aws_db_instance" "mysql" {
  identifier = "tf-demo-mysql"
  allocated_storage = 20
  storage_type = "gp2"
  engine = "mysql"
  instance_class = "db.t2.micro"
  name = "todo"
  username = "root"
  password = "password"
  db_subnet_group_name = "${aws_db_subnet_group.mysql_subnet_group.id}"
  vpc_security_group_ids = ["${aws_security_group.sg_mysql.id}"]
  auto_minor_version_upgrade = false
  skip_final_snapshot = true
  parameter_group_name = "${aws_db_parameter_group.mysql_parameters.id}"
  option_group_name = "${aws_db_option_group.mysql_options.id}"
  depends_on = [
    "aws_db_subnet_group.mysql_subnet_group",
    "aws_db_parameter_group.mysql_parameters",
    "aws_db_option_group.mysql_options"
  ]
}

resource "aws_route53_zone" "private_hosted_zone" {
  name = "lynn.demo"
  vpc_id = "${aws_vpc.vpc.id}"
  tags {
    Name = "tf-private-hosted-zone"
  }
}

resource "aws_route53_record" "domain_record_db" {
  name = "db.lynn.demo"
  type = "CNAME"
  zone_id = "${aws_route53_zone.private_hosted_zone.zone_id}"
  ttl = 300
  records = ["${aws_db_instance.mysql.address}"]
}

# Storage
resource "aws_s3_bucket" "s3" {
  bucket = "tf-demo-todo-image"
  acl = "private"
}

# Task Authorization
data "aws_iam_policy_document" "iam_policy_ecs_task_access_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = [
      "${aws_s3_bucket.s3.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "iam_policy_ecs_task_access_s3" {
  name = "tfDemoFullAccessToDemoTodoImage"
  policy = "${data.aws_iam_policy_document.iam_policy_ecs_task_access_s3.json}"
}

# Load Balance
resource "aws_lb_target_group" "alb_webserver_tg" {
  name = "tf-demo-alb-webserver-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_lb" "alb_webserver" {
  name = "tf-demo-alb-webserver"
  internal = false
  security_groups = ["${aws_security_group.sg_webserver_lb.id}"]
  subnets = ["${aws_subnet.public_subnet_2a.id}", "${aws_subnet.public_subnet_2b.id}"]
}

resource "aws_lb_listener" "alb_webserver_listen" {
  load_balancer_arn = "${aws_lb.alb_webserver.arn}"
  port = 80
  protocol = "HTTP"
  default_action {
    target_group_arn = "${aws_lb_target_group.alb_webserver_tg.arn}"
    type = "forward"
  }
}

output "alb_dns" {
  value = "${aws_lb.alb_webserver.dns_name}"
}
