import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/app_cache_manager.dart';

/// # LikeCacheImage
///
/// A universal, premium network image widget designed to load, render, and automatically
/// cache images.
///
/// It integrates seamlessly with the custom encrypted L2 disk cache (`AppCacheManager`)
/// and honors LIKE's web/native dual-runtime safety constraints automatically.
///
/// ### How Caching Works:
/// * **Native Platforms (iOS/Android):** Powered by `CachedNetworkImage` with our custom
///   `AppCacheManager`. Images are downloaded, parsed, encrypted on-the-fly, and saved to disk.
///   Subsequent requests retrieve the image instantly from the local database instead of hitting
///   the internet again.
/// * **Web Platform (Chrome/Safari/etc.):** Since native file paths and directory accesses aren't
///   supported in browser security sandboxes, it gracefully falls back to standard `Image.network`
///   without throwing exceptions, utilizing native browser caching headers.
///
/// ### Example Usage:
/// ```dart
/// LikeCacheImage(
///   imageUrl: 'https://example.com/avatar.jpg',
///   width: 100,
///   height: 100,
///   fit: BoxFit.cover,
///   placeholder: (context, url) => CircularProgressIndicator(),
///   errorWidget: (context, url, error) => Icon(Icons.broken_image),
/// );
/// ```
class LikeCacheImage extends StatelessWidget {
  /// The absolute network HTTP/HTTPS URL of the image to display.
  final String imageUrl;

  /// How the image should scale to fit its visual bounds (e.g. [BoxFit.cover] vs [BoxFit.contain]).
  final BoxFit fit;

  /// The strict layout width constraint of the image widget.
  final double? width;

  /// The strict layout height constraint of the image widget.
  final double? height;

  /// Optional builder that renders a temporary widget while the image is downloading.
  final Widget Function(BuildContext, String)? placeholder;

  /// Optional builder that renders a custom error UI if the download or parsing fails.
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  /// Optional builder that allows wrapping the resolved [ImageProvider] inside a styled custom container
  /// (e.g. adding rounded borders, shadows, or background filters).
  final Widget Function(BuildContext, ImageProvider)? imageBuilder;

  /// Limits the horizontal resolution decoded in memory (helps reduce RAM usage for massive images).
  final int? memCacheWidth;

  /// Limits the vertical resolution decoded in memory.
  final int? memCacheHeight;

  /// The duration of the smooth fade-in animation when the image resolves.
  final Duration fadeInDuration;

  /// The duration of the smooth fade-out animation.
  final Duration fadeOutDuration;

  /// If true, normalizes query string parameters or paths to prevent duplicate entries
  /// for identical images with varying URL query parameters.
  final bool normalizeUrl;

  /// An optional tint color applied to the image pixels.
  final Color? color;

  const LikeCacheImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
    this.memCacheWidth,
    this.memCacheHeight,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.fadeOutDuration = const Duration(milliseconds: 1000),
    this.normalizeUrl = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Guard against empty URLs to prevent network request crashes
    if (imageUrl.trim().isEmpty) {
      return errorWidget?.call(context, imageUrl, 'Empty URL') ??
          const Center(child: Icon(Icons.error_outline));
    }

    // 2. Handle Web Platform Safety (Dual-runtime fallback)
    if (kIsWeb && LikeConstants.supportWeb) {
      return Image.network(
        imageUrl,
        fit: fit,
        width: width,
        height: height,
        color: color,
        errorBuilder: errorWidget != null
            ? (context, error, stackTrace) =>
                errorWidget!(context, imageUrl, error)
            : null,
        loadingBuilder: placeholder != null
            ? (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return placeholder!(context, imageUrl);
              }
            : null,
      );
    }

    // 3. Native Platform persistent cache with key normalization
    final cacheKey = normalizeUrl ? AppCacheUtils.normalizeUrl(imageUrl) : null;

    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheKey: cacheKey,
      cacheManager: AppCacheManager(),
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      imageBuilder: imageBuilder,
      placeholder: placeholder,
      errorWidget: errorWidget,
      color: color,
    );
  }
}
