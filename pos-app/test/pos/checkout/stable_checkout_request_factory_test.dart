import 'package:berkahtigaputeri_pos/features/pos/checkout/payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StableCheckoutRequestFactory', () {
    test('identical retry reuses the same transaction ID and timestamp', () {
      var generatedIds = 0;
      var clockCalls = 0;
      final factory = StableCheckoutRequestFactory(
        idGenerator: () => 'TRX-TEST-${++generatedIds}',
        clock: () {
          clockCalls++;
          return DateTime.utc(2026, 10, 19, 1, 2, clockCalls);
        },
      );
      const lines = <PaymentLineInput>[
        PaymentLineInput(productId: 'P-1', quantity: 2),
      ];

      final first = factory.create(method: PaymentMethod.cash, lines: lines);
      final retry = factory.create(method: PaymentMethod.cash, lines: lines);

      expect(retry.transactionId, first.transactionId);
      expect(retry.occurredAtUtc, first.occurredAtUtc);
      expect(generatedIds, 1);
      expect(clockCalls, 1);
    });

    test('changed cart or payment method rotates key; reset starts new intent', () {
      var generatedIds = 0;
      final factory = StableCheckoutRequestFactory(
        idGenerator: () => 'TRX-TEST-${++generatedIds}',
        clock: () => DateTime.utc(2026, 10, 19),
      );
      const oneItem = <PaymentLineInput>[
        PaymentLineInput(productId: 'P-1', quantity: 1),
      ];
      final first = factory.create(method: PaymentMethod.cash, lines: oneItem);
      final changed = factory.create(
        method: PaymentMethod.cash,
        lines: const <PaymentLineInput>[
          PaymentLineInput(productId: 'P-1', quantity: 2),
        ],
      );
      final changedMethod = factory.create(
        method: PaymentMethod.qris,
        lines: const <PaymentLineInput>[
          PaymentLineInput(productId: 'P-1', quantity: 2),
        ],
      );
      factory.reset();
      final newIntent = factory.create(method: PaymentMethod.cash, lines: oneItem);

      expect(changed.transactionId, isNot(first.transactionId));
      expect(changedMethod.transactionId, isNot(changed.transactionId));
      expect(newIntent.transactionId, isNot(first.transactionId));
      expect(generatedIds, 4);
    });
  });
}
