import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_logger.dart';

class AppCacheManager extends CacheManager {
  static const key = 'universalImageCache';
  static final AppCacheManager _instance = AppCacheManager._internal();

  factory AppCacheManager() => _instance;

  AppCacheManager._internal()
      : super(
          Config(
            key,
            stalePeriod: Duration(days: LikeConstants.imageStalePeriod),
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
          } catch (deleteError) {
            LikeLogger.log(
              level: LikeLogLevel.error,
              category: 'cache_manager',
              message: 'Failed to delete corrupted file: $deleteError',
            );
          }
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
    } catch (e) {
      LikeLogger.log(
        level: LikeLogLevel.warning,
        category: 'cache_manager',
        message: 'Failed to update access time for ${file.path}: $e',
      );
    }
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
        final List<io.FileSystemEntity> entities =
            await directory.list().toList();
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

  /// Clears the temporary decrypted files
  Future<void> clearDecryptedCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final decryptedDir = io.Directory('${cacheDir.path}/$key/decrypted');
      if (await decryptedDir.exists()) {
        await decryptedDir.delete(recursive: true);
      }
    } catch (e) {
      LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'cache_manager',
        message: 'Failed to clear decrypted cache: $e',
      );
    }
  }

  /// Explicitly clears both the flutter_cache_manager encrypted cache and the decrypted files.
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
    try {
      await clearDecryptedCache();
    } catch (e) {
      LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'cache_manager',
        message: 'Failed to clear decrypted cache in clearAll: $e',
      );
    }

    // Manually clean up any remaining files in the cache directory to guarantee the disk is completely cleared.
    try {
      final cacheDir = await getTemporaryDirectory();
      final directory = io.Directory('${cacheDir.path}/$key');
      if (await directory.exists()) {
        final List<io.FileSystemEntity> entities =
            await directory.list(recursive: true).toList();
        for (var entity in entities) {
          if (entity is io.File) {
            final path = entity.path.toLowerCase();
            // Do not delete the database/metadata files of flutter_cache_manager itself
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

/// Handles AES-CBC encryption/decryption for the image cache.
///
/// **Design**:
/// - Key: Derived from the user-provided `LikeConfig.encryptionKey` via SHA-256,
///   or auto-generated as a cryptographically random 32-byte key persisted in
///   SharedPreferences (unique per device/install).
/// - IV: A fresh random 16-byte IV is generated for every file encryption and
///   prepended to the ciphertext (layout: [16-byte IV][ciphertext]).
///   This means each file is independently and correctly decryptable with no
///   shared state or IV reuse weaknesses.
///
/// **Initialization**: Call [AppCacheSecurity.init] inside [LikeService.init]
/// before any file downloads occur.
class AppCacheSecurity {
  static encrypt.Encrypter? _encrypter;
  static bool _initialized = false;
  static const int _ivLength = 16;
  static const String _deviceKeyPrefKey = 'like_cache_encryption_key_v2';

  /// Initializes the encryption engine.
  ///
  /// Uses [LikeConfig.encryptionKey] if set; otherwise generates and persists
  /// a per-device key in SharedPreferences.
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> init() async {
    if (_initialized) return;

    final configKey = LikeConstants.current.encryptionKey;
    final Uint8List keyBytes;

    if (configKey != null && configKey.isNotEmpty) {
      // Derive a stable 32-byte key from the user-provided string via SHA-256.
      // This ensures any length of input becomes a valid AES-256 key.
      keyBytes = Uint8List.fromList(
        sha256.convert(utf8.encode(configKey)).bytes,
      );
    } else {
      keyBytes = await _getOrCreateDeviceKey();
    }

    _encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc),
    );
    _initialized = true;
  }

  static Future<Uint8List> _getOrCreateDeviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_deviceKeyPrefKey);

    if (stored != null && stored.isNotEmpty) {
      return base64Decode(stored);
    }

    // Generate a cryptographically random 32-byte key.
    final rng = Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    await prefs.setString(_deviceKeyPrefKey, base64Encode(keyBytes));
    return keyBytes;
  }

  static void _assertInitialized() {
    if (!_initialized || _encrypter == null) {
      throw StateError(
        'AppCacheSecurity is not initialized. '
        'Ensure LikeService.init() is called before using the image cache.',
      );
    }
  }

  /// Encrypts [bytes] with a freshly generated random IV.
  ///
  /// Returns [16-byte IV][AES-CBC ciphertext] concatenated.
  static Uint8List encryptBytes(Uint8List bytes) {
    if (bytes.isEmpty) return Uint8List(0);
    _assertInitialized();

    final rng = Random.secure();
    final ivBytes = Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => rng.nextInt(256)),
    );
    final iv = encrypt.IV(ivBytes);
    final ciphertext = _encrypter!.encryptBytes(bytes, iv: iv);

    // Layout: [_ivLength bytes of IV][ciphertext bytes]
    final result = Uint8List(_ivLength + ciphertext.bytes.length);
    result.setRange(0, _ivLength, ivBytes);
    result.setRange(_ivLength, result.length, ciphertext.bytes);
    return result;
  }

  /// Decrypts encrypted bytes in-memory and returns the raw decrypted bytes.
  static Uint8List decryptBytes(Uint8List encryptedBytes) {
    if (encryptedBytes.isEmpty) return Uint8List(0);
    _assertInitialized();

    if (encryptedBytes.length <= _ivLength) {
      throw Exception(
        'Bytes too small to contain IV + ciphertext. Likely from an old format.',
      );
    }

    final ivBytes = Uint8List.fromList(encryptedBytes.sublist(0, _ivLength));
    final cipherBytes = Uint8List.fromList(encryptedBytes.sublist(_ivLength));
    final iv = encrypt.IV(ivBytes);

    final decryptedBytes = _encrypter!.decryptBytes(
      encrypt.Encrypted(cipherBytes),
      iv: iv,
    );
    return Uint8List.fromList(decryptedBytes);
  }

  /// Decrypts a file whose content was produced by [encryptBytes].
  ///
  /// Reads the IV from the first 16 bytes, then decrypts the remainder.
  /// If decryption fails (e.g., file was encrypted with the old hardcoded key),
  /// the caller ([AppCacheManager.getFileStream]) will delete and re-download it.
  static Future<io.File> decryptFile(File encryptedFile) async {
    _assertInitialized();

    final bytes = await encryptedFile.readAsBytes();
    if (bytes.isEmpty) throw Exception('File is empty');
    if (bytes.length <= _ivLength) {
      throw Exception(
        'File too small to contain IV + ciphertext. Likely from a previous format.',
      );
    }

    // Extract the per-file IV from the first 16 bytes.
    final iv = encrypt.IV(Uint8List.fromList(bytes.sublist(0, _ivLength)));
    final cipherBytes = Uint8List.fromList(bytes.sublist(_ivLength));

    final decryptedBytes = _encrypter!.decryptBytes(
      encrypt.Encrypted(cipherBytes),
      iv: iv,
    );

    // Safeguard path logic (unchanged from original)
    final String separator = io.Platform.pathSeparator;
    final String keyMatch = '$separator${AppCacheManager.key}$separator';
    final String decryptedMatch = '${keyMatch}decrypted$separator';

    String decryptedPath;
    if (encryptedFile.path.contains(keyMatch)) {
      decryptedPath = encryptedFile.path.replaceFirst(keyMatch, decryptedMatch);
    } else {
      decryptedPath =
          '${encryptedFile.parent.path}${separator}decrypted$separator${encryptedFile.basename}';
    }

    if (decryptedPath == encryptedFile.path) {
      throw Exception(
          'Decryption path collision detected. Avoiding overwrite.');
    }

    final decryptedFile = io.File(decryptedPath);
    if (!await decryptedFile.parent.exists()) {
      await decryptedFile.parent.create(recursive: true);
    }
    return decryptedFile.writeAsBytes(decryptedBytes);
  }

  /// Resets the encryption state. For testing only.
  @visibleForTesting
  static void reset() {
    _encrypter = null;
    _initialized = false;
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
