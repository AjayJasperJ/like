# Changelog

All notable changes to this project will be documented in this file.

## [1.0.2] - 2026-05-10

### Fixed
- **Pub.dev Asset Loading**: Switched to raw GitHub URLs for the banner to ensure correct rendering on pub.dev.
- **Package Size Optimization**: Added `.pubignore` to exclude the `build/` folder and other artifacts, significantly reducing the package size (from 16MB down to <1MB).

## [1.0.1] - 2026-05-10


### Added
- **Visual Identity**: Added a high-fidelity package banner to the README for a more professional presentation on pub.dev.

### Fixed
- **Code Hardening**: Fixed multiple `use_build_context_synchronously` lint issues in `LikeWhen` to ensure UI stability during async gaps.
- **Style Consistency**: Corrected string quoting and applied `dart format` across the entire package (63 files) for 100% lint compliance.

## [1.0.0] - 2026-05-10


### Initial Release

- **Link Intelligent Kernel Engine (LIKE)**: A high-performance, 4-tier caching networking package for Flutter.
- **3-Tier Caching Architecture**:
  - L1: RAM Cache for instantaneous session-level retrieval.
  - L2: Persistent Disk Cache (Hive) for cross-session persistence.
  - L3: Stale-While-Revalidate (SWR) logic for background data freshness.
- **Resilience Engine**: 
  - Automated request deduplication.
  - Request suppression and cancellation logic.
  - Built-in smart retry mechanism.
- **Offline-First Synchronization**:
  - Background mutation queueing (POST/PUT/DELETE).
  - Automatic synchronization when connectivity is restored.
- **Notification Engine**:
  - Contextless high-fidelity toast notification system.
  - Custom animations (Slide, Fade, Scale, Bounce).
  - Swipe-to-dismiss and interactive action support.
- **Performance Optimizations**:
  - Automatic offloading of heavy JSON parsing to background isolates.
  - Efficient binary serialization for L2 disk storage.
- **Reactive UI Components**:
  - `LikeBuilder`: Declarative state handling for Loading, Success, SWR, and Error.
  - `LikeWhen`: Streamlined pattern matching for network results.
  - `updateNotifier`: Integrated side-effect handler with haptics and toast support.
- **Security & Configuration**:
  - Support for SSL Pinning (SHA256).
  - Sensitive header masking in logs.
  - Comprehensive `LikeConfig` with over 80+ customization options.
