---
date: 2023-07-31 20:01
description: Vorian SwiftUI app with Vapor backend
tags: vapor, hummingbird, cloudbuild, cloudrun, mongodb
---
###### Published 2023-07-31
# Vorian SwiftUI app with Vapor backend

## The project

My summer 2023 hobby project was to build a SwiftUI app that shows the norwegian electricity price during the day, and have a server side Swift backend, using Vapor. I also wanted to run the Vapor backend in docker containers, on Google cloud. I only worked on the project during rainy days, and as we had a lot of rain in July, the project progressed rapidly.

I quickly found out that Google has a server-less service called Cloud Run that would be perfect for the job, and the Google Cloud Build could build the docker containers by pulling the source code from Github with continuous integration, i.e. whenever I pushed to Github, a new docker container would be built.

I found a server that daily serves the electricity prices as a free service, and I made another service running on Google Cloud Run Jobs that pulls the daily prices for the next day every day at 14:00, and insert them as a document into a MongoDB Atlas database. This service runs as another server-side Swift service, not on Vapor, but on Hummingbird.

I am happy to say that now all the services are running on Google Cloud, the Vorian SwiftUI project is progressing well, not quite finished yet, but I think it looks promising. I am using both Swift Charts that was introduced during WWDC last year and SwiftData that was introduced in June this year.

## MongoDB Atlas

The database I use for the backend is MongoDB Atlas, which I have used for a few years. I love using a NoSQL database, and have used MongoDB for a few projects. The first project I used it for was a backend server I built 5 years ago for a company in Kristiansand using Node.js

## UserModelsPackage

