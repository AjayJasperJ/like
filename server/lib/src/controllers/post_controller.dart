import 'dart:io';

import 'package:shelf/shelf.dart';

import '../core/api_exception.dart';
import '../http/http_utils.dart';
import '../repositories/post_repository.dart';

final class PostController {
  const PostController(this._posts);

  final PostRepository _posts;

  Response list(Request request) {
    final query = request.url.queryParameters;
    final page = positiveInt(query['page'], fallback: 1, name: 'page');
    final limit = positiveInt(
      query['limit'],
      fallback: 10,
      name: 'limit',
      maximum: 100,
    );
    final search = query['search']?.trim().toLowerCase();
    final published = optionalBool(query['published'], 'published');
    final userId = query['userId'] == null
        ? null
        : positiveInt(query['userId'], name: 'userId');

    final filtered = _posts.all.where((post) {
      final matchesSearch = search == null ||
          search.isEmpty ||
          (post['title'] as String).toLowerCase().contains(search) ||
          (post['body'] as String).toLowerCase().contains(search);
      final matchesPublished =
          published == null || post['published'] == published;
      final matchesUser = userId == null || post['userId'] == userId;
      return matchesSearch && matchesPublished && matchesUser;
    }).toList();

    final sort = query['sort'] ?? 'id';
    const sortableFields = {'id', 'title', 'createdAt', 'userId'};
    if (!sortableFields.contains(sort)) {
      throw ApiException(400, 'Unsupported sort field: $sort');
    }
    final descending = (query['order'] ?? 'asc').toLowerCase() == 'desc';
    filtered.sort((left, right) {
      final result = (left[sort] as Comparable<Object?>).compareTo(right[sort]);
      return descending ? -result : result;
    });

    final total = filtered.length;
    final totalPages = total == 0 ? 0 : (total / limit).ceil();
    final start = (page - 1) * limit;
    final data = start >= total
        ? <Map<String, Object?>>[]
        : filtered.sublist(start, (start + limit).clamp(0, total));

    return jsonResponse({
      'data': data,
      'pagination': {
        'page': page,
        'limit': limit,
        'total': total,
        'totalPages': totalPages,
        'hasNext': page < totalPages,
        'hasPrevious': page > 1 && totalPages > 0,
      },
    });
  }

  Response get(Request request, String rawId) =>
      jsonResponse({'data': _findPost(rawId)});

  Future<Response> create(Request request) async {
    final body = await readJsonObject(request);
    _validatePost(body, requireAll: true);
    final post = _posts.create({
      'title': body['title'],
      'body': body['body'],
      'published': body['published'] ?? false,
      'userId': body['userId'],
    });
    return jsonResponse({'data': post}, status: HttpStatus.created);
  }

  Future<Response> replace(Request request, String rawId) async {
    final existing = _findPost(rawId);
    final body = await readJsonObject(request);
    _validatePost(body, requireAll: true);
    final replacement = _posts.replace(existing, {
      'title': body['title'],
      'body': body['body'],
      'published': body['published'] ?? false,
      'userId': body['userId'],
    });
    return jsonResponse({'data': replacement});
  }

  Future<Response> update(Request request, String rawId) async {
    final existing = _findPost(rawId);
    final body = await readJsonObject(request);
    if (body.isEmpty) {
      throw ApiException(400, 'Request body must contain at least one field');
    }
    _validatePost(body, requireAll: false);
    final values = <String, Object?>{};
    for (final field in ['title', 'body', 'published', 'userId']) {
      if (body.containsKey(field)) values[field] = body[field];
    }
    return jsonResponse({'data': _posts.update(existing, values)});
  }

  Response delete(Request request, String rawId) {
    _posts.delete(_findPost(rawId));
    return Response(HttpStatus.noContent);
  }

  Map<String, Object?> _findPost(String rawId) {
    final id = int.tryParse(rawId);
    if (id == null || id < 1) throw ApiException(400, 'Invalid post id');
    return _posts.findById(id);
  }

  void _validatePost(Map<String, Object?> body, {required bool requireAll}) {
    const allowed = {'title', 'body', 'published', 'userId'};
    final unknown = body.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw ApiException(400, 'Unknown fields: ${unknown.join(', ')}');
    }
    if (requireAll) {
      for (final field in ['title', 'body', 'userId']) {
        if (!body.containsKey(field)) {
          throw ApiException(422, 'Missing required field: $field');
        }
      }
    }
    if (body.containsKey('title') &&
        (body['title'] is! String ||
            (body['title'] as String).trim().isEmpty)) {
      throw ApiException(422, 'title must be a non-empty string');
    }
    if (body.containsKey('body') &&
        (body['body'] is! String || (body['body'] as String).trim().isEmpty)) {
      throw ApiException(422, 'body must be a non-empty string');
    }
    if (body.containsKey('published') && body['published'] is! bool) {
      throw ApiException(422, 'published must be a boolean');
    }
    if (body.containsKey('userId') &&
        (body['userId'] is! int || (body['userId'] as int) < 1)) {
      throw ApiException(422, 'userId must be a positive integer');
    }
  }
}
