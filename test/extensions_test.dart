import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  group('String Extensions on String?', () {
    test('capitalize capitalizes first letter and handles null/empty', () {
      expect('hello'.capitalize, equals('Hello'));
      expect('world'.capitalize, equals('World'));
      expect(''.capitalize, equals(''));

      String? nullStr;
      expect(nullStr.capitalize, equals(''));
    });

    test('titleCase capitalizes each word and handles null/empty', () {
      expect('hello world'.titleCase, equals('Hello World'));

      String? nullStr;
      expect(nullStr.titleCase, equals(''));
    });

    test('isEmail and isUrl validation with null-safety', () {
      expect('user@example.com'.isEmail, isTrue);
      expect('invalid-email'.isEmail, isFalse);

      String? nullEmail;
      expect(nullEmail.isEmail, isFalse);

      expect('https://flutter.dev'.isUrl, isTrue);
      expect('not-a-url'.isUrl, isFalse);

      String? nullUrl;
      expect(nullUrl.isUrl, isFalse);
    });

    test('nullable string extensions', () {
      String? emptyStr = '   ';
      expect(emptyStr.isNullOrEmpty, isTrue);
      expect(emptyStr.isNotNullOrEmpty, isFalse);

      String? validStr = 'hello';
      expect(validStr.isNotNullOrEmpty, isTrue);
      expect(validStr.capitalizeOr('default'), equals('Hello'));
    });
  });

  group('Number Extensions on num?', () {
    test('clean formats integers without decimal and doubles with decimal', () {
      expect(5.0.clean, equals('5'));
      expect(5.5.clean, equals('5.5'));
      expect(10.clean, equals('10'));

      num? nullNum;
      expect(nullNum.clean, equals('0'));
    });

    test('padLeft and toCurrency with null-safety', () {
      expect(5.padLeft(3), equals('005'));
      expect(19.99.toCurrency(), equals('\$19.99'));

      num? nullNum;
      expect(nullNum.padLeft(3), equals('000'));
      expect(nullNum.toCurrency(), equals('\$0.00'));
    });

    test('nullable num fallbacks', () {
      num? val;
      expect(val.orZero, equals(0));
      expect(val.intOrZero, equals(0));
      expect(val.doubleOrZero, equals(0.0));

      num? numVal = 42.5;
      expect(numVal.intOrZero, equals(42));
    });
  });

  group('DateTime Extensions on DateTime', () {
    test('isToday and toDateString', () {
      final now = DateTime.now();
      expect(now.isToday, isTrue);
      expect(now.toDateString.length, equals(10));
    });

    test('timeAgo format', () {
      final past = DateTime.now().subtract(const Duration(minutes: 5));
      expect(past.timeAgo, equals('5m ago'));
    });

    test('next & previous day/week/month/year', () {
      final date = DateTime(2026, 3, 15, 10, 30);
      expect(date.nextDay, equals(DateTime(2026, 3, 16, 10, 30)));
      expect(date.previousDay, equals(DateTime(2026, 3, 14, 10, 30)));

      expect(date.nextWeek, equals(DateTime(2026, 3, 22, 10, 30)));
      expect(date.previousWeek, equals(DateTime(2026, 3, 8, 10, 30)));

      expect(date.nextMonth, equals(DateTime(2026, 4, 15, 10, 30)));
      expect(date.previousMonth, equals(DateTime(2026, 2, 15, 10, 30)));

      expect(date.nextYear, equals(DateTime(2027, 3, 15, 10, 30)));
      expect(date.previousYear, equals(DateTime(2025, 3, 15, 10, 30)));
    });

    test('start & end of day/week/month/year', () {
      final date = DateTime(2026, 9, 20, 14, 45, 30); // Sunday

      expect(date.startOfDay, equals(DateTime(2026, 9, 20, 0, 0, 0)));
      expect(date.endOfDay, equals(DateTime(2026, 9, 20, 23, 59, 59, 999)));

      expect(
          date.startOfWeek, equals(DateTime(2026, 9, 14, 0, 0, 0))); // Monday
      expect(date.endOfWeek,
          equals(DateTime(2026, 9, 20, 23, 59, 59, 999))); // Sunday

      expect(date.startOfMonth, equals(DateTime(2026, 9, 1, 0, 0, 0)));
      expect(date.endOfMonth, equals(DateTime(2026, 9, 30, 23, 59, 59, 999)));

      expect(date.startOfYear, equals(DateTime(2026, 1, 1, 0, 0, 0)));
      expect(date.endOfYear, equals(DateTime(2026, 12, 31, 23, 59, 59, 999)));
    });

    test('isSameDay, isSameMonth, isSameYear and differenceFrom', () {
      final d1 = DateTime(2026, 9, 20, 10, 0);
      final d2 = DateTime(2026, 9, 20, 18, 30);
      final d3 = DateTime(2026, 9, 21, 10, 0);
      final d4 = DateTime(2026, 10, 20, 10, 0);
      final d5 = DateTime(2027, 9, 20, 10, 0);

      expect(d1.isSameDay(d2), isTrue);
      expect(d1.isSameDay(d3), isFalse);

      expect(d1.isSameMonth(d4), isFalse);
      expect(d1.isSameMonth(d2), isTrue);

      expect(d1.isSameYear(d5), isFalse);
      expect(d1.isSameYear(d4), isTrue);

      expect(d3.differenceFrom(d1), equals(const Duration(hours: 24)));
    });
  });
}
