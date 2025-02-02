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


Our project expects to have the private key base64-encoded, so we will do that with this command:
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

## Middleware

Add a Middleware folder under the App folder, and add a Swift file named `JWTAuthenticator`. This is the middleware that we will use to authenticate the api requests from clients that have been authenticated by Firebase. That could be an iOS or Android app that uses Firebase.

The file should look like this:

```swift
import Foundation
import Hummingbird
import HummingbirdAuth
import JWTKit
import NIOFoundationCompat

struct FirestorePayload: JWTPayload, Equatable {
    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
        case issuedAt = "iat"
        case issuer = "iss"
        case audience = "aud"
        case scope
    }
    var expiration: ExpirationClaim
    var issuedAt: IssuedAtClaim
    var issuer: IssuerClaim
    var audience: AudienceClaim
    var scope: String
    
    func verify(using algorithm: some JWTKit.JWTAlgorithm) async throws {
        try self.expiration.verifyNotExpired()
    }
    
}

struct JWTAuthenticator: AuthenticatorMiddleware, @unchecked Sendable {
    typealias Context = AppRequestContext
    let jwtKeyCollection: JWTKeyCollection

    init(jwksData: ByteBuffer) async throws {
        let jwks = try JSONDecoder().decode(JWKS.self, from: jwksData)
        self.jwtKeyCollection = JWTKeyCollection()
        try await self.jwtKeyCollection.add(jwks: jwks)
    }

    func authenticate(request: Request, context: Context) async throws -> User? {
        // get JWT from bearer authorisation
        guard let jwtToken = request.headers.bearer?.token else { throw HTTPError(.unauthorized) }

        let payload: FirebaseJWTPayload
        do {
            payload = try await self.jwtKeyCollection.verify(jwtToken, as: FirebaseJWTPayload.self)
            if payload.expirationAt.value < Date.now || payload.subject.value.isEmpty || payload.userID.isEmpty {
                throw HTTPError(.unauthorized)
            }
        } catch {
            context.logger.debug("couldn't verify token")
            throw HTTPError(.unauthorized)
        }

        return User(userID: payload.userID, email: payload.email)
    }
    
}

public struct FirebaseJWTPayload: JWTPayload {
    public func verify(using algorithm: some JWTKit.JWTAlgorithm) async throws {
        guard issuer.value.contains("securetoken.google.com") else {
            throw JWTError.claimVerificationFailure(failedClaim: IssuerClaim(value: issuer.value), reason: "Claim wasn't issued by Google")
        }
        guard subject.value.count <= 256 else {
            throw JWTError.claimVerificationFailure(failedClaim: SubjectClaim(value: subject.value), reason: "Subject claim beyond 255 ASCII characters long.")
        }
        try expirationAt.verifyNotExpired()
    }
    
    enum CodingKeys: String, CodingKey {
        case issuer = "iss"
        case subject = "sub"
        case audience = "aud"
        case issuedAt = "iat"
        case expirationAt = "exp"
        case email = "email"
        case userID = "user_id"
        case picture = "picture"
        case name = "name"
        case authTime = "auth_time"
        case isEmailVerified = "email_verified"
        case phoneNumber = "phone_number"
    }
    
    /// Issuer. It must be "https://securetoken.google.com/<projectId>", where <projectId> is the same project ID used for aud
    public let issuer: IssuerClaim
    
    /// Issued-at time. It must be in the past. The time is measured in seconds since the UNIX epoch.
    public let issuedAt: IssuedAtClaim
    
    /// Expiration time. It must be in the future. The time is measured in seconds since the UNIX epoch.
    public let expirationAt: ExpirationClaim
    
    /// The audience that this ID token is intended for. It must be your Firebase project ID, the unique identifier for your Firebase project, which can be found in the URL of that project's console.
    public let audience: AudienceClaim
    
    /// Subject. It must be a non-empty string and must be the uid of the user or device.
    public let subject: SubjectClaim
    
    /// Authentication time. It must be in the past. The time when the user authenticated.
    public let authTime: Date?
    
    public let userID: String
    public let email: String?
    public let picture: String?
    public let name: String?
    public let isEmailVerified: Bool?
    public let phoneNumber: String?
}
```

We need to create a User file, that `JWTAuthenticator` returns as part of the authentication process. Add a Models folder under App, and add a User.swift file, that should look like this:

```swift
import HummingbirdBcrypt
import Foundation
import Hummingbird
import HummingbirdAuth
import HummingbirdBasicAuth
import NIOPosix

final class User: PasswordAuthenticatable, @unchecked Sendable {
    var userID: String
    var email: String?
    var passwordHash: String?

    init(userID: String, email: String?, passwordHash: String? = nil) {
        self.userID = userID
        self.email = email
        self.passwordHash = passwordHash
    }

    init(from userRequest: CreateUserRequest) async throws {
        self.userID = userRequest.userID
        self.email = userRequest.email
    }
}

struct CreateUserRequest: Decodable {
    let userID: String
    let email: String

    init(userID: String, email: String) {
        self.userID = userID
        self.email = email
    }
}

/// User encoded into HTTP response
struct UserResponse: ResponseCodable {
    let userID: String
    let email: String?

    init(userID: String, email: String?) {
        self.userID = userID
        self.email = email
    }

    init(from user: User) {
        self.userID = user.userID
        self.email = user.email
    }
}
```

