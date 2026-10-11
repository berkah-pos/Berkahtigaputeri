import 'package:flutter_test/flutter_test.dart';
import 'package:berkah_pos/main.dart';

void main() {
  test('Rupiah formatter groups thousands with dots', () {
    expect(formatRupiah(0), 'Rp0');
    expect(formatRupiah(12000), 'Rp12.000');
    expect(formatRupiah(1250000), 'Rp1.250.000');
    expect(formatRupiah(-1500), '-Rp1.500');
  });
}
