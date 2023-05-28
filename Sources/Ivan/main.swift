import Foundation
import Publish
import Plot
import SplashPublishPlugin
import IvanPublishTheme
//import HighlightJSPublishPlugin

// This type acts as the configuration for your website.
struct Ivan: Website {
    enum SectionID: String, WebsiteSectionID {
        // Add the sections that you want your website to contain here:
        case projects
        case vapor
        case aws
        case ios
        case life
    }

    struct ItemMetadata: WebsiteItemMetadata {
        // Add any site-specific metadata that you want to use here.
    }

    // Update these properties to configure your website:
    var url = URL(string: "https://ivan.myrvold.blog")!
    var name = "Ivan C Myrvold"
    var description = "I live in a small beautiful seaside town in south Norway called Lillesand. My technical interests are in Web technologies, Cloud (AWS, DigitalOcean), Terraform, Ansible, Server-side Swift, MacOS and iOS."
    var language: Language { .english }
    var imagePath: Path? { nil }
}

// This will generate your website using the built-in Foundation theme:
//try Ivan().publish(using: [.installPlugin(.highlightJS())])

try Ivan().publish(
    withTheme: .ivan,
    plugins: [.splash(withClassPrefix: "")/*, .highlightJS()*/]
)
 
