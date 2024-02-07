terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  backend "s3" {
    bucket = "group4-tfstate"
    key    = "state/remote-state"
    region = "us-west-2"
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = "us-west-2"
  access_key = var.access_key
  secret_key = var.secret_key
}

resource "aws_ecr_repository" "group4_capstone_ecr_repo" {
  name = "group4_capstone_ecr_repo" # Naming my repository
}

resource "aws_ecs_cluster" "group4-cluster" {
  name = "group4-cluster" # Naming the cluster
}

resource "aws_ecs_task_definition" "group4-task" {
  family                   = "group4-task" # Naming our first task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "group4-task",
      "image": "${aws_ecr_repository.group4_capstone_ecr_repo.repository_url}:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 8080
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = aws_iam_role.group4-ecsTaskExecutionRole.arn
}

resource "aws_iam_role" "group4-ecsTaskExecutionRole" {
  name               = "group4-ecsTaskExecutionRole-capstone-2"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
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
  role       = aws_iam_role.group4-ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "group4-service" {
  name            = "group4-service"                        # Naming our first service
  cluster         = aws_ecs_cluster.group4-cluster.id       # Referencing our created Cluster
  task_definition = aws_ecs_task_definition.group4-task.arn # Referencing the task our service will spin up
  launch_type     = "FARGATE"
  desired_count   = 3 # Setting the number of containers we want deployed to 3

  load_balancer {
    target_group_arn = aws_lb_target_group.group4-target-group.arn # Referencing our target group
    container_name   = aws_ecs_task_definition.group4-task.family
    container_port   = 8080 # Specifying the container port
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true                                                # Providing our containers with public IPs
    security_groups  = ["${aws_security_group.service_security_group.id}"] # Setting the security group
  }
}

resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.group4-alb-sg.id}"]
  }

  ingress {
    from_port   = 8080 # Allowing traffic in from port 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0             # Allowing any incoming port
    to_port     = 0             # Allowing any outgoing port
    protocol    = "-1"          # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

# Providing a reference to our default VPC
resource "aws_default_vpc" "default_vpc" {
}

# Providing a reference to our default subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-west-2a"
  
  tags ={
    "kubernetes.io/cluster/group4-capstone2-eks-cluster" = "shared"
    "kubernetes.io/role/elb" = 1
  }
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-west-2b"
  
  tags ={
    "kubernetes.io/cluster/group4-capstone2-eks-cluster" = "shared"
    "kubernetes.io/role/elb" = 1
  }
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "us-west-2c"
  
  tags ={
    "kubernetes.io/cluster/group4-capstone2-eks-cluster" = "shared"
    "kubernetes.io/role/elb" = 1
  }
}

resource "aws_alb" "group4-alb" {
  name               = "group4-lb-tf" # Naming our load balancer
  load_balancer_type = "application"
  subnets = [ # Referencing the default subnets
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  # Referencing the security group
  security_groups = ["${aws_security_group.group4-alb-sg.id}"]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "group4-alb-sg" {
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0             # Allowing any incoming port
    to_port     = 0             # Allowing any outgoing port
    protocol    = "-1"          # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}


resource "aws_lb_target_group" "group4-target-group" {
  name        = "group4-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id # Referencing the default VPC
  health_check {
    matcher             = "200,301,302"
    path                = "/"
    timeout             = 60
    interval            = 120
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "group4-listener" {
  load_balancer_arn = aws_alb.group4-alb.arn # Referencing our load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.group4-target-group.arn # Referencing our target group
  }
}

resource "aws_eks_cluster" "group4-eks-cluster" {
  name     = "group4-capstone2-eks-cluster"
  role_arn = aws_iam_role.group4-k8s-role.arn

  vpc_config {
    subnet_ids = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.group4-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.group4-AmazonEKSVPCResourceController,
    aws_iam_role_policy_attachment.group4-AmazonEKSCNIPolicy
  ]
  
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
}

output "endpoint" {
  value = aws_eks_cluster.group4-eks-cluster.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.group4-eks-cluster.certificate_authority[0].data
}

data "aws_iam_policy_document" "assume_role_eks" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com", "ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "group4-k8s-role" {
  name               = "group4-k8s-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_eks.json
}

resource "aws_iam_role_policy_attachment" "group4-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.group4-k8s-role.name
}

# Optionally, enable Security Groups for Pods
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
resource "aws_iam_role_policy_attachment" "group4-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.group4-k8s-role.name
}

resource "aws_iam_role_policy_attachment" "group4-AmazonEKSCNIPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.group4-k8s-role.name
}

resource "aws_iam_role_policy_attachment" "group4-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.group4-k8s-role.name
}

resource "aws_iam_role_policy_attachment" "group4-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.group4-k8s-role.name
}

resource "aws_eks_addon" "vpc-cni-addon" {
  cluster_name = aws_eks_cluster.group4-eks-cluster.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns-addon" {
  cluster_name = aws_eks_cluster.group4-eks-cluster.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "kube-proxy-addon" {
  cluster_name = aws_eks_cluster.group4-eks-cluster.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_node_group" "group4-node-group" {
  cluster_name    = aws_eks_cluster.group4-eks-cluster.name
  node_group_name = "group4-node-group"
  node_role_arn   = aws_iam_role.group4-k8s-role.arn
  subnet_ids      = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.group4-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.group4-AmazonEKSCNIPolicy,
    aws_iam_role_policy_attachment.group4-AmazonEC2ContainerRegistryReadOnly,
  ]
}