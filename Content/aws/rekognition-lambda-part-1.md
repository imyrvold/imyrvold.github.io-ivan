---
date: 2021-03-21 06:25
description: Rekognition Lambda Function with Swift
tags: lambda, aws, docker, swift
---
###### Published 2022-03-21
# Rekognition Lambda Function with Swift

Twitch has a video stream called [AWS Dev Hour: Building Modern Applications](https://www.twitch.tv/aws/video/891956043), an 8-episode series which uses CDK, [Cloud Development Kit](https://aws.amazon.com/cdk/) to build an application with Python. The application uses [AWS Lambda](https://aws.amazon.com/lambda/) and [AWS Rekognition](https://aws.amazon.com/rekognition/?blog-cards.sort-by=item.additionalFields.createdDate&blog-cards.sort-order=desc) together to get information about images you upload to [AWS S3](https://aws.amazon.com/s3/).

As I am very interested in AWS and CDK, I wondered if it was possible to use Swift instead of Python, and this blog post shows how to do it. The CDK itself uses TypeScript for the infrastructure code, as there is no support for Swift (yet). I will also use the infrastructure code I have built to support CI/CD, as this takes care of building the docker container for the Lambda function. This makes it possible to deploy everything with just a single `aws deploy` command. If you are interested in how I made the CI/CD infrastructure code, have a look at my previous blog post  [Make a continuous delivery of Swift Lambda in AWS](/aws/swift-lambda-ci-cd).

The development of the Lambda function in Swift took a long time and a lot of effort to do, and I wouldn't have made it without good help from Adam Fowler on the Vapor Discord channel, the developer of the [Soto for AWS](https://github.com/soto-project/soto), an absolutely remarkable Swift library for Amazon Web Services, and Fabian Fett, also a contributor of Soto.

I will try to follow the Twitch series, and plan to make a blog post for each episode. The full code base is available from my [GitHub account](https://github.com/imyrvold/DevhrProjectCICD).

![RekFunction](/images/lambda/rekfunction.png)

The figure shows the complete application infrastructure. This blog post will cover the rightmost Lambda function, the top green Photos Amazon S3 bucket, the Amazon DynamoDB, and the Amazon Rekognition. We will send photos manually (for now) with an `aws s3 cp` command into the green S3 bucket. This will trigger the AWS Lambda function, which will run the Swift code to get information about the image from Amazon Rekognition. The labels we get from AWS Rekognition (labels are just an array of strings that say something about the image, like e.g. "dog", "animal", "grass" if it is a photo of a dog) and save it to a DynamoDB database.

This sounds very complicated, but the Swift code to do this is actually very simple.

## Swift Package Manager

The Swift Lambda function uses `swift-aws-lambda-runtime` and `Soto`, so we have these as dependencies in Package.swift. The target has `AWSLambdaRuntime`, `AWSLambdaEvents`, `SotoS3`, `SotoRekognition` and `SotoDynamoDB` as dependencies.
```
// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RecognitionFunction",
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .upToNextMajor(from: "0.3.0")),
        .package(url: "https://github.com/soto-project/soto.git", from: "5.0.0"),
        // .package(name: "AWSSDKSwift", url: "https://github.com/swift-aws/aws-sdk-swift.git", from: "4.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "RecognitionFunction",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-runtime"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoRekognition", package: "soto"),
                .product(name: "SotoDynamoDB", package: "soto")
            ]),
        .testTarget(
            name: "RecognitionFunctionTests",
            dependencies: ["RecognitionFunction"]),
    ]
)
```

## Swift Lambda code

The `RekHandler` struct is the `EventLoopLambdaHandler` that controls the lifecycle of AWSClient. I used the [Soto guide](https://soto.codes/user-guides/using-soto-on-aws-lambda.html) to structure the handler:

```swift
import AWSLambdaRuntime
import AWSLambdaEvents
import SotoRekognition
import SotoDynamoDB

struct RekHandler: EventLoopLambdaHandler {
    typealias In = AWSLambdaEvents.S3.Event
    typealias Out = Void
    
    let minConfidence: Float = 50

    let awsClient: AWSClient
    
    init(context: Lambda.InitializationContext) {
        self.awsClient = AWSClient(httpClientProvider: .createNewWithEventLoopGroup(context.eventLoop))
    }
    
    func shutdown(context: Lambda.ShutdownContext) -> EventLoopFuture<Void> {
        let promise = context.eventLoop.makePromise(of: Void.self)
        awsClient.shutdown { error in
            if let error = error {
                promise.fail(error)
            } else {
                promise.succeed(())
            }
        }
        return context.eventLoop.makeSucceededFuture(())
    }

```

We will use `SotoRekognition` and `SotoDynamoDB`, so we import the libraries for these first.

When the lambda function is triggered by an upload of an image to `aws s3`, this is an `AWSLambdaEvents.S3.Event`, so we set the `typealias In` to this event.

The constant `minConfidence` is used by  `AWS Rekognition`, and specifies the minimum confidence level for the labels to return. Amazon Rekognition doesn't return any labels with confidence lower than this specified value.

```
func handle(context: Lambda.Context, event: In) -> EventLoopFuture<Out> {
    guard let record = event.records.first else { return context.eventLoop.makeFailedFuture(APIError.requestError) }
    let safeKey = record.s3.object.key.replacingOccurrences(of: "%3A", with: ":")
    let db = DynamoDB(client: awsClient, region: .euwest1)
    let s3Object = Rekognition.S3Object(bucket: record.s3.bucket.name, name: safeKey)
    let image = Rekognition.Image(s3Object: s3Object)
    let rekognitionClient = Rekognition(client: awsClient)
    let detectLabelsRequest = Rekognition.DetectLabelsRequest(image: image, maxLabels: 10, minConfidence: minConfidence)

    return rekognitionClient.detectLabels(detectLabelsRequest)
        .flatMap { detectLabelsResponse -> EventLoopFuture<Void> in
            guard let rekLabels = detectLabelsResponse.labels,
                  let imageLabelsTable = Lambda.env("TABLE") else {
                return context.eventLoop.makeSucceededFuture(())
            }
            
            // Instantiate a table resource object of our environment variable
            let labels = rekLabels.compactMap { $0.name }
            let rekEntry = RekEntry(image: safeKey, labels: labels)
            let putRequest = DynamoDB.PutItemCodableInput(item: rekEntry, tableName: imageLabelsTable)
            
            // Put item into table
            return db.putItem(putRequest)
                .flatMap { result in
                    return context.eventLoop.makeSucceededFuture(())
                }
        }.map { _ in }
}
```
The handle function is called when the Lambda function is invoked by the S3 upload. 
