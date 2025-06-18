terraform {
  required_version = "~>1.11.4"
  required_providers {
    aws ={
      source = "hashicorp/aws"
      version = "~>3.20"
    }
  }
}

provider "aws" {
  region  = "ap-south-1"
  profile = "default"
}

# --- ECR Repository ---
resource "aws_ecr_repository" "ecr-repo" {
   name = "ecr-repo"  
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "my_cluster" {
  name = "my-ecs-cluster"
}

#Creating Task Definition
resource "aws_ecs_task_definition" "my-task-ecs" {
  family                   = "my-app-task"
  container_definitions    = <<DEFINITION
  [
    {
      "name": "my-app-task",
      "image": "${aws_ecr_repository.ecr-repo.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 5000,
          "hostPort": 5000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # use Fargate as the launch type
  network_mode             = "awsvpc"    # add the AWS VPN network mode as this is required for Fargate
  memory                   = 512         # Specify the memory the container requires
  cpu                      = 256         # Specify the CPU the container requires
  execution_role_arn       = "${aws_iam_role.my-ecs-Task-Role.arn}"
}

resource "aws_iam_role" "my-ecs-Task-Role" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_ecs.json}"
}

data "aws_iam_policy_document" "assume_role_ecs" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "policy-ecs-Task-Execution-Role" {
  role       = "${aws_iam_role.my-ecs-Task-Role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


#VPC

resource "aws_default_vpc" "my_vpc" {

}

#default subnets
resource "aws_default_subnet" "my_subnet_a" {
  availability_zone = "ap-south-1a"
}

resource "aws_default_subnet" "my_subnet_b" {
  availability_zone = "ap-south-1b"
}


#Creating Load Balancer
resource "aws_alb" "my_load_balancer" {
  name               = "my-load-balancer" #load balancer name
  load_balancer_type = "application"
  subnets = [ 
    "${aws_default_subnet.my_subnet_a.id}",
    "${aws_default_subnet.my_subnet_b.id}"
  ]
   security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}
 
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic in from all sources
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}




resource "aws_lb_target_group" "target_group" {
  name        = "my-target-group"
  port        = 5000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.my_vpc.id
}


resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.my_load_balancer.arn}"
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}" 
  }
}


resource "aws_ecs_service" "my_service" {
  name            = "my-first-service" 
  cluster         = "${aws_ecs_cluster.my_cluster.id}"   
  task_definition = "${aws_ecs_task_definition.my-task-ecs.arn}" 
  launch_type     = "FARGATE"
  desired_count   = 3 

  load_balancer {
    target_group_arn =  aws_lb_target_group.target_group.arn
    container_name   = "my-app-task"
    container_port   = 5000 
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.my_subnet_a.id}", "${aws_default_subnet.my_subnet_b.id}"]
    assign_public_ip = true     
    security_groups  =  ["${aws_security_group.service_security_group.id}"]

}

  }



resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}