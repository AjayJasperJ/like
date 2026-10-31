import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  test('multipart snapshots survive consumed bodies and reconstruct fresh uploads', () async {
    const codec = DefaultLikeReplayCodec();
    final form = FormData()..fields.addAll([const MapEntry('tag', 'a'), const MapEntry('tag', 'b')]);
    form.files.add(MapEntry('file', MultipartFile.fromBytes([1, 2, 3], filename: 'sample.bin')));
    await form.finalize().drain<void>();
    final snapshot = await codec.encode(form);
    final restored = codec.decode(snapshot) as FormData;
    expect(restored.fields.map((e) => e.value), ['a', 'b']);
    expect(restored.files.single.value.filename, 'sample.bin');
    final bytes = await restored.files.single.value.finalize().expand((chunk) => chunk).toList();
    expect(bytes, [1, 2, 3]);
    expect((codec.decode(snapshot) as FormData).isFinalized, isFalse);
  });

  test('codec rejects unsupported values and oversized upload snapshots', () async {
    const codec = DefaultLikeReplayCodec(maximumBytes: 2);
    await expectLater(codec.encode(Object()), throwsArgumentError);
    final form = FormData()..files.add(MapEntry('file', MultipartFile.fromBytes([1, 2, 3])));
    await expectLater(codec.encode(form), throwsStateError);
    final encoded = await codec.encode(Uint8List.fromList([1, 2]));
    expect(codec.decode(encoded), [1, 2]);
  });

  test('retry policy honors seconds, HTTP dates, bounds and positive jitter', () {
    final now = DateTime.utc(2026, 10, 31, 12);
    final policy = LikeRetryPolicy(random: () => 0);
    expect(policy.rateLimit('5', 0, now: now), const Duration(seconds: 5));
    expect(policy.rateLimit('Sat, 31 Oct 2026 12:00:10 GMT', 0, now: now), const Duration(seconds: 10));
    expect(policy.rateLimit('120', 0, now: now), isNull);
    expect(policy.rateLimit('invalid', 2, now: now), const Duration(seconds: 4));
    expect(policy.rateLimit('-1', 0, now: now), Duration.zero);
    final jittered = LikeRetryPolicy(random: () => 1).rateLimit('5', 0)!;
    expect(jittered, const Duration(seconds: 6));
  });
}
