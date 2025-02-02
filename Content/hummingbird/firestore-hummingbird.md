---
date: 2025-02-02 06:43
description: Using Hummingbird as Firestore API Server
tags: hummingbird, swift
---
###### Published 2025-02-02
# Using Hummingbird as Firestore API Server

## The project

I have successfully used Firestore as a database from Vapor, and decided I wanted to try out Hummingbird using the same method. I write the blog post mostly for my own sake to document every step in the process before I forget it. But I am happy if anyone else finds this blog post and find it useful.

When I first researched the internet with the help of Google to find if anyone else have done something similar, I came across the post [Getting Started with Firebase for Server-Side Swift](https://medium.com/atlas/getting-started-with-firebase-for-server-side-swift-93c11098702a) by Tyler Milner. The JWT and Vapor part of the post was outdated, as he used Vapor 2 and an older version of jwt-kit. But I got a lot of useful information out of this post, and wanted to use Hummingbird and jwt-kit to get the same result. And as Swift 6 is released now, I also wanted to use this even if it meant to having to grapple with Sendable protocol.

## Setting up Firebase

You need to create a new project in Firebase, or use an existing on that you want to connect to. I decided to call my project duved-1955.
![duved-1955](/images/vapor/duved-1955.png)

Click on **Firestore Database** in the sidebar, and then click the **Create database** button to create the Cloud Firestore.
![create-cloud-firestore](/images/vapor/create-cloud-firestore.png)
After setting the location of your database, You will see an empty project.
![empty-project](/images/vapor/empty-project.png)

Click project settings. This will open up the project settings window.
![project-settings](/images/vapor/project-settings.png)

Click the **Service accounts** tab, and then **Generate new private key** button.
![generate-private-key](/images/vapor/generate-private-key.png)

This will download a json file to your download folder. Open the json file with your favorite text editor, and find the private key value.

![duved_json](/images/vapor/duved_json.png)

 Copy that text into a new window. If you inspect the file, you will see that there are a number of "\n" in the file. Use a find and replace tool in your text editor, and replace them with an newline (If you use BBEdit, use "\\\n" in the Find field, and "\n" in the Replace field).

![google-private-key](/images/vapor/duved_replaced.png)

I named the file GooglePrivateKey.key

![google-private-key](/images/vapor/google_private_key.png)


Hummingbird expects to have the private key base64-encoded, so we will do that with this command:
`base64 -i GooglePrivateKey.key -o GooglePrivateKeyBase64.key`

Make a new .env file, and add a `FIREBASE_PRIVATE_KEY` environment variable with the content of the base64 file we just created. 
Also add an environment variable for `FIREBASE_SERVICE_ACCOUNT`,  `FIREBASE_KID` and `DOCUMENTS_URL`. The `SERVICE_ACCOUNT` you can find in the downloaded json file, with the key `client_email`.
`FIREBASE_KID` is the first part of the domain in the service account email address, and `DOCUMENTS_URL` should be like shown below, with the `KID` inserted in the middle of the URL:

![env-base64](/images/hummingbird/duved_env.png)

## Setting up Hummingbird
Make a new Hummingbird project with the following commands (I called my project duhum):

`git clone https://github.com/hummingbird-project/template duhum`

`cd duhum`

When running configure.sh, just accept the defaults by pressing return

`./configure.sh`

Now you can open the project from Xcode or Visual Studio if you prefer.

Open `Package.swift`, and add the dependencies so that it looks like this:

```swift
// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "duhum",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.19.0"),
    ],
    targets: [
        .executableTarget(name: "App",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdBcrypt", package: "hummingbird-auth"),
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
                .product(name: "HummingbirdBasicAuth", package: "hummingbird-auth"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "JWTKit", package: "jwt-kit"),
            ],
            path: "Sources/App"
        ),
        .testTarget(name: "AppTests",
            dependencies: [
                .byName(name: "App"),
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ],
            path: "Tests/AppTests"
        )
    ]
)
```


