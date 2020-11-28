import Foundation
import Publish
import Plot

// This type acts as the configuration for your website.
struct Ivan: Website {
    enum SectionID: String, WebsiteSectionID {
        // Add the sections that you want your website to contain here:
        case vapor
        case life
    }

    struct ItemMetadata: WebsiteItemMetadata {
        // Add any site-specific metadata that you want to use here.
    }

    // Update these properties to configure your website:
    var url = URL(string: "https://ivan.myrvold.blog")!
    var name = "Ivan's Blog"
    var description = "I live in a small beautiful seaside town in south Norway called Lillesand. My interests is in Web technologies, Cloud (AWS, Digital Ocean), Terraform, Ansible, server-side Swift, MacOS and iOS."
    var language: Language { .english }
    var imagePath: Path? { nil }
}

// This will generate your website using the built-in Foundation theme:
try Ivan().publish(withTheme: .foundation)
