terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket = "cp-mayank-demo"
    key    = "tfstate/cap2-remote-state"
    region = "us-west-2"
  }

}

# Configure the AWS Provider
provider "aws" {
    region="us-west-2"
}

# resource "aws_ecr_repository" "my_first_ecr_repo" {
#   name = "${var.resname}-mk-ecr-cap1" # Naming my repository
# }

resource "aws_ecs_cluster" "my_cluster" {
  name = "${var.resname}-mk-c1-cluster" # Naming the cluster
}

resource "aws_ecs_task_definition" "my_first_task" {
  family                   = "${var.resname}-my-first-task" # Naming our first task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "todo",
      "image": "962804699607.dkr.ecr.us-west-2.amazonaws.com/mk-c2-img:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000,
          "protocol": "tcp",
          "appProtocol": "http"
        }
      ],
      "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-create-group": "true",
                    "awslogs-group": "/ecs/my-first-task000",
                    "awslogs-region": "us-west-2",
                    "awslogs-stream-prefix": "ecs"
                },
                "secretOptions": []
        },
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  runtime_platform {
    cpu_architecture = "X86_64"
    operating_system_family = "LINUX"
  }
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "${var.resname}-mk-c1-ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_ecs_service" "my_first_service" {
  name            = "${var.resname}-my-first-service01"                             # Naming our first service
  cluster         = "${aws_ecs_cluster.my_cluster.id}"             # Referencing our created Cluster
  task_definition = "${aws_ecs_task_definition.my_first_task.arn}" # Referencing the task our service will spin up
 // launch_type     = "FARGATE"
  capacity_provider_strategy {
    base = 0
    capacity_provider = "FARGATE"
    weight = 1
  }
  ////////
  deployment_circuit_breaker{
    enable = true
    rollback = true
  }
  //////////
  desired_count   = 3 # Setting the number of containers we want deployed to 3
  network_configuration {
    subnets       = [ "subnet-021318a3222b6f79e", "subnet-01d69f2a7ee7efb83", "subnet-02a999c1b13aa14cc"]
    assign_public_ip = false
    security_groups  = ["${aws_security_group.service_security_group.id}"] # Setting the security group
  }
  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}" # Referencing our target group
    container_name   = "todo"
    container_port   = 3000 # Specifying the container port
  }
}

resource "aws_security_group" "service_security_group" {
  name        = "${var.resname}-mk-c1-task-sg"
  vpc_id      = "vpc-0f8815c29df30b66a"
  ingress {
    from_port = 3000
    to_port   = 3000
    protocol  = "tcp"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}


resource "aws_alb" "application_load_balancer" {
  name               = "${var.resname}-mk-c1-lb-tf" # Naming our load balancer
  load_balancer_type = "application"
  subnets = [ # Referencing the default subnets
    "subnet-07b83e19b1233ad2e",
    "subnet-016fe41b8326f2152",
    "subnet-0c727bc2e4b35e506"
  ]
  # Referencing the security group
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  name          = "${var.resname}-mk-c1-alb-sg"
  vpc_id        = "vpc-0f8815c29df30b66a"
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "${var.resname}-mk-c1-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "vpc-0f8815c29df30b66a" # Referencing the default VPC
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}" # Referencing our load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}" # Referencing our tagrte group
  }
}