import 'package:file/file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart' as io;

class AppCacheManager extends CacheManager {
  /// Version 2 stores ordinary image files. The namespace change prevents
  /// metadata from the former on-disk format from being read as image bytes;
  /// those entries are left for normal temporary-file cleanup.
  static String get key =>
      '${LikeConstants.projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_')}_universalImageCache_v2';

  static AppCacheManager? _instance;

  @visibleForTesting
  static void reset() => _instance = null;

  factory AppCacheManager() {
    return _instance ??= AppCacheManager._internal();
  }

  AppCacheManager._internal()
      : super(
          Config(
            key,
            stalePeriod: Duration(days: LikeConstants.imageStalePeriod),
            maxNrOfCacheObjects: LikeConstants.maxImageCacheItems,
            // JsonCacheInfoRepository uses sqflite, which has no web support.
            // On web, images still load but are not persisted across sessions.
            repo: kIsWeb
                ? NonStoringObjectProvider()
                : JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(),
          ),
        );

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final stream = super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    );

    if (kIsWeb && LikeConstants.supportWeb) {
      return stream;
    }

    return stream.asyncMap((response) async {
      if (response is FileInfo) {
        await _updateAccessTime(response.file);
      }
      return response;
    });
  }

  Future<void> _updateAccessTime(File file) async {
    try {
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
      }
    } catch (e) {
      LikeLogger.log(
        level: LikeLogLevel.warning,
        category: 'cache_manager',
        message: 'Failed to update access time for ${file.path}: $e',
      );
    }
  }

  /// Checks the total size of the cache and performs LRU pruning if it exceeds
  /// [maxMB]. Prunes down to [minMB] by deleting least-recently-used files.
  Future<void> pruneCacheIfExceedsSize({double? maxMB, double? minMB}) async {
    if (kIsWeb && LikeConstants.supportWeb) return;
    final limitMax = maxMB ?? LikeConstants.maxImageCacheMB;
    final limitMin = minMB ?? LikeConstants.minImageCacheMB;

    try {
      final cacheDir = await getTemporaryDirectory();
      final directory = io.Directory('${cacheDir.path}/$key');

      if (await directory.exists()) {
        final entities = await directory.list().toList();
        final files = entities.whereType<io.File>().toList();

        int totalSizeBytes = 0;
        for (final file in files) {
          totalSizeBytes += await file.length();
        }

        final totalSizeMB = totalSizeBytes / (1024 * 1024);
        if (totalSizeMB > limitMax) {
          files.sort((a, b) {
            final aTime = a.lastModifiedSync();
            final bTime = b.lastModifiedSync();
            return aTime.compareTo(bTime);
          });

          final bytesToDelete =
              ((totalSizeMB - limitMin) * 1024 * 1024).toInt();
          var deletedBytes = 0;

          for (final file in files) {
            if (deletedBytes >= bytesToDelete) break;
            final length = await file.length();
            try {
              await file.delete();
              deletedBytes += length;
            } catch (e) {
              LikeLogger.log(
                level: LikeLogLevel.error,
                category: 'cache_manager',
                message:
                    'Failed to delete file during pruning ${file.path}: $e',
              );
            }
          }
        }
      }
    } catch (e) {
      LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'cache_manager',
        message: 'Error during cache pruning: $e',
      );
    }
  }

  /// Clears the cache manager metadata and all ordinary cached image files.
  Future<void> clearAll() async {
    try {
      await emptyCache();
    } catch (e) {
      LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'cache_manager',
        message: 'Failed to empty flutter_cache_manager cache: $e',
      );
    }
    if (kIsWeb && LikeConstants.supportWeb) return;

    // Remove remaining cache binaries while preserving cache-manager metadata.
    try {
      final cacheDir = await getTemporaryDirectory();
      final directory = io.Directory('${cacheDir.path}/$key');
      if (await directory.exists()) {
        final entities = await directory.list(recursive: true).toList();
        for (final entity in entities) {
          if (entity is io.File) {
            final path = entity.path.toLowerCase();
            if (!path.endsWith('.json') &&
                !path.endsWith('.db') &&
                !path.endsWith('.sqlite')) {
              try {
                await entity.delete();
              } catch (e) {
                LikeLogger.log(
                  level: LikeLogLevel.warning,
                  category: 'cache_manager',
                  message: 'Could not delete remaining file ${entity.path}: $e',
                );
              }
            }
          }
        }
      }
    } catch (e) {
      LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'cache_manager',
        message: 'Error during deep cleanup in clearAll: $e',
      );
    }
  }
}

class AppCacheUtils {
  /// Normalizes a URL for caching by removing dynamic parameters (like timestamps or cache-busters)
  /// while preserving access tokens, API keys, and auth signatures required for image access.
  static String normalizeUrl(String rawUrl, {List<String>? preserveParams}) {
    if (rawUrl.isEmpty) return '';
    try {
      var trimmed = rawUrl.trim();
      final schemeMatch = RegExp(r'^([a-zA-Z0-9+\-.]+):').firstMatch(trimmed);
      if (schemeMatch != null) {
        final scheme = schemeMatch.group(1)!;
        trimmed = '${scheme.toLowerCase()}${trimmed.substring(scheme.length)}';
      }

      final uri = Uri.parse(trimmed);
      final normalizedHost = uri.hasAuthority ? uri.host.toLowerCase() : null;

      // Common auth / access keys that should always be preserved
      final keysToKeep = <String>{
        'apikey',
        'api_key',
        'key',
        'token',
        'access_token',
        'auth',
        'sig',
        'signature',
        'sv',
        'se',
        'sr',
        'sp',
        if (preserveParams != null) ...preserveParams.map((e) => e.toLowerCase()),
      };

      final filteredQuery = uri.queryParameters.isEmpty
          ? null
          : (Map<String, String>.from(uri.queryParameters)
            ..removeWhere((key, _) => !keysToKeep.contains(key.toLowerCase())));

      final resultUri = uri.replace(
        host: normalizedHost,
        queryParameters: (filteredQuery != null && filteredQuery.isNotEmpty)
            ? filteredQuery
            : null,
        fragment: '',
      );

      var result = resultUri.toString();
      if (result.contains('#')) {
        result = result.split('#').first;
      }
      if ((filteredQuery == null || filteredQuery.isEmpty) && result.contains('?')) {
        result = result.split('?').first;
      }
      return result;
    } catch (_) {
      return rawUrl.trim();
    }
  }
}
