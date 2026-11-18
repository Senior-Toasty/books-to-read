import 'package:flutter_test/flutter_test.dart';
import 'package:bookhunter/main.dart';

void main() {
  testWidgets('BookHunter home renders discover and format cards', (tester) async {
    await tester.pumpWidget(const BookHunterApp());
    expect(find.text('BOOKHUNTER'), findsOneWidget);
    expect(find.text('Ebooks'), findsOneWidget);
    expect(find.text('Audiobooks'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Search five catalogues at once'), findsOneWidget);
  });

  testWidgets('navigation opens library and downloads placeholders', (tester) async {
    await tester.pumpWidget(const BookHunterApp());
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Your library'), findsOneWidget);
    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Downloads'), findsWidgets);
  });

  testWidgets('search opens results screen and offers result filters', (tester) async {
    await tester.pumpWidget(const BookHunterApp());
    await tester.enterText(find.byType(TextField), 'Dune');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('Results for “Dune”'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Ebooks'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
  });
}
