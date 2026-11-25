# ioant-Clip architecture

Hero Skills baseline: 62f7b2ac062e62de41f8fe8565583d761aeabb0f. Product is a high-fidelity content collection library, not a note editor. UI terminology: clip / collection. Preserve legacy repository, package, bundle IDs, capture envelope, persisted field names and paths until an explicit migration is approved.

| Module | Responsibility and contract |
|---|---|
| App/Bootstrap | SwiftUI app composition, library lifetime, scene wiring |
| App/Features/Library | LibraryStore owns atomic local mutations; LibraryView owns navigation/selection; LibrarySidebar controls via bindings |
| App/Features/Reader | ClipDetailView composes native reader and actions |
| App/Features/Tags | Tag chips and editing sheet |
| App/Features/Sync | Settings and provider adapters; cloud disabled until consent and configuration |
| App/Platform | AppKit/UIKit clipboard and WebKit platform views |
| App/DesignSystem | UI presentation mappings |
| App/Localization | Resource ownership |
| Sources/NoteCore/Notes | Note, NotePart and NoteLibrary; stable persisted schema and mutation owner |
| Sources/NoteCore/Rendering | Pure HTML generation, source colors and offline CSP |
| Sources/NoteCore/Persistence | Atomic file load/save |
| Sources/NoteCore/Capture | Envelope decoding and durable inbox |
| Sources/NoteCore/Tags | Colors, filters, deterministic suggestions (no AI) |
| Sources/NoteCore/Sync | Revision graph, exchange and pure projection |
| BrowserExtension | Separate popup, injected capture and viewport scripts; further layout/asset split must preserve isolated-world execution |

UI -> store/use case -> core, native adapters at app boundary. Core must not import SwiftUI, AppKit/UIKit, CloudKit or WebKit. Stable data owners, no duplicate stores. Native NavigationSplitView, List, Menu, Sheet, Toolbar and gestures remain unchanged. Do not change user content, cloud settings, bundle identity or source styles during structural work. Native host ID com.ioant.note.capture stays unchanged. App binary target names remain legacy for build scripts.

## Next steps
R2 semantic localization and persistent language choice; R3 semantic theme with system/light/dark and accent choice; R4 native platform layout polish. Build and regression test both native platforms and browser capture each stage. Deeper capture-engine decomposition requires explicit isolated-world execution contract and real Chrome regression.
