import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/customer/customer_app.dart';

void main() {
  testWidgets('Customer App onboarding smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CustomerApp());

    // Verify that our onboarding screen text is present.
    expect(find.text('Torkk Rider'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