Finally, we need to edit the `Application+build` file, to set up the authentication and controllers.

```swift
import Hummingbird
import Logging
import AsyncHTTPClient
import HummingbirdAuth
import JWTKit
import ServiceLifecycle
import Foundation

public protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
    var logLevel: Logger.Level? { get }
}

typealias AppRequestContext = BasicAuthRequestContext<User>

///  Build application
/// - Parameter arguments: application arguments
public func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    let environment = Environment()
    let logger = {
        var logger = Logger(label: "fishum")
        logger.logLevel =
            arguments.logLevel ??
            environment.get("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ??
            .info
        return logger
    }()
    let jwtAuthenticator: JWTAuthenticator
    let env = try await Environment.dotEnv()

    guard let jwksUrl = env.get("JWKS_URL") else {
        logger.error("JWTAuthenticator initialization failed getting environment vars")
        throw HTTPError(.unauthorized, message: "JWTAuthenticator initialization failed")
    }
    let httpClient = HTTPClient.shared

    do {
        let request = HTTPClientRequest(url: jwksUrl)
        let jwksResponse: HTTPClientResponse = try await httpClient.execute(request, timeout: .seconds(20))
        let jwksData = try await jwksResponse.body.collect(upTo: 1_000_000)
        jwtAuthenticator = try await JWTAuthenticator(jwksData: jwksData)
    } catch {
        logger.error("JWTAuthenticator initialization failed")
        throw error
    }

    let router = Router(context: AppRequestContext.self)
    router.add(middleware: LogRequestsMiddleware(.debug))
  
//    let firestoreService = await FirestoreService(logger: logger)
  
//  TodoController(jwtAuthenticator: jwtAuthenticator, firestoreService: firestoreService)
//    .addRoutes(to: router.group("api/todo"))

    router.group("auth")
        .add(middleware: jwtAuthenticator)
        .get("/") { request, context in
            guard let user = context.identity else { throw HTTPError(.unauthorized) }
            return "Authenticated (Subject: \(user.email ?? "unknown"))"
        }


    let app = Application(
        router: router,
        configuration: .init(
            address: .hostname(arguments.hostname, port: arguments.port),
            serverName: "fishum"
        ),
        logger: logger
    )
    return app
}
```

Now is the time to build the project. It should build, if it doesn't go through the code and see if you have missed something in the process. We will uncomment the commented lines in the `Application+build` in the next sections.

## Login to our project

When we get an API request, we need to authenticate it and see that we have the request coming from a user that have logged in with a Firebase auth process. That could be via web, or from a mobile app. I am mostly familiar doing this from a mobile app, so that is how I will set it up. We will not need to build a mobile app, but only set this up in Firebase, so we can log in with `curl`.

When the request have been authenticated with the JWTAuthenticator middleware, we need to create a Bearer token so we can send a request to Firestore API with this token embedded in the Authorization header. Doing it this way we can request data from a Firestore collection or set or update data in the Firestore collection. We can even send push notifications with this. I have built an API in Vapor doing this, and now with Hummingbird we can do it with this project.

First we need to find the Web API Key. Go to Project settins in Firebase, the General tab, and find the web api key there, as like this:

![env-base64](/images/hummingbird/web_api_key.png)

We also need to create a login user, so we can test the login:

![env-base64](/images/hummingbird/login_user.png)

Now, use this api key in the following curl cli command, to see if we can get a secure token from Firebase.

```
curl -i --request POST \
--header "Content-Type: application/json" \
--data-binary '{"email": "donald@duck.no", "password": "donald", "returnSecureToken": true}' \
https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=AIzaSy...
```

This should result in a HTTP 200 response like the following:

![env-base64](/images/hummingbird/login_response.png)

This proves that we can get an secure token, and we can use that to test our projects authentication process.

In the file `Application+build`, after the `router.group("auth")` just below the `guard statement`, add the following print statement to see that we get the user email and userID correctly and that the JWTAuthenticator have fully authorized the login user:

`print("user:", user.email ?? "unknown", "id:", user.userID)`

But before we run the project, make sure to set the custom working directory correctly if you are using Xcode, or else we will get an error thet the project have not read the environment variables. Select `Edit schemas` from the top of the Xcode window, and set the custom working directory to the directory where you have your project. Mine is like this:

![env-base64](/images/hummingbird/custom_working_directory.png)

Now run the project, and run the following cli command, but replace the token following the Bearer with the token we received from the login cli command above.

![env-base64](/images/hummingbird/curl_auth.png)

Xcode's console should now have printed both the email and userID.

## Add Todo controller and FirestoreService
