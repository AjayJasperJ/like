import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

class MockDio extends Mock implements Dio {}

class MockHttpClientAdapter extends Mock implements HttpClientAdapter {}

class MockResponse extends Mock implements Response {}

class FakeRequestOptions extends Fake implements RequestOptions {}

void setupMocks() {
  registerFallbackValue(FakeRequestOptions());
  registerFallbackValue(Stream<List<int>>.fromIterable([]));
}

Future<void> initTestHive() async {
  final tempDir = Directory.systemTemp.createTempSync('hive_test_');
  Hive.init(tempDir.path);
}
