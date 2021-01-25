---
date: 2021-01-25 12:00
description: Using APIGateway (version 1) with Swift Lambda - Part 1
tags: lambda, localstack, apigateway, aws, docker, swift
---
###### Published 2021-01-22
# Using Amazon API Gateway (Rest API) with Swift Lambda - Part 1

Amazon have now two different AWS services that can be used for connecting other AWS services, like Lambda, to HTTP endpoints. They are API Gateway (Rest API), and HTTP API. For me the names are a bit confusing, because both services are using http, but using the aws cli they are used as apigateway and apigatewayv2. The API HTTP (apigatewayv2) is the newest service, and the easiest to configure, but the Rest API (apigateway) is the service with the most functionality but also the most complicated one. In this three-part blog posts we will focus on the Rest API.

We will go through three integrations with Lambda, this first post will show you how to use the API Gateway to integrate with a GET method with query parameters. This means that you will be able to use a normal web browser to connect to the Lambda service, and supply parameters through the browsers query parameters. The next two posts will show how to integrate with a POST method with a JSON payload to get the same result, and the third blog post will show how to integrate with a GET method with path parameters.

The nice thing about this is that we don't have to modify the Swift Lambda code to integrate with these three different methods, all is done with using API Gateway and the supporting services.

I have used the [AWS Tutorial from Amazon](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-lambda.html) for these three blog posts, but I will be using the aws cli to set up everything, instead of using the AWS consoles from a browser.

## Swift Lambda code

The Lambda function is a simple function that acts as a simple calculator, and the parameters supplied to the function are the two numbers the function is to operate on, and one of the 4 operators (add, sub, mul, div).

We will make the new Lambda function by first make a new folder and then use Swift to init a new SPM project:
` mkdir calc && cd calc`
`swift package init --type executable`

We can open the project in Xcode by double-clicking the Package.swift file in Finder, or by doing `open Package.swift` in the Terminal.

Add `AWSLambdaRuntime` to the `Package.swift` file:
```
// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "calc",
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .upToNextMajor(from: "0.3.0"))
    ],

    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "calc",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
            ]),
        .testTarget(
            name: "calcTests",
            dependencies: ["calc"]),
    ]
)
```

Make a new file on the same level as `main.swift` with the name `APIError.swift` with the content:
```
import Foundation

enum APIError: Error {
    case decodingError
    case requestError
}
```
This enum can be expanded to add more error cases, now we just have a request error and a decoding error.

Make an extension folder at the same level as `main.swift`, and add the two files `APIGateway.Request+bodyObject.swift` and `APIGateway.Response+init.swift`:

```
import AWSLambdaEvents
import Foundation

extension APIGateway.Request {
    func bodyObject<D: Decodable>() throws -> D {
        guard let jsonData = body?.data(using: .utf8) else { throw APIError.requestError }
        let decoder = JSONDecoder()
        
        let object = try decoder.decode(D.self, from: jsonData)
        return object
    }
}
```
`APIGateway.Request+bodyObject.swift`

```
import AWSLambdaEvents
import Foundation

extension APIGateway.Response {
    public static let defaultHeaders = [
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT,DELETE",
        "Access-Control-Allow-Credentials": "true"
    ]
    
    public init(with error: Error, statusCode: AWSLambdaEvents.HTTPResponseStatus) {
        self.init(
            statusCode: statusCode,
            headers: APIGateway.Response.defaultHeaders,
            multiValueHeaders: nil,
            body: "{\"error\":\"\(String(describing: error))\"}",
            isBase64Encoded: false
        )
    }
    
    public init<Out: Encodable>(with object: Out, statusCode: AWSLambdaEvents.HTTPResponseStatus) {
        var body: String = "{}"
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(object) {
            body = String(data: data, encoding: .utf8) ?? body
        }
        self.init(
            statusCode: statusCode,
            headers: APIGateway.Response.defaultHeaders,
            multiValueHeaders: nil,
            body: body,
            isBase64Encoded: false
        )
    }
}

struct EmptyResponse: Encodable {}
```
`APIGateway.Response+init.swift`

