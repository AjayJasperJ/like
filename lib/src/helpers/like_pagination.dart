/// Generic state, parsing, and calculations for page-based and cursor-based pagination.
///
/// Can be used as a standalone pagination container or extended by custom API
/// response models (e.g. `class PaginatedPosts extends PaginationTool<ApiPost>`).
class PaginationTool<T> {
  final int? page;
  final int? contentLimit;
  final int? totalPages;
  final int? totalContent;
  final int? currentPage;
  final int? currentContent;
  final bool? hasNextOverride;
  final bool? hasPreviousOverride;
  final String? cursor;
  final String? nextCursor;
  final List<T>? listData;

  const PaginationTool({
    this.page,
    this.contentLimit,
    this.totalPages,
    this.totalContent,
    this.currentPage,
    this.currentContent,
    this.hasNextOverride,
    this.hasPreviousOverride,
    this.cursor,
    this.nextCursor,
    this.listData,
  });

  /// Alias for [contentLimit].
  int? get limit => contentLimit;

  /// Alias for [totalContent].
  int? get total => totalContent;

  /// Returns the items/records list.
  List<T>? get items => listData;

  /// Whether there is a next page available.
  bool get hasNext => hasNextOverride ?? hasMore;

  /// Whether there is a previous page available.
  bool get hasPrevious =>
      hasPreviousOverride ??
      (resolvedPage > 1 || (cursor != null && cursor!.isNotEmpty));

  /// Uses total item count when the API provides it.
  bool get hasMoreByTotal =>
      totalContent != null && loadedContent < totalContent!;

  /// Uses current and total pages when the API provides page metadata.
  bool get hasMoreByPages => totalPages != null && resolvedPage < totalPages!;

  /// Uses the accumulated list when the API only returns paginated items.
  bool get hasMoreByList =>
      contentLimit != null &&
      listData != null &&
      listData!.length >= resolvedPage * contentLimit!;

  /// Uses cursor metadata when provided by the API.
  bool get hasMoreByCursor => nextCursor != null && nextCursor!.isNotEmpty;

  /// Selects a strategy based only on metadata supplied by the API.
  bool get hasMore {
    if (hasNextOverride != null) return hasNextOverride!;
    if (nextCursor != null) return hasMoreByCursor;
    if (totalContent != null) return hasMoreByTotal;
    if (totalPages != null) return hasMoreByPages;
    if (listData != null && contentLimit != null) return hasMoreByList;
    return false;
  }

  bool get isComplete => !hasMore;
  int get resolvedPage => currentPage ?? page ?? 0;
  int get loadedContent => currentContent ?? listData?.length ?? 0;
  int get nextPage => hasMore ? resolvedPage + 1 : resolvedPage;

  int get remainingPages => totalPages == null
      ? 0
      : (totalPages! - resolvedPage).clamp(0, totalPages!);

  int get remainingContent => totalContent == null
      ? 0
      : (totalContent! - loadedContent).clamp(0, totalContent!);

  double get progress => totalContent == null || totalContent == 0
      ? 0
      : (loadedContent / totalContent!).clamp(0, 1);

  /// Converts pagination state into a standard Map payload.
  Map<String, dynamic> toMap() => {
        if (page != null) 'page': page,
        if (contentLimit != null) 'limit': contentLimit,
        if (totalPages != null) 'totalPages': totalPages,
        if (totalContent != null) 'total': totalContent,
        'hasNext': hasNext,
        'hasPrevious': hasPrevious,
        if (cursor != null) 'cursor': cursor,
        if (nextCursor != null) 'nextCursor': nextCursor,
        if (listData != null) 'items': listData,
      };

  /// Alias for [toMap].
  Map<String, dynamic> toJson() => toMap();

  /// Returns pagination updated with a fetched page.
  PaginationTool<T> updatePage({
    required int page,
    required int limit,
    required List<T> pageData,
    required bool append,
    int? totalPages,
    int? totalContent,
    String? cursor,
    String? nextCursor,
    bool? hasNext,
    bool? hasPrevious,
  }) {
    final data = append ? [...?listData, ...pageData] : pageData;
    return PaginationTool<T>(
      page: page,
      currentPage: page,
      currentContent: data.length,
      contentLimit: limit,
      totalPages: totalPages ?? this.totalPages,
      totalContent: totalContent ?? this.totalContent,
      hasNextOverride: hasNext ?? hasNextOverride,
      hasPreviousOverride: hasPrevious ?? hasPreviousOverride,
      cursor: cursor ?? this.cursor,
      nextCursor: nextCursor ?? this.nextCursor,
      listData: data,
    );
  }

  /// Overwrites/replaces the slice of items belonging to a specific [pageNumber]
  /// with fresh [pageData], preserving data from other loaded pages.
  PaginationTool<T> overwritePage({
    required int pageNumber,
    required int limit,
    required List<T> pageData,
    int? totalPages,
    int? totalContent,
    String? cursor,
    String? nextCursor,
    bool? hasNext,
    bool? hasPrevious,
  }) {
    final existing = listData ?? <T>[];
    final startIndex = (pageNumber - 1) * limit;

    if (startIndex >= existing.length) {
      final updated = [...existing, ...pageData];
      return copyWith(
        page: pageNumber,
        currentPage: pageNumber,
        currentContent: updated.length,
        contentLimit: limit,
        totalPages: totalPages,
        totalContent: totalContent,
        cursor: cursor,
        nextCursor: nextCursor,
        hasNextOverride: hasNext,
        hasPreviousOverride: hasPrevious,
        listData: updated,
      );
    }

    final updated = List<T>.from(existing);
    final endIndex = (startIndex + limit).clamp(0, updated.length);
    updated.replaceRange(
      startIndex,
      endIndex,
      pageData,
    );

    return copyWith(
      page: pageNumber,
      currentPage: pageNumber,
      currentContent: updated.length,
      contentLimit: limit,
      totalPages: totalPages,
      totalContent: totalContent,
      cursor: cursor,
      nextCursor: nextCursor,
      hasNextOverride: hasNext,
      hasPreviousOverride: hasPrevious,
      listData: updated,
    );
  }

  PaginationTool<T> reset() => PaginationTool<T>();

  PaginationTool<T> copyWith({
    int? page,
    int? contentLimit,
    int? totalPages,
    int? totalContent,
    int? currentPage,
    int? currentContent,
    bool? hasNextOverride,
    bool? hasPreviousOverride,
    String? cursor,
    String? nextCursor,
    List<T>? listData,
  }) =>
      PaginationTool<T>(
        page: page ?? this.page,
        contentLimit: contentLimit ?? this.contentLimit,
        totalPages: totalPages ?? this.totalPages,
        totalContent: totalContent ?? this.totalContent,
        currentPage: currentPage ?? this.currentPage,
        currentContent: currentContent ?? this.currentContent,
        hasNextOverride: hasNextOverride ?? this.hasNextOverride,
        hasPreviousOverride: hasPreviousOverride ?? this.hasPreviousOverride,
        cursor: cursor ?? this.cursor,
        nextCursor: nextCursor ?? this.nextCursor,
        listData: listData ?? this.listData,
      );

  factory PaginationTool.initial() => PaginationTool<T>();
}

/// Backward compatibility alias for [PaginationTool].
typedef Pagination<T> = PaginationTool<T>;
