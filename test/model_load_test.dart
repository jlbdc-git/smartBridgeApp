import 'package:flutter_test/flutter_test.dart';
import 'package:smartbridgeapp/services/model_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelService baseline contract', () {
    test('exposes gesture class labels for inference output', () {
      final modelService = ModelService();
      expect(modelService.signLabels, isNotEmpty);
      // The shipped Senyas FSL model uses Filipino sign labels (see
      // assets/models/labels.txt), not the earlier MediaPipe gesture set.
      expect(modelService.signLabels, contains('kamusta'));
      expect(modelService.signLabels, contains('salamat'));
      expect(modelService.signLabels, contains('ako'));
    });

    test('reports not loaded before initialization', () {
      final modelService = ModelService();
      expect(modelService.isModelLoaded, isFalse);
      expect(modelService.getModelInfo(), contains('Model not loaded'));
    });
  });
}
