---
date: 2021-01-15 12:00
description: Test Swift Lambda Locally
tags: lambda, localstack, aws, docker, swift
---
###### Published 2021-01-15
# Test Swift Lambda Locally

When trying to find a way to test a Lambda function coded in Swift locally, I came over [Localstack](https://localstack.cloud). We can launch Localstack in a docker container, and it will act as a local AWS cloud environment, without you requiring to log into your AWS account.

I will show how we can make localstack work with our Swift Lambda function. I will use the SquareNumber lambda function that I posted in [Deploy a Lambda Function with a Swift Image](/aws/swift-lambda-function), but now we can test it locally 😀.

You will have to have AWS CLI installed to follow this post, with `brew install awscli`.

## Set up localstack

Make a new folder and `cd` into it with the cli command: `mkdir SquareNumberLocal && cd SquareNumberLocal`

I find it convenient to use a docker-compose file to set up localstack:

Make a `docker-compose.yml` file and set the content to:

```
version: '3'
services:
  localstack:
    image: localstack/localstack:latest
    ports:
      - 4566-4583:4566-4583
    container_name: square-number-lambda-localstack
    environment:
      - SERVICES=serverless
      - LAMBDA_EXECUTOR=docker
      - DOCKER_HOST=unix:///var/run/docker.sock
      - DEBUG=1
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
```
Start the localstack docker container with: `docker-compose up -d`

All the AWS API's is accessible from a single edge service, which is accessible on http://localhost:4566.
Documentation for localstack is available on the [localstack/localstack GitHub repository](https://github.com/localstack/localstack).

Make sure that we don't have any lambda functions in the localstack with the command:
`aws --endpoint-url http://localhost:4566 lambda list-functions`

This should return this:

```
{
    "Functions": []
}
```

We always add the `--endpoint-url http://localhost:4566` parameter to aws cli commands, to direct the cli commands to localstack. 
We can install a thin wrapper to this with `awslocal` that can be installed from [localstack/awscli-local GitHub repository](https://github.com/localstack/awscli-local), which makes it possible to replace `aws --endpoint-url http://localhost:4566` with just `awslocal`. The aws commands will then simply be `awslocal lambda list-functions`.
But I will be using the `--endpoint-url` in this post.

## Set up Swift Lambda function
Start a new Swift project with: `swift package init --type executable`, and open it in Xcode with `open Package.swift`

Add `swift-aws-lambda-runtime` to dependencies in `Package.swift`:

```
// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SquareNumberLocal",
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .upToNextMajor(from: "0.3.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SquareNumberLocal",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
            ]),
        .testTarget(
            name: "SquareNumberLocalTests",
            dependencies: ["SquareNumberLocal"]),
    ]
)
```
Replace the content of `main.swift` with:

```
import AWSLambdaRuntime

struct Input: Codable {
    let number: Double
}

struct Output: Codable {
    let result: Double
}

Lambda.run { (context, input: Input, callback: @escaping (Result<Output, Error>) -> Void) in
    print("input:", input)
    callback(.success(Output(result: input.number * input.number)))
}
```

## Compile with amazonlinux2 container and zip

Compile the swift project with `swift:5.3.2-amazonlinux2` container:

```
docker run \
--rm \
--volume "$(pwd)/:/src" \
--workdir "/src/" \
swift:5.3.2-amazonlinux2 \
swift build --product NotificationServer -c release -Xswiftc -static-stdlib
```

Fabian Fett gives a nice explanation in his excellent [blog post](https://fabianfett.de/getting-started-with-swift-aws-lambda-runtime) (Step 5) of all the parameters of this command.

Make a new folder `Scripts`, and add the script `package.sh` to it:

```
#!/bin/bash

set -eu

executable=$1

target=.build/lambda/$executable
rm -rf "$target"
mkdir -p "$target"
cp ".build/release/$executable" "$target/"
cd "$target"
ln -s "$executable" "bootstrap"
zip --symlinks lambda.zip *
```
Make it executable with `chmod +x scripts/package.sh`

Run the command `scripts/package.sh SquareNumberLocal` to make the zip file.

## Test the lambda function locally with localstack

Now we can test the lambda function, but we first need to create the lambda function in localstack with the command:
```
aws --endpoint-url http://localhost:4566 lambda create-function \
--function-name SquareNumber \
--runtime provided.al2 \
--role fakerole \
--handler lambda.run \
--zip-file fileb://.build/lambda/SquareNumberLocal/lambda.zip
```

This will output a result similar to this:

```
{
    "FunctionName": "SquareNumber",
    "FunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:SquareNumber",
    "Runtime": "provided.al2",
    "Role": "fakerole",
    "Handler": "lambda.run",
    "CodeSize": 20400688,
    "Description": "",
    "Timeout": 3,
    "LastModified": "2021-01-15T09:40:57.026+0000",
    "CodeSha256": "jQ3Ac8j5E3F0+XVn6RwuB8TsXHwQb/ITZemjrRc5W6Q=",
    "Version": "$LATEST",
    "VpcConfig": {},
    "TracingConfig": {
        "Mode": "PassThrough"
    },
    "RevisionId": "577c4b3b-cfa6-405c-901b-91b0d864ab5b",
    "State": "Active",
    "LastUpdateStatus": "Successful",
    "PackageType": "Zip"
}
```

Now we can invoke the lambda function, let's try to square the number 35:
```
aws --endpoint-url http://localhost:4566 lambda invoke \
--function-name SquareNumber \
--cli-binary-format raw-in-base64-out \
--payload '{"number": 35}' \
result.json
```
We will hopefully get this result:

```
{
    "StatusCode": 200,
    "LogResult": "",
    "ExecutedVersion": "$LATEST"
}
```

And if we inspect result.json, we should see the squared result:
```
{"result":1225}
```

## Conclusion
We are able to use localstack container to test our Swift lambda function locally. The next step would be to integrate with AWS APIGateway. But it looks like we then need to use the Pro version of localstack, because I get only errors when trying to set up APIGateway V2:

```
aws --endpoint-url http://localhost:4566 apigatewayv2 create-api \
--name sqn \
--protocol-type HTTP
```

This results in 404 Not Found from localstack.

The source is available from [my GitHub repository](https://github.com/imyrvold/SquareNumberLocal).
