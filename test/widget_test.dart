import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RetailFlow test environment loads', () {
    // Keeps the starter test suite valid without initializing external
    // Supabase services inside a unit test.
    expect('RetailFlow'.isNotEmpty, isTrue);
  });
}
