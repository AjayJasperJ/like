import 'dart:io' as io;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:like/src/core/like_constants.dart';

class AppCacheManager extends CacheManager {
  static const key = 'universalImageCache';
  static final AppCacheManager _instance = AppCacheManager._internal();

  factory AppCacheManager() => _instance;

  AppCacheManager._internal()
      : super(
          Config(
            key,
            stalePeriod: Duration(
              days: LikeConstants.imageStalePeriod,
            ),
            maxNrOfCacheObjects: LikeConstants.maxImageCacheItems,
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: EncryptedHttpFileService(),
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

    return stream.asyncMap((response) async {
      if (response is FileInfo) {
        // Skip if already in decrypted directory
        if (response.file.path.contains(
          '${io.Platform.pathSeparator}decrypted${io.Platform.pathSeparator}',
        )) {
          return response;
        }

        // Reset stale period by updating last modified time
        _updateAccessTime(response.file);

        // Decrypt the file for use
        try {
          final decryptedIoFile = await AppCacheSecurity.decryptFile(
            response.file,
          );
          final decryptedFile = const LocalFileSystem().file(
            decryptedIoFile.path,
          );
          return FileInfo(
            decryptedFile,
            response.source,
            response.validTill,
            response.originalUrl,
            // Keep existing logic
          );
        } catch (e) {
          // If decryption fails, the file is likely unencrypted (legacy) or corrupted.
          // We delete it so it can be re-downloaded correctly.
          try {
            if (await response.file.exists()) {
              await response.file.delete();
            }
          } catch (_) {}
          throw Exception('Decryption failed, corrupted file removed');
        }
      }
      return response;
    });
  }

  Future<void> _updateAccessTime(File file) async {
    try {
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
      }
    } catch (_) {}
  }

