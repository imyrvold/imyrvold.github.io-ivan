---
date: 2021-03-21 06:25
description: Rekognition Lambda Function with Swift
tags: lambda, aws, docker, swift
---
###### Published 2021-03-21
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
    let db = DynamoDB(client: awsClient, region: .euwest1)
    let rekognitionClient = Rekognition(client: awsClient)
    
    let futureRecords: [S3.Event.Record] = event.records

    let futureRecordsResult = futureRecords.map { record -> EventLoopFuture<Out> in
        let safeKey = record.s3.object.key.replacingOccurrences(of: "%3A", with: ":")
        let s3Object = Rekognition.S3Object(bucket: record.s3.bucket.name, name: safeKey)
        let image = Rekognition.Image(s3Object: s3Object)
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
            }
    }
    
    return EventLoopFuture<Out>.andAllSucceed(futureRecordsResult, on: context.eventLoop)
}
```
The handle function is called when the Lambda function is invoked by the S3 upload. The `event.records` parameter to the handle is a `S3.Event.Record`. For each of the records (photos), we get the S3 bucket (s3Object) and the image in the bucket, and constructs the `DetectLabelsRequest` request object. Then we use the `rekognitionClient` to request the labels in the image using the `detectLabelsRequest` object as parameter.

We put the labels as an array of strings into the dynamoDB database in AWS. We construct the `putRequest` object using  `PutItemCodableInput`. It constructs a dynamoDB request from any Codable input. Our codable object is this:

```
struct RekEntry: Codable {
    let image: String
    let labels: [String]
}
```
This ensures that the dynamoDB stores the image along with an array of labels. The `imageLabelsTable` is an environment variable that we provides from the infrastructure code in TypeScript (see next section for details):

```
const rekFn = new lambda.DockerImageFunction(this, 'recognitionFunction', {
  functionName: 'recognitionFunction',
  code: lambda.DockerImageCode.fromImageAsset(dockerfile),
  environment: {
    'TABLE': table.tableName,
    'BUCKET': imageBucket.bucketName
  },
  timeout: Duration.seconds(5)
});
```

## CDK Infrastructure Code

The CDK infrastructure code that builds the AWS infrastructure for the Lambda function, lives in the cdk folder. There are three files in the `cdk/lib` folder, `devhr-project-cicd-infra.ts`, which is the infrastructure code that builds the CI/CD pipeline, `devhr-project-stack.ts`, that builds the stack for DynamoDB database and the Lambda function. The `lambda-deployment.ts` file builds the pipeline stage that deploys the Lambda and DynamoDB from the `DevhrProjectStack` in the `devhr-project-stack.ts` file.

We will focus on the `DevhrProjectStack`:

```
import * as cdk from '@aws-cdk/core'
import * as s3 from '@aws-cdk/aws-s3'
import * as lambda from '@aws-cdk/aws-lambda'
import * as dynamodb from '@aws-cdk/aws-dynamodb'
import { Duration } from '@aws-cdk/core'
import * as iam from '@aws-cdk/aws-iam'
import * as event_sources from '@aws-cdk/aws-lambda-event-sources'

const imageBucketName = 'cdk-rekn-imagebucket'
```

We first import all the dependencies needed to build the Lambda function and the database.

```
export class DevhrProjectStack extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props)

    const dockerfile = '../';
```
The Lambda function is created with the new Container Image Support that was introduced a couple of months ago to help deploy Lambda function as a container image. We point to the dockerfile with the property `dockerfile` here. The `Dockerfile` itself is just a few lines:
```
FROM public.ecr.aws/o8l5c1i1/swift:5.3.2-amazonlinux2 as build
WORKDIR /src
COPY . .
RUN swift build --product RecognitionFunction -c release -Xswiftc -static-stdlib

