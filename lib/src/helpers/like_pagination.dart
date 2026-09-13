/// Generic state and calculations for page-based pagination.
class Pagination<T> {
  final int? page;
  final int? contentLimit;
  final int? totalPages;
  final int? totalContent;
  final int? currentPage;
  final int? currentContent;
  final List<T>? listData;

  const Pagination({
    this.page,
    this.contentLimit,
    this.totalPages,
    this.totalContent,
    this.currentPage,
    this.currentContent,
    this.listData,
  });

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

  /// Selects a strategy based only on metadata supplied by the API.
  bool get hasMore {
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

  /// Returns pagination updated with a fetched page.
  ///
  /// Page one can replace existing data by passing [append] as `false`, while
  /// subsequent pages can be accumulated by passing it as `true`.
  Pagination<T> updatePage({
    required int page,
    required int limit,
    required List<T> pageData,
    required bool append,
    int? totalPages,
    int? totalContent,
  }) {
    final data = append ? [...?listData, ...pageData] : pageData;
    return Pagination<T>(
      page: page,
      currentPage: page,
      currentContent: data.length,
      contentLimit: limit,
      totalPages: totalPages ?? this.totalPages,
      totalContent: totalContent ?? this.totalContent,
      listData: data,
    );
  }

  Pagination<T> reset() => Pagination<T>();

  Pagination<T> copyWith({
    int? page,
    int? contentLimit,
    int? totalPages,
    int? totalContent,
    int? currentPage,
    int? currentContent,
    List<T>? listData,
  }) =>
      Pagination<T>(
        page: page ?? this.page,
        contentLimit: contentLimit ?? this.contentLimit,
        totalPages: totalPages ?? this.totalPages,
        totalContent: totalContent ?? this.totalContent,
        currentPage: currentPage ?? this.currentPage,
        currentContent: currentContent ?? this.currentContent,
        listData: listData ?? this.listData,
      );

  factory Pagination.initial() => Pagination<T>();
}
