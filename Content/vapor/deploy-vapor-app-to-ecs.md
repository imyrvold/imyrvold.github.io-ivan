---
date: 2020-12-11 07:00
description: Step-by-step how to deploy a Vapor app to ECS Fargate with AWS Cloud Development Kit
tags: vapor, cdk, aws, ecs
---
# Deploy a Vapor app to ECS Fargate with CDK

## How I started using CDK

I have had an AWS account for a long time, I don't remember exactly when I signed up for it, but I have  
emails with invoices from 2013, so I have been an AWS user for at least 7-8 years.

But it wasn't until I had a consultant job with the oil service company National Oilwell Varco that I got  
seriously interested in the AWS universe, and realized how rich an ecosystem this has become in the  
last few years. I got deeply involved in developing AWS infrastructure with Terraform and Ansible, and
soon appreciated the value of deploying a complete infrastructure with EC2 instances, VPC,  
security groups, load balancers etc. with a single command.

I have been using Vapor since Vapor 3, and I have tried different ways to deploy a Vapor service to AWS
Elastic Container Service (ECS) Fargate. I have used AWS commands to configure task definitions, ECS clusters,  
ECS service etc. I also have tried AWS ECS commands. I got it working, but it is so many commands  
to get everything up and running, especially if I also wanted to have load balancer and security groups etc  
set up.

CloudFormation solves the problem of setting up infrastructure repeatedly in the same way, it is like a  
plan of how you want your infrastructure to look like, and you can keep adding or removing elements from  
this plan and keep it up to date. But the CloudFormation infrastructure code soon adds up to hundreds of lines  
of code very soon, and it is a lot of work to keep it up to date.

Then I found [AWS Cloud Development Kit (CDK)](https://aws.amazon.com/cdk/) that AWS introduced a couple of years ago, and I  
soon saw this as a powerful way to define infrastructure in AWS with a lot less code.

With CDK I can use a familiar programming language to set up the infrastructure (TypeScript, JavaScript,  
Python, Java and soon Go) with something CDK calls constructs, which are the basic building blocks of an AWS CDK app.
I would love to have Swift support in CDK, and if you go to [aws-cdk Github](https://github.com/aws/aws-cdk/issues/549)  
you can vote for Swift support in an upcoming CDK release (21 votes so far).

## How I deploy a Vapor app to AWS ECS Fargate

I how worked on a Vapor 4 app with a Mongo databse since this summer, with a SwiftUI app on MacOS, iOS and  
iPadOS as a frontend to the Vapor backend. I started investigating how to use CDK to deploy the  
Vapor app and Mongo database containers to ECS Fargate a couple of weeks ago, and I now  
have a setup that I for now is satisfied with.

I use the new Nova app from Panic, but you can use any IDE you want, as Visual Studio Code is also a great
alternative. With a single cli command `cdk deploy` I can deploy the infrastructure needed to run the  
service, and after a few minutes it is running on ECS Fargate.

![CDK with Nova](/images/vapor/dune-vapor.png)

I have made a YouTube video [Vapor app to AWS ECS Fargate with CDK](https://youtu.be/DG0PCAuX9Qc) of  
how I set up the CDK infrastructure   code, and another video [Deploy Vapor App with CDK](https://youtu.be/tpxKIhkve18)  
for the deploy part of it.

The CDK project for this [dune-vapor-cdk](https://github.com/imyrvold/dune-vapor-cdk.git) can be cloned from my GitHub account.

Removing the infrastructure code is by doing a cli command `cdk destroy`, and all infrstructure  
will be removed after a couple of minutes. That is great to save money on using AWS, which I use on  
my personal AWS account.

## Add a CI/CD pipeline to the project

I have started working on enhancing the project to add a CI/CD pipeline to it. CDK have a pipeline construct  
that I think will be very helpful with this. This will be in an upcoming YouTube video and blog post
