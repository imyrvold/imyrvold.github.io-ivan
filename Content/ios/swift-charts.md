---
date: 2022-07-13 16:50
description: First look at Swift Charts
tags: ios, swift, charts
---
###### Published 2022-07-13
# First look at Swift Charts

## Using Charts ##

At last months WWDC Apple unveiled Swift Charts for SwiftUI, a new Swift library that enables a SwiftUI developer to make beautiful charts in the same declarative way that many of us have enjoyed with SwiftUI. In the app that I have been the lead iOS developer for the last 1.5 years, we use many charts, and the library we have been using is also called `Charts` [Charts](https://github.com/danielgindi/Charts), and I have been impressed by the charts we have been able to produce with it.  

The first thought I had when Apple showed the new Swift Charts library at WWDC, was if this could be a replacement for the Charts library we had been using? So for the last couple of days, I started my mission to see what I could do with one of the charts we have in the app. The result is at the short video at the end of this blog post, and as you can see, the result is quite impressive.

## Prepare the data ##

I have rebuilt the app I am developing in my day job as a SwiftUI app, using iOS 16. That have been my private project for the last year, and in my last revision, I have replaced the Charts library with the new Swift Charts from Apple. I get the data as JSON from a backend server:

```
{
  "values" : [
    372.55000000000001,
    362.26299999999998,
    361.01299999999998,
    359.77499999999998,
    358.46300000000002,
    355.17500000000001,
    338.72500000000002,
    356.83800000000002,
    388.06299999999999,
    408.26299999999998,
    409.28800000000001,
    401.85000000000002,
    372.988,
    326.22500000000002,
    328.92500000000001,
    360.17500000000001,
    394.67500000000001,
    420.94999999999999,
    426.30000000000001,
    446.51299999999998,
    428.33800000000002,
    424.25,
    424.57499999999999,
    413.363
  ],
  "toDate" : "2022-07-13T00:00:00",
  "maxValue" : 446.51299999999998,
  "minValue" : 326.22500000000002,
  "fromDate" : "2022-07-12T00:00:00",
  ...
  ...
  ...
```
The `values` part is the 24 hours of electricity energy cost in norwegian øre from hour 00 through hours 23. And the `fromDate` and `toDate` is the start and end hours of the values. Now I want to show the energy prices during the day as a line chart.

The JSON is decoded into a struct:

```swift
struct CodableEnergyPrice: Decodable {
    let fromDate: Date
    let toDate: Date
    let maxValue: Double?
    let minValue: Double?
    let values: [Double]
}
```

and the struct have a computed property `energyPriceData`, that produces the simple struct that holds the charts data we will use in the line chart:

```swift
    var energyPriceData: EnergyPriceData {
        var data: [EnergyPriceDataValue] = []
        var hoursInt: [Int] = []
        hoursInt += 0...23
        let hours: [Date] = hoursInt.map { Calendar.current.date(byAdding: .hour, value: Int($0), to: fromDate) ?? fromDate }

        values.indices.forEach { index in
            data.append(EnergyPriceDataValue(hour: hours[index], øre: Int(values[index].rounded()), color: "blue"))
        }
        let minValue = minValue ?? 0
        let maxValue = maxValue ?? 1000
        let min = Int(minValue.rounded(.towardZero))
        let max = Int(maxValue.rounded(.awayFromZero))
        return EnergyPriceData(min: min, max: max, values: data)
    }
```

The `EnergyPriceData` is a very simple struct:

```swift
struct EnergyPriceDataValue: Identifiable {
    var id: String { UUID().uuidString }
    let hour: Date
    let øre: Int
    let color: String
}

struct EnergyPriceData {
    let min: Int
    let max: Int
    let values: [EnergyPriceDataValue]
}
```


 

<video controls>
    <source src="/movies/Strømprisen-min.mov" type="video/mp4">
</video>

