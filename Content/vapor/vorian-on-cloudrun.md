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

## PriceJob

I wanted first to make a service that runs every day at 14:00, when the electricity prices for the next day is available, and save them to a MongoDB database. I investigated several solutions, first as running the job as a Vapor job, but then I found out that Google has a server-less service called Cloud Run, that could run a docker container as a job at intervals I could set.

I configured the trigger for the job to execute every day at 14:00
![Pricejob history](/images/vapor/pricejob-trigger.png)

And the service has been running now daily for the last three weeks perfectly.
![Pricejob history](/images/vapor/pricejob-history.png)

The Swift code to realize this was quite simple. I first thought I would code this as a Vapor server, but then I thought I would try to use Hummingbird, which is a more lightweight server side Swift project.

The source code for the project is at https://github.com/shortcut/PriceJob, for those that have access to shortcut private repositories.

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

