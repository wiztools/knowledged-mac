# knowledged-mac

`knowledged-mac` is a native macOS client for the [`knowledged`](https://github.com/wiztools/knowledged) HTTP API. It gives you a single-window SwiftUI app for posting content, retrieving knowledge, browsing tags, editing documents, deleting documents, and browsing recent posts without dropping to the CLI.

## Features

- Post new content with an optional hint and comma-separated tags
- Retrieve content by natural-language query or exact repo-relative file path
- Switch retrieval output between synthesized answers and raw source documents
- Save retrieved results to disk
- Browse tags and open tagged documents
- Edit existing Markdown documents by path
- Delete stored documents by path
- Browse recent posts and jump straight back into the Retrieve tab
- Configure the backend server URL from the app's Settings window

## Requirements

- macOS 14.0 or later
- Xcode 15+ for local development
- A running `knowledged` server reachable over HTTP, typically `http://localhost:9090`

For backend setup, see [`knowledged`](https://github.com/wiztools/knowledged).

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

For the repo-local Release build helper, use:

```sh
./bld.sh
```

The app bundle is written to `build/local/KnowledgedMac.app`.

## Developer ID release and notarization

The open-source scripts keep local Apple Developer details out of the repo. Copy
the example config and fill in values from your Apple Developer account:

```sh
cp scripts/release.env.example scripts/release.env
```

At minimum, set:

- `KNOWLEDGED_MAC_TEAM_ID`: your Apple Developer Team ID
- `KNOWLEDGED_MAC_NOTARY_PROFILE`: the `notarytool` keychain profile name
- `KNOWLEDGED_MAC_SIGNING_CERTIFICATE`: optional, if Xcode cannot infer the
  correct `Developer ID Application` certificate

Create the notary profile once on your machine:

```sh
xcrun notarytool store-credentials "knowledged-mac-notary" \
  --apple-id "you@example.com" \
  --team-id "ABCDE12345" \
  --password "app-specific-password"
```

Then build, sign, notarize, staple, and package:

```sh
scripts/release.sh
```

You can also run the steps separately:

```sh
scripts/build-release.sh
scripts/notarize-release.sh
```

Release outputs:

- Signed app: `build/release/export/KnowledgedMac.app`
- Notarized ZIP for distribution: `dist/KnowledgedMac-<timestamp>.zip`

The release scripts enable hardened runtime for the archive and use
`xcodebuild -archivePath`, `xcodebuild -exportArchive` with
`method=developer-id`, `xcrun notarytool submit --wait`, `xcrun stapler`,
`codesign --verify`, and `spctl --assess`.

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
Exact file-path results include an Edit action that opens the document in the Edit tab.
Tag chips in retrieved frontmatter open the Tags tab for that tag.

### Tags

Tags lists all backend tags with counts, then shows matching documents for the selected tag. Clicking a document opens it in Retrieve, and the pencil icon opens it in Edit. Tag chips inside Tags, Retrieve, and Recents jump directly to the selected tag.

### Edit

Edit loads a stored Markdown document by repo-relative path, lets you replace its body content or update frontmatter title, description, and tags, then waits for the backend edit job to finish.

### Delete

Delete removes a stored document by repo-relative path and waits for the backend job to finish.

### Recents

Recents lists recently posted items returned by the backend. Clicking an entry opens its path in the Retrieve tab. Clicking the copy icon copies the full path; double-clicking copies only the filename.
The pencil icon opens the entry in the Edit tab.
Tag chips open the Tags tab for that tag.

## Keyboard shortcuts

- `Cmd+N`: show the Post tab
- `Cmd+S`: show the Retrieve tab
- `Cmd+E`: show the Edit tab
- `Cmd+,`: open Settings
- `Cmd+Return`: run the primary action in the active form

`Cmd+Return` posts content in Post, runs a retrieval in Retrieve, saves in Edit, and confirms deletion in Delete.

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
