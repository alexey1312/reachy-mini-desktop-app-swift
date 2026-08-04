import ProjectDescription

let tuist = Tuist(
    fullHandle: "alexey1312/reachy-mini-desktop-app-swift",
    project: .tuist(
        // A set `fullHandle` otherwise makes generation require a tuist.dev session,
        // which CI has none of — this repo is not connected to the server project.
        generationOptions: .options(optionalAuthentication: true)
    )
)
