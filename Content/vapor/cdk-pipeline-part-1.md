---
date: 2020-12-21 07:00
description: Deploy Vapor app with Continuous Integration/Delivery to AWS ECS Fargate
tags: vapor, cdk, aws, ecs
---
###### Published 2020-12-21
# Deploy a Vapor app with CI/CD to ECS Fargate with CDK

## The project

I have implemented the minimum of the User manager in Shop Backend from the book `Hands-On Swift 5 Microservices Development` by Ralph Kuepper for this project. The Product Manager and Order Manager I will cover in a later blog post and YouTube video.

I will make use of the pipeline construct library of the AWS Cloud Development Kit to define a pipeline for the UserManager vapor application, the complete project is hosted in a GitHub repository.

## The UserManager pipeline

We need to deploy the pipeline manually with a `cdk deploy CicdInfraStack` the first time, and then any commit and push to the GitHub repository will trigger the pipeline in AWS which will go through all the stages to pull from GitHub, build the Vapor app with Swift, and deploy new vapor app docker container to ECS Fargate.

The pipeline is translated from TypeScript to CloudFormation by CDK. It uses CodePipeline for the pipeline, CodeBuild to build the Vapor Swift app, S3 to store the artifacts from the build, Secrets Manager to store the secrets that are injected into the container as Environment variables, CloudWatch for logging, ECR for storing the container images, ECR public for the Swift 5.3 docker images, ECS Fargate for running the containers in AWS.

We could define everything in CloudFormation and skip the CDK, but CDK makes defining the infrastructure in AWS much easier, and using a familiar language as TypeScript, JavaScript, Python or Go is also a plus.

The YouTube video [CDK Vapor App AWS Pipeline](https://youtu.be/M6XSSgKiLxc) shows the steps to deploy the pipeline to AWS. In the next blog post I will continue with the project, but split the project into several pipelines for UserManager, ProductManager and OrderManager. I will also host the CDK pipeline in it's own GitHub repo.