These two extensions simplifies the Lambda handler code we will add next. Add the file `CalcHandler.swift` on the same level as `main.swift` with the content:
```
import AWSLambdaRuntime
import AWSLambdaEvents
import NIO
import Foundation

struct Input: Codable {
    enum OPER: String, Codable {
        case add
        case sub
        case mul
        case div
    }
    let a: Double
    let b: Double
    let op: OPER
}

struct Output: Codable {
    let result: Double
}

struct CalcHandler: EventLoopLambdaHandler {
    typealias In = APIGateway.Request
    typealias Out = APIGateway.Response
    

    func handle(context: Lambda.Context, event: In) -> EventLoopFuture<Out> {
        guard let input: Input = try? event.bodyObject() else {
            return context.eventLoop.makeSucceededFuture(APIGateway.Response(with: APIError.requestError, statusCode: .badRequest))
        }
        let output: Output
        
        switch input.op {
        case .add:
            output = Output(result: input.a + input.b)
        case .sub:
            output = Output(result: input.a - input.b)
        case .mul:
            output = Output(result: input.a * input.b)
        case .div:
            output = Output(result: input.a / input.b)
        }
        
        let apigatewayOutput = APIGateway.Response(with: output, statusCode: .ok)
        
        return context.eventLoop.makeSucceededFuture(apigatewayOutput)
    }
}
```
The `handler` function in the `CalcHandler` struct is the function that will receive the request from API Gateway, with the event containing the `Input` payload. We use a `switch` to find out which operation the user wants, and returns the response containing the result of the operation.

The last thing we need to do is to instantiate the `CalcHandler` in `main.swift`:

```
import AWSLambdaRuntime

Lambda.run(CalcHandler())
```

This makes the Lambda handler complete, and we proceed with compile and zip it.

## Compile Swift Lambda function with Amazonlinux2 docker container
We must compile and pack the Lambda function with Amazon Linux 2, so it can run on the AWS cloud platform.
Luckily, we have a swift image prepared for Amazon Linux 2, so we can just run it and compile our Lambda function with it:

`docker run \
--rm \
--volume "$(pwd)/:/src" \
--workdir "/src/" \
swift:5.3.2-amazonlinux2 \
swift build --product calc -c release -Xswiftc -static-stdlib`

Check out the excellent [blog post](https://fabianfett.de/getting-started-with-swift-aws-lambda-runtime) (Step 5) by Fabian Fett for an explanation of the parameters.

Make a `scripts` folder for the `package.sh` shell script that we use to zip the Lambda function that we compiled:
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
Remember to make it executable with `chmod +x scripts/package.sh`

Now we can run the script to zip the compiled Lambda function: `scripts/package.sh calc`

The zipped file can be found under `.build/lambda/calc/lambda.zip`

## AWS API Gateway setup
The setup of the AWS infrastructure to make API Gateway work is a bit complicated, so I have prepared a shell script, `setup_aws.sh` to set the service and Lambda function in AWS.
Another shell script `delete_aws.sh` is used to tear down the infrastructure in AWS. This makes it easier to handle the complicated setup.
The setup script stores the results of the scripts in the `results/aws` folder, so we have to make this folder first with `mkdir -p results/aws`

I will explain the steps made in the setup script, but the complete project with swift code and the scripts can be cloned from my GitHub repository.

## AWS Constants
The following constants which the script uses:
`FUNCTION_NAME=Calc`
The named used for the Lambda function.

`API_NAME=LambdaCalc`
The name we give to the Rest API in API Gateway.

`RESOURCE_NAME=calc`
The resource name given to the API Gateway resource. This name is also used in the endpoint url to the Lambda function.

`POLICY_NAME=lambda_execute`
The name of the `iam` policy we use to attach to the `iam` role.

`ROLE_NAME=lambda_invoke_function_assume_apigw_role`
The name of the execution role of the Lambda function.

## IAM role and policy
We need to create an execution role for the Lambda function, and an iam policy to attach to the role.
Make the json file with the policy in the scripts folder with name `Invoke-Function-Role-Trust-Policy.json`:
```
{
   "Version":"2012-10-17",
   "Statement":[
      {
         "Effect":"Allow",
         "Action":"lambda:InvokeFunction",
         "Resource":"*"
      }
   ]
}
```
We creates the policy first with:
```
aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file://Invoke-Function-Role-Trust-Policy.json \
    > ../results/aws/create-policy.json
```
We can check the `create-policy.json` to see the result of the command.

Before we can create the role, we need another policy, `Assume-STS-Role-Policy.json` file in the scripts folder:
```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "apigateway.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
} 
```
Now we can create the role:
```
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://Assume-STS-Role-Policy.json \
    > ../results/aws/create-role.json
```


