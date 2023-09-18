# Creating IAM role so that it can be assumed while connecting to the Kubernetes cluster.


resource "aws_iam_role" "master" {
  name = "terraform-eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# Attach the AWS EKS service and AWS EKS cluster policies to the role.



resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.master.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.master.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.master.name
}

resource "aws_iam_role" "worker" {
  name = "terraform-eks-worker"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "autoscaler" {
  name   = "terraform-eks-autoscaler-policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeTags",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "x-ray" {
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.worker.name
}
resource "aws_iam_role_policy_attachment" "s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "autoscaler" {
  policy_arn = aws_iam_policy.autoscaler.arn
  role       = aws_iam_role.worker.name
}

resource "aws_iam_instance_profile" "worker" {
  depends_on = [aws_iam_role.worker]
  name       = "ed-eks-worker-new-profile"
  role       = aws_iam_role.worker.name
}


# Create security group for AWS EKS.

resource "aws_security_group" "allow_tls" {
    name        = "allow_tls"
    description = "Allow TLS inbound traffic"
    vpc_id      = aws_vpc.main.id
  
    ingress {
      description = "TLS from VPC"
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
      Name = "allow_tls"
    }
  }

# Create VPC
resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
  
    tags = {
      Name = "PC-VPC"
    }
  }

#Create Subnets
resource "aws_subnet" "public-1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-sub-1"
  }
}

resource "aws_subnet" "public-2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-sub-2"
  }
}

#Create Internet Gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.main.id
  
    tags = {
      Name = "main"
    }
  }
#Create Route table
resource "aws_route_table" "rtb" {
    vpc_id = aws_vpc.main.id
  
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.gw.id
    }
  
    tags = {
      Name = "MyRoute"
    }
  }
  
  resource "aws_route_table_association" "a-1" {
    subnet_id      = aws_subnet.public-1.id
    route_table_id = aws_route_table.rtb.id
  }
  
  resource "aws_route_table_association" "a-2" {
    subnet_id      = aws_subnet.public-2.id
    route_table_id = aws_route_table.rtb.id
  }

  # Creating the AWS EKS cluster


  resource "aws_eks_cluster" "eks" {
    name     = "terraform-eks-cluster"
    role_arn = aws_iam_role.master.arn
  
  
    vpc_config {
      subnet_ids = [aws_subnet.public-1.id, aws_subnet.public-2.id]
    }
  
    depends_on = [
      aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
      aws_iam_role_policy_attachment.AmazonEKSServicePolicy,
      aws_iam_role_policy_attachment.AmazonEKSVPCResourceController,
      aws_iam_role_policy_attachment.AmazonEKSVPCResourceController,
      #aws_subnet.pub_sub1,
      #aws_subnet.pub_sub2,
    ]
  }

#Kubectl server setup
    resource "aws_instance" "kubectl-server" {
        ami                         = "ami-0f5ee92e2d63afc18"
        key_name                    = "EC2Keypair"
        instance_type               = "t2.micro"
        associate_public_ip_address = true
        subnet_id                   = aws_subnet.public-1.id
        vpc_security_group_ids      = [aws_security_group.allow_tls.id]
      
        tags = {
          Name = "kubectl"
        }
      
      }
      # Create AWS EKS cluster node group

      resource "aws_eks_node_group" "node-grp" {
        cluster_name    = aws_eks_cluster.eks.name
        node_group_name = "eks-node-group"
        node_role_arn   = aws_iam_role.worker.arn
        subnet_ids      = [aws_subnet.public-1.id, aws_subnet.public-2.id]
        capacity_type   = "ON_DEMAND"
        disk_size       = "20"
        instance_types  = ["t2.small"]
      
        remote_access {
          ec2_ssh_key               = "EC2Keypair"
          source_security_group_ids = [aws_security_group.allow_tls.id]
        }
      
        labels = tomap({ env = "dev" })
      
        scaling_config {
          desired_size = 2
          max_size     = 3
          min_size     = 1
        }
      
        update_config {
          max_unavailable = 1
        }
      
        depends_on = [
          aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
          aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
          aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
          #aws_subnet.pub_sub1,
          #aws_subnet.pub_sub2,
        ]
      }