The big advantage for developing both the frontend and the backend using the same language, is that we can share code between the platforms. I have used this with the Swift Package UserModelsPackage. Source is at [UserModelsPackage](https://github.com/shortcut/UserModelsPackage). In UserModelsPackage, I have Swift models that is shared between the Vorian SwiftUI app, and the backend micro services.

## PriceJob

I wanted first to make a service that runs every day at 14:00, when the electricity prices for the next day is available, and save them to a MongoDB database. I investigated several solutions, first as running the job as a Vapor job, but then I found out that Google has a server-less service called Cloud Run, that could run a docker container as a job at intervals I could set.

I configured the trigger for the job to execute every day at 14:00
![Pricejob history](/images/vapor/pricejob-trigger.png)

And the service has been running now daily for the last three weeks perfectly.
![Pricejob history](/images/vapor/pricejob-history.png)

The Swift code to realize this was quite simple. I first thought I would code this as a Vapor server, but then I thought I would try to use Hummingbird, which is a more lightweight server side Swift project.

The source code for the project is at [PriceJob](https://github.com/shortcut/PriceJob), for those that have access to shortcut private repositories.

```swift
import MongoQueue
import MongoKitten
import AsyncHTTPClient
import UserModelsPackage
import Foundation
import NIOCore
import NIOFoundationCompat


struct DailyElectricityPriceJob: ScheduledTask {
    var taskExecutionDate: Date {
        Date()
    }
        
    func execute(withContext context: Context) async throws {
        let regions = ["NO1", "NO2", "NO3", "NO4", "NO5"]
        print("DailyElectricityPriceJob", #function)

        for region in regions {
            let prices = try await getElectricityPrices(with: context.client, at: region)
            let priceCollection = context.db["dailyprice"]
            for price in prices {
                let dailyPrice = DailyPrice.price(for: price, at: region)
                try await priceCollection.insertEncoded(dailyPrice)
            }
        }
    }

    private func getElectricityPrices(with client: HTTPClient, at area: String) async throws -> [HvaKosterStrømmen] {
        guard let date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return [] }
        let year = Calendar.current.component(.year, from: date)
        let month = Calendar.current.component(.month, from: date)
        let monthString = String(format: "%02d", month)
        let day = Calendar.current.component(.day, from: date)
        let dayString = String(format: "%02d", day)
        let url = "https://www.hvakosterstrommen.no/api/v1/prices/\(year)/\(monthString)-\(dayString)_\(area).json"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        let ds = dateFormatter.string(from: Date.now)
        print(ds, url)
        
        let request = HTTPClientRequest(url: url)
        let response = try await client.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 1024 * 1024)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let hvaKosterstrømmen = try decoder.decode([HvaKosterStrømmen].self, from: body)
        print(hvaKosterstrømmen)

        return hvaKosterstrømmen
    }

    func onExecutionFailure(failureContext: QueuedTaskFailure<Context>) async throws -> TaskExecutionFailureAction {
        print("DailyElectricityPriceJob failed 😰")
        return .dequeue()
    }
}
```

## UsersService

The source code for this project is at [UsersService](https://github.com/shortcut/UsersService).
I have a few years ago made a Vapor project to authenticate a user, returning JWT access token and refresh token to the user so that he can access protected API endpoints. I thought that this would be perfect for authenticating the Vorian SwiftUI app. As there have been a few years since developing this, I wanted to modernize the project, and replace the Fluent ORM I used at the time with [MongoKitten](https://github.com/orlandos-nl/MongoKitten) and Meow ORM, which are dedicated frameworks for MongoDB (I think that Joannis Orlandos that is the developer and maintainer of these frameworks have a soft spot for cats 😄). This was a new framework that I haven't used before, so I had to have a few sessions with Joannis on his Discord server to make progress. I also used these frameworks for PriceJob and ContentService too.

I used the same procedure as for the PriceJob service, to use Cloud Build to build the docker container every time there is a push to the GitHub repository, and save it to my personal Docker Hub. Unfortunately, I couldn't use a complete CI/CD for this with Cloud Build, but I hope that this will be possible in the future. Now only the Continuous Integration part of it is working, and I have to go to Cloud Run to push a button to make a new revision of the service after it has been built. If I had developed the docker container with one of the Google supported languages, that would have worked. But that is a minor annoyance. Cloud Build takes around 12-14 minutes to complete the build of the docker container.

```swift
import Vapor
import JWT
import SendGrid
import Meow
import UserModelsPackage

final class AuthController: RouteCollection {
    private let sendGridClient: SendGridClient
    
    init(sendGridClient: SendGridClient) {
        self.sendGridClient = sendGridClient
    }
    
    func boot(routes: RoutesBuilder) throws {
        routes.post("register", use: register)
        routes.post("login", use: login)
        routes.post("accessToken", use: refreshAccessToken)
    }
    
    func register(_ request: Request) async throws -> UserResponse {
        let userInput = try request.content.decode(RegisterRequest.self)
        let inputUser = try User(id: ObjectId(), email: userInput.email, firstName: userInput.firstName, lastName: userInput.lastName, password: userInput.password)
        let user = try await request.meow[User.self].findOne { user in
            user.$email == inputUser.email
        }
        if user != nil {
            throw Abort(.badRequest, reason: "This email is already registered!")
        }

        try await inputUser.save(in: request.meow)
        
        let subject = "Your Registration"
        let body = "Welcome!"
        
        return UserResponse(user: inputUser)
    }
    
    func login(_ request: Request) async throws -> LoginResponse {
        let data = try request.content.decode(LoginInput.self)
        let user = try await request.meow[User.self].findOne { user in
            user.$email == data.email
        }
        guard let user else { throw Abort(.unauthorized) }

        var check = false
        do {
            check = try Bcrypt.verify(data.password, created: user.password)
        } catch {}
        guard check else { throw Abort(.unauthorized) }
        let userPayload = Payload(id: user._id, email: user.email)
        do {
            let accessToken = try request.application.jwt.signers.sign(userPayload)
            let refreshPayload = RefreshToken(user: user)
            let refreshToken = try request.application.jwt.signers.sign(refreshPayload)
            let userResponse = UserResponse(user: user)
            
            try await user.save(in: request.meow)

            return LoginResponse(accessToken: accessToken, refreshToken: refreshToken, user: userResponse)
        } catch {
            throw Abort(.internalServerError)
        }
    }
    
    func refreshAccessToken(_ request: Request) async throws -> RefreshTokenResponse {
        let data = try request.content.decode(RefreshTokenInput.self)
        let refreshToken = data.refreshToken
        let jwtPayload = try request.application.jwt.signers.verify(refreshToken, as: RefreshToken.self)
        
        let userID = jwtPayload.id
        let user = try await request.meow[User.self].findOne { user in
            user.$_id == userID
        }
        guard let user else { throw Abort(.unauthorized) }

        let payload = Payload(id: user._id, email: user.email)
        let accessToken = try? request.application.jwt.signers.sign(payload)
        let refreshPayload = RefreshToken(user: user)
        let newRefreshToken = try? request.application.jwt.signers.sign(refreshPayload)
        
        try await user.save(in: request.meow)
        guard let accessToken, let newRefreshToken else { throw Abort(.badRequest) }
        
        return RefreshTokenResponse(accessToken: accessToken, refreshToken: newRefreshToken)
    }
}
```

## ContentService

Source at [ContentService](https://github.com/shortcut/ContentService).
The ContentService project is also based on Vapor, and using Meow as the MongoDB ORM. The idea behind ContentService is to be a micro service for only the content of the SwiftUI Vorian app. As the UsersService backend takes care of login, registering, and refreshing access tokens, the ContentService is returning the electricity price content, the home screen content and any other content that the app will use in the future. It shares the models with the SwiftUI Vorian app using the SPM UserModelsPackage package.

The big advantage using the JSON Web Token (JWT) is that the backend server doesn't need to save the tokens, it only have to validate the access tokens that the user sends in the header. The JWKS public private keypair is added to the container in Cloud Run as an environment variable from Googles Secret Manager at run time, and is used to verify the tokens the user is sending in the http Authorization header. This is done automatically by Vapor with the verify function in the Payload struct.

