import SwiftUI

@main
struct HappyBirthdayApp: App {
    var body: some Scene {
        WindowGroup {
            // Step 1 launches with empty details so the button starts disabled.
            // Editing and persistence are step 2.
            DetailsView(details: BirthdayDetails())
        }
    }
}
