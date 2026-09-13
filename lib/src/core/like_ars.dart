/// Advanced Request Settings (ARS) for fine-grained network control.
/// Mirrors the core enterprise network capabilities.
typedef ARS = LikeARS;

class LikeARS {
  /// Enables Stale-While-Revalidate (Instant cached UI + Background network refresh).
  ///
  /// **How it works:** When enabled, the app instantly shows the user their last stored cached data (even if it's old),
  /// and silently fetches the fresh data from the internet in the background to update the screen.
  ///
  /// **Best used for:** Feeds, profile pages, or dashboards where fast loading is crucial.
  final bool staleWhileRevalidate;

  /// Signals that this request is a user-initiated hard refresh (like a pull-to-refresh swipe).
  ///
  /// **Why it's useful:** It tells the state managers and UI builders that they should either show a loading spinner
  /// or maintain "sticky data" (keeping the current data visible on screen) while the fresh network request finishes.
  final bool refresh;

  /// Fetches from the internet *exactly once* during the lifetime of the application.
  ///
  /// **How it works:** When set to `true`, the app checks your offline L2 disk database. If it finds a stored response,
  /// it returns it instantly and **completely skips the network call**.
  ///
  /// **Best used for:** Static app configurations, FAQs, country lists, or legal terms that almost never change.
  final bool singleFetch;

  /// Saves cache in fast RAM memory for the current session.
  ///
  /// **How it works:** The very first time you request the data, the app goes to the internet. For any subsequent
  /// requests made in the same session, it instantly serves the response from the in-memory L1 RAM Cache,
  /// avoiding both database reads and network calls.
  final bool sessionStale;

  /// Bypasses all caching layers entirely and forces a direct call to the internet.
  ///
  /// **Why it's useful:** When `true`, it ignores L1 RAM, L2 Disk, and SWR layers. The request is guaranteed
  /// to go straight to the real network every single time.
  ///
  /// **Best used for:** Pages requiring absolute real-time accuracy, such as checkouts or bank balances.
  final bool disableCache;

  /// Resets the single-fetch safeguard for this specific endpoint.
  ///
  /// **Why it's useful:** When `true`, it invalidates any previous `singleFetch` cache and forces a real network call
  /// to refresh that data once, updating the cached value.
  final bool resetSingleFetch;

  /// Clears the session RAM cache for this specific endpoint.
  ///
  /// **Why it's useful:** When `true`, it clears the stored L1 cache registry key for this resource,
  /// forcing a new network call to fetch fresh data.
  final bool resetSessionStale;

  /// Suppresses global UI error alerts or popup toasts if this request fails.
  ///
  /// **Why it's useful:** Prevents annoying error dialogs from popping up when a background task or non-critical pre-fetch
  /// fails, letting you handle the error silently in your controller code.
  final bool suppressErrors;

  /// Enforces the persistent "Offline Action Sync Queue" for modifying actions (like POST/PUT/DELETE).
  ///
  /// **How it works:** If a user performs an action (like posting a comment) while offline, this catches the failure,
  /// serializes the request, and saves it in the persistent offline queue box. As soon as the connectivity manager
  /// detects that the device is online again, it automatically sends the action to the server in the background.
  final bool offlineSync;

  /// Whether to verify the SSL/TLS security certificate of the remote server.
  ///
  /// **Tip:** Keep this `true` for production. You can set it to `false` in local debug/development environments
  /// if your local mock API server does not have a verified security certificate.
  final bool verifySSL;

  /// Checks whether the requested resource is available before proceeding.
  final bool checkAvailability;

  /// Automatically cancels previous identical network requests if a new one is made.
  ///
  /// **Example:** If two widgets on your screen request the user's profile at the exact same time,
  /// the app cancels the first request and only the second widget's request is executed (Take-Latest behavior).
  final bool deduplicate;

  /// Enables automatic UI refetching when the bound screen comes into focus.
  final bool visibility;

  const LikeARS({
    this.visibility = false,
    this.staleWhileRevalidate = false,
    this.refresh = false,
    this.singleFetch = false,
    this.sessionStale = false,
    this.disableCache = false,
    this.resetSingleFetch = false,
    this.resetSessionStale = false,
    this.offlineSync = false,
    this.verifySSL = true,
    this.checkAvailability = false,
    this.deduplicate = true,
    this.suppressErrors = true,
  });

  LikeARS copyWith({
    bool? staleWhileRevalidate,
    bool? refresh,
    bool? singleFetch,
    bool? sessionStale,
    bool? disableCache,
    bool? resetSingleFetch,
    bool? resetSessionStale,
    bool? offlineSync,
    bool? verifySSL,
    bool? checkAvailability,
    bool? deduplicate,
    bool? suppressErrors,
    bool? visibility,
  }) {
    return LikeARS(
      staleWhileRevalidate: staleWhileRevalidate ?? this.staleWhileRevalidate,
      refresh: refresh ?? this.refresh,
      singleFetch: singleFetch ?? this.singleFetch,
      sessionStale: sessionStale ?? this.sessionStale,
      disableCache: disableCache ?? this.disableCache,
      resetSingleFetch: resetSingleFetch ?? this.resetSingleFetch,
      resetSessionStale: resetSessionStale ?? this.resetSessionStale,
      offlineSync: offlineSync ?? this.offlineSync,
      verifySSL: verifySSL ?? this.verifySSL,
      checkAvailability: checkAvailability ?? this.checkAvailability,
      deduplicate: deduplicate ?? this.deduplicate,
      suppressErrors: suppressErrors ?? this.suppressErrors,
      visibility: visibility ?? this.visibility,
    );
  }

  Map<String, dynamic> toJson() => {
        'staleWhileRevalidate': staleWhileRevalidate,
        'refresh': refresh,
        'singleFetch': singleFetch,
        'sessionStale': sessionStale,
        'disableCache': disableCache,
        'resetSingleFetch': resetSingleFetch,
        'resetSessionStale': resetSessionStale,
        'offlineSync': offlineSync,
        'verifySSL': verifySSL,
        'checkAvailability': checkAvailability,
        'deduplicate': deduplicate,
        'suppressErrors': suppressErrors,
        'visibility': visibility,
      };

  factory LikeARS.fromJson(Map<String, dynamic> json) => LikeARS(
        staleWhileRevalidate: json['staleWhileRevalidate'] ?? false,
        refresh: json['refresh'] ?? false,
        singleFetch: json['singleFetch'] ?? false,
        sessionStale: json['sessionStale'] ?? false,
        disableCache: json['disableCache'] ?? false,
        resetSingleFetch: json['resetSingleFetch'] ?? false,
        resetSessionStale: json['resetSessionStale'] ?? false,
        offlineSync: json['offlineSync'] ?? false,
        verifySSL: json['verifySSL'] ?? true,
        checkAvailability: json['checkAvailability'] ?? false,
        deduplicate: json['deduplicate'] ?? true,
        suppressErrors: json['suppressErrors'] ?? true,
        visibility: json['visibility'] ?? false,
      );
}