FROM public.ecr.aws/lambda/provided:al2
COPY --from=build /src/.build/release/RecognitionFunction /main
ENTRYPOINT [ "/main" ]
```
It uses the amazon linux swift docker image that I have stored in the public ECR repository.

To continue with the CDK stack `DevhrProjectStack`,  we first create the S3 image bucket where we store the photo we send in:

```
// =================================================================================
// Image Bucket
// =================================================================================
const imageBucket = new s3.Bucket(this, imageBucketName, {
  bucketName: 'photobucket',
  removalPolicy: cdk.RemovalPolicy.DESTROY
})
new cdk.CfnOutput(this, 'imageBucket', { value: imageBucket.bucketName })
```

We then create the Amazon DynamoDB table for storing the photo and labels:

```
// =================================================================================
// Amazon DynamoDB table for storing image labels
// =================================================================================
const table = new dynamodb.Table(this, 'ImageLabels', {
  tableName: 'ImageLabels',
  partitionKey: { name: 'image', type: dynamodb.AttributeType.STRING },
  removalPolicy: cdk.RemovalPolicy.DESTROY
})
new cdk.CfnOutput(this, 'ddbTable', { value: table.tableName })
```

And last, we create the Lambda function itself, using the dockerfile which CDK will automatically build (using Swift):

```
        // =================================================================================
        // Building our AWS Lambda Function; compute for our serverless microservice
        // =================================================================================
        const rekFn = new lambda.DockerImageFunction(this, 'recognitionFunction', {
          functionName: 'recognitionFunction',
          code: lambda.DockerImageCode.fromImageAsset(dockerfile),
          environment: {
            'TABLE': table.tableName,
            'BUCKET': imageBucket.bucketName
          },
          timeout: Duration.seconds(5)
        });
        rekFn.addEventSource(new event_sources.S3EventSource(imageBucket, { events: [s3.EventType.OBJECT_CREATED] }))
        imageBucket.grantRead(rekFn)
        table.grantWriteData(rekFn)

        rekFn.addToRolePolicy(new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['rekognition:DetectLabels'],
          resources: ['*']
        }))
    }
}
```

## Test Rekognition with Lambda

With Terminal, we can now bootstrap the infrastructure code:

`cdk bootstrap \`
`--cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess \`
`aws://<your AWS Account ID>/eu-west-1`  


and deploy it: `cdk deploy`

When the pipeline have built the Lambda function, we can test it with a photo.
First, list all your S3 buckets with the command:
`aws s3 ls`

One of the buckets should have a name beginning with `lambdadeploymentstage...`.
Now, copy one photo from your hard drive to the S3 bucket, here is an example from my photo:
`aws s3 cp ~/Pictures/IMG_2032.JPG s3://lambdadeploymentstage-de-cdkreknimagebucketa588dc-joztsb6kb272`

Hopefully, that went ok, and you can make a scan from your DynamoDB database, to see if the Rekognition function in the Lambda function managed to see what is in the photo (we gave the table the name `ImageLabels` when we created the table with CDK):

`aws dynamodb scan --table-name ImageLabels`

```
{
    "Items": [
        {
            "image": {
                "S": "IMG_2032.jpeg"
            },
            "labels": {
                "L": [
                    {
                        "S": "Water"
                    },
                    {
                        "S": "Person"
                    },
                    {
                        "S": "Waterfront"
                    },
                    {
                        "S": "Pier"
                    },
                    {
                        "S": "Boardwalk"
                    },
                    {
                        "S": "Building"
                    },
                    {
                        "S": "Bridge"
                    },
                    {
                        "S": "Shoe"
                    },
                    {
                        "S": "Clothing"
                    },
                    {
                        "S": "Wood"
                    }
                ]
            }
        }
    ],
    "Count": 1,
    "ScannedCount": 1,
    "ConsumedCapacity": null
}
```

This is the list of labels I get when running the Lambda function. The photo is of me and my wife standing on a small wooden pier by a lake in the small village I was born in the swedish mountains.

![By the lake Ånnsjöen](/images/lambda/IMG_2032.jpeg)

## Conclusion

We have made a Lambda function with Swift and Soto, and verified it works by manually copying a photo to the S3 bucket, which triggers an S3 event to the Lambda function. The Lambda function uses the Rekognition function in AWS to generate a list of labels, which the Lambda function copies into a DynamoDB table together with the photo file name.

In my next blog post in this serial, I will build on the foundation we made here. 