  /// Checks the total size of the cache and performs LRU pruning if it exceeds [maxMB].
  /// Prunes down to [minMB] by deleting the least recently used files.
  Future<void> pruneCacheIfExceedsSize({double? maxMB, double? minMB}) async {
    final limitMax = maxMB ?? LikeConstants.maxImageCacheMB;
    final limitMin = minMB ?? LikeConstants.minImageCacheMB;

    try {
      final cacheDir = await getTemporaryDirectory();
      final directory = io.Directory('${cacheDir.path}/$key');

      if (await directory.exists()) {
        final List<io.FileSystemEntity> entities = await directory
            .list()
            .toList();
        final List<io.File> files = entities
            .whereType<io.File>()
            .where((f) => !f.path.contains('/decrypted/'))
            .toList();

        int totalSizeBytes = 0;
        for (var file in files) {
          totalSizeBytes += await file.length();
        }

        final double totalSizeMB = totalSizeBytes / (1024 * 1024);

        if (totalSizeMB > limitMax) {
          // Sort by last modified (oldest first)
          files.sort((a, b) {
            final aTime = a.lastModifiedSync();
            final bTime = b.lastModifiedSync();
            return aTime.compareTo(bTime);
          });

          int bytesToDelete = ((totalSizeMB - limitMin) * 1024 * 1024).toInt();
          int deletedBytes = 0;

          for (var file in files) {
            if (deletedBytes >= bytesToDelete) break;
            final length = await file.length();
            try {
              await file.delete();
              deletedBytes += length;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Clears the temporary decrypted files
  Future<void> clearDecryptedCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final decryptedDir = io.Directory('${cacheDir.path}/$key/decrypted');
      if (await decryptedDir.exists()) {
        await decryptedDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Explicitly clears both the flutter_cache_manager encrypted cache and the decrypted files.
  Future<void> clearAll() async {
    try {
      await emptyCache();
    } catch (_) {}
    try {
      await clearDecryptedCache();
    } catch (_) {}

    // Manually clean up any remaining files in the cache directory to guarantee the disk is completely cleared.
    try {
      final cacheDir = await getTemporaryDirectory();
      final directory = io.Directory('${cacheDir.path}/$key');
      if (await directory.exists()) {
        final List<io.FileSystemEntity> entities = await directory.list(recursive: true).toList();
        for (var entity in entities) {
          if (entity is io.File) {
            final path = entity.path.toLowerCase();
            // Do not delete the database/metadata files of flutter_cache_manager itself
            if (!path.endsWith('.json') && !path.endsWith('.db') && !path.endsWith('.sqlite')) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }
}

class AppCacheSecurity {
  static final _key = encrypt.Key.fromUtf8(
    'LikeSecureEncryptionCacheKey1234',
  ); // 32 chars
  // USE A FIXED IV FOR PERSISTENT DECRYPTION ACROSS SESSIONS
  static final _iv = encrypt.IV.fromUtf8('LikeSecureIV1234'); // 16 chars
  static final _encrypter = encrypt.Encrypter(
    encrypt.AES(_key, mode: encrypt.AESMode.cbc),
  );

  static Future<io.File> decryptFile(File encryptedFile) async {
    final bytes = await encryptedFile.readAsBytes();
    if (bytes.isEmpty) throw Exception('File is empty');

    final decryptedBytes = _encrypter.decryptBytes(
      encrypt.Encrypted(bytes),
      iv: _iv,
    );

    // Safeguard path logic
    final String separator = io.Platform.pathSeparator;
    final String keyMatch = '$separator${AppCacheManager.key}$separator';
    final String decryptedMatch = '${keyMatch}decrypted$separator';

    String decryptedPath;
    if (encryptedFile.path.contains(keyMatch)) {
      decryptedPath = encryptedFile.path.replaceFirst(keyMatch, decryptedMatch);
    } else {
      // Fallback if path structure is unexpected
      decryptedPath =
          '${encryptedFile.parent.path}${separator}decrypted$separator${encryptedFile.basename}';
    }

    if (decryptedPath == encryptedFile.path) {
      throw Exception(
        'Decryption path collision detected. Avoiding overwrite.',
      );
    }

    final decryptedFile = io.File(decryptedPath);
    if (!await decryptedFile.parent.exists()) {
      await decryptedFile.parent.create(recursive: true);
    }

    return await decryptedFile.writeAsBytes(decryptedBytes);
  }

  static Uint8List encryptBytes(Uint8List bytes) {
    if (bytes.isEmpty) return Uint8List(0);
    return Uint8List.fromList(_encrypter.encryptBytes(bytes, iv: _iv).bytes);
  }
}

class EncryptedHttpFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await super.get(url, headers: headers);
    return EncryptedFileServiceResponse(response);
  }
}

class EncryptedFileServiceResponse implements FileServiceResponse {
  final FileServiceResponse _inner;
  EncryptedFileServiceResponse(this._inner);

  @override
  Stream<List<int>> get content async* {
    final List<int> allBytes = [];
    await for (final chunk in _inner.content) {
      allBytes.addAll(chunk);
    }
    yield AppCacheSecurity.encryptBytes(Uint8List.fromList(allBytes));
  }

  @override
  int get statusCode => _inner.statusCode;

  @override
  String get eTag => _inner.eTag ?? '';

  @override
  int? get contentLength => null; // Set to null because encryption changes size

  @override
  DateTime get validTill => _inner.validTill;

  @override
  String get fileExtension => _inner.fileExtension;
}

class AppCacheUtils {
  /// Normalizes a URL for caching purposes by removing query parameters
  /// (like tokens or tracking IDs) that would otherwise cause cache misses
  /// for the same image resource.
  static String normalizeUrl(String rawUrl) {
    if (rawUrl.isEmpty) return '';
    try {
      final uri = Uri.parse(rawUrl.trim());
      return uri
          .replace(
            scheme: uri.scheme.toLowerCase(),
            host: uri.host.toLowerCase(),
            query: '', // Remove tokens / tracking params
            fragment: '',
          )
          .toString();
    } catch (_) {
      return rawUrl.trim();
    }
  }
}
