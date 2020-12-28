---
date: 2020-12-28 11:15
description: Deploy a Lambda Function with a Swift Image
tags: lambda, aws, docker
---
# Deploy a Lambda Function with a Swift Image

Under re:Invent 2020 AWS announced support for container image containing Lambda function. This made me think about how to make a Swift Lambda function with a Docker image.

Fabian Fett made an excellent [post](https://fabianfett.de/getting-started-with-swift-aws-lambda-runtime) how to use [swift-aws-lambda-runtime](https://github.com/swift-server/swift-aws-lambda-runtime) to make a swift lambda function.

Can we use that to make a new image for AWS Lambda? Yes, you can, and in this post I will show you how. I will use the same function `SquareNumber` that Fabian Fett did in his post.

## Make the SquareNumber project
We need only a few files for the project. The Dockerfile uses the amazonlinux2 swift docker image to build the `SquareNumber` function.
The compiled function is copied into the public lambda al2 image.

![SquareNumber project](/images/lambda/Dockerfile.png)

The `Package.swift` file is the same as in Fabian Fett's post:

```
// swift-tools-version:5.2
 // The swift-tools-version declares the minimum version of Swift required to build this package.
    
 import PackageDescription
    
 let package = Package(
   name: "SquareNumber",
   products: [
     .executable(name: "SquareNumber", targets: ["SquareNumber"]),
   ],
   dependencies: [
     .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .upToNextMajor(from:"0.3.0")),
   ],
   targets: [
     .target(
       name: "SquareNumber",
       dependencies: [
         .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
       ]
     ),
   ]
 )
```

The same with main.swift:
```
import AWSLambdaRuntime

struct Input: Codable {
    let number: Double
}

struct Output: Codable {
    let result: Double
}

Lambda.run { (context, input: Input, callback: @escaping (Result<Output, Error>) -> Void) in
    callback(.success(Output(result: input.number * input.number)))
}
```

### Build the Docker image
Before you build the image, you must login to the public AWS repository:
`aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws`

Make sure you are in the root directory of the project, where `Dockerfile` is, and build the docker image and tag it with your account id:
`docker build -t <AWS account id>.dkr.ecr.eu-west-1.amazonaws.com/squarenumber .`
Remember the period at the end, that means that the build should take place in the current directory.

When the new docker image is built, you can push it to your ECR repository.
If you haven't created the repository, you can do it with this command:
`aws ecr create-repository --repository-name squarenumber`

Before you push it, you must login to your private ECR:
`aws ecr get-login-password | docker login --username=AWS --password-stdin <AWS account id>.dkr.ecr.eu-west-1.amazonaws.com`

Then you can push the image to ECR: `docker push <AWS account id>.dkr.ecr.eu-west-1.amazonaws.com/squarenumber:latest`

### Create Lambda Function
Now we are ready to create the lambda function. Navigate to the AWS Lambda console, click the `Create function` button, and fill in the details:
![Create Lambda](/images/lambda/CreateLambda.png)
 
### Test Lambda
Click the `Test` button in the Lambda console, and make a new test:

![Test Lambda](/images/lambda/TestLambda.png)

When you have created the test, and pressed the `Test` button again, you should get your number squared.
