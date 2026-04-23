# knowledged-mac

`knowledged-mac` is a native macOS client for the [`knowledged`](https://github.com/wiztools/knowledged) HTTP API. It gives you a single-window SwiftUI app for posting content, retrieving knowledge, deleting documents, and browsing recent posts without dropping to the CLI.

## Features

- Post new content with an optional hint and comma-separated tags
- Retrieve content by natural-language query or exact repo-relative file path
- Switch retrieval output between synthesized answers and raw source documents
- Save retrieved results to disk
- Delete stored documents by path
- Browse recent posts and jump straight back into the Retrieve tab
- Configure the backend server URL from the app's Settings window

## Requirements

- macOS 14.0 or later
- Xcode 15+ for local development
- A running `knowledged` server reachable over HTTP, typically `http://localhost:9090`

For backend setup, see [`../knowledged/README.md`](../knowledged/README.md).

## Build

Open the project in Xcode:

```sh
open KnowledgedMac.xcodeproj
```

Or build from the command line:

```sh
xcodebuild \
  -project KnowledgedMac.xcodeproj \
  -scheme KnowledgedMac \
  -configuration Debug \
  -derivedDataPath /tmp/knowledged-mac-build \
  build
```

To create a Release build and copy the app into `/Applications`, use:

```sh
./bld.sh
```

## Run

1. Start the `knowledged` backend.
2. Launch `KnowledgedMac.app` from Xcode, `/Applications`, or the built product in DerivedData.
3. Open Settings with `Cmd+,` and confirm the server URL.
4. Click `Test` in Settings to verify the connection.

The Settings health check requests `INDEX.md` from the backend, so the server should be pointed at a valid knowledged repository.

## Tabs

### Post

Use the Post tab to submit new content to the backend. The app shows queue/polling progress and resets the form after a successful write.

### Retrieve

Use Retrieve in one of two ways:

- `Query`: ask a natural-language question and choose `Synthesize` or `Raw Docs`
- `File Path`: fetch a specific file by repo-relative path

Retrieved content can be viewed as rendered Markdown or raw text and saved to disk.

### Delete

Delete removes a stored document by repo-relative path and waits for the backend job to finish.

### Recents

Recents lists recently posted items returned by the backend. Clicking an entry opens its path in the Retrieve tab. Clicking the copy icon copies the full path; double-clicking copies only the filename.

## Keyboard shortcuts

- `Cmd+N`: show the Post tab
- `Cmd+S`: show the Retrieve tab
- `Cmd+,`: open Settings
- `Cmd+Return`: run the primary action in the active form

`Cmd+Return` posts content in Post, runs a retrieval in Retrieve, and confirms deletion in Delete.

## Project layout

```text
knowledged-mac/
├── KnowledgedMac/              # SwiftUI app source
├── KnowledgedMac.xcodeproj/    # Xcode project
├── bld.sh                      # Release build + install helper
└── LICENSE
```

## License

See [`LICENSE`](LICENSE).
