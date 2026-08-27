/// Désérialisation du résultat Style DNA — sans réseau ni clé API.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/repositories/style_dna_repository.dart';

const _payload = {
  'face_detected': true,
  'face_shape': 'oval',
  'shape_label_ar': 'وجه بيضاوي',
  'confidence': 0.86,
  'analysis_ar': 'وجهك أطول شوية من عرضو.',
  'styles': [
    {
      'name': 'Textured Crop',
      'name_ar': 'كروب تكستشر',
      'description_ar': 'يبين ملامحك.',
      'match_score': 91,
      'tags': ['عصري', 'سهل'],
      'recommended': true,
    },
  ],
  'avoid_ar': ['شعر طويل مسطح'],
  'model': 'claude-opus-5',
};

void main() {
  group('StyleDnaResult', () {
    test('une analyse complète est lue intégralement', () {
      final result = StyleDnaResult.fromJson(Map<String, dynamic>.from(_payload));

      expect(result.faceDetected, isTrue);
      expect(result.faceShape, 'oval');
      expect(result.shapeLabelAr, 'وجه بيضاوي');
      expect(result.confidencePct, 86);
      expect(result.styles.single.nameAr, 'كروب تكستشر');
      expect(result.styles.single.recommended, isTrue);
      expect(result.avoidAr, ['شعر طويل مسطح']);
      expect(result.model, 'claude-opus-5');
    });

    test('la confiance est affichée en pourcentage borné', () {
      double pct(num c) => StyleDnaResult.fromJson({..._payload, 'confidence': c})
          .confidencePct
          .toDouble();

      expect(pct(0), 0);
      expect(pct(0.5), 50);
      expect(pct(1), 100);
      // Le backend borne déjà, mais l'app ne doit jamais afficher 140 %.
      expect(pct(1.4), 100);
      expect(pct(-0.2), 0);
    });

    test('« pas de visage » est un résultat valide, pas une erreur', () {
      final result = StyleDnaResult.fromJson(const {
        'face_detected': false,
        'face_shape': '',
        'shape_label_ar': '',
        'confidence': 0,
        'analysis_ar': '',
        'styles': [],
        'avoid_ar': [],
      });

      expect(result.faceDetected, isFalse);
      expect(result.styles, isEmpty);
    });

    test('des champs absents ne font pas planter le parsing', () {
      final result = StyleDnaResult.fromJson(const {'face_detected': true});

      expect(result.faceShape, isEmpty);
      expect(result.confidencePct, 0);
      expect(result.styles, isEmpty);
      expect(result.avoidAr, isEmpty);
    });
  });

  group('StyleSuggestion', () {
    test('les tags absents deviennent une liste vide', () {
      final style = StyleSuggestion.fromJson(const {'name': 'Fade'});
      expect(style.tags, isEmpty);
      expect(style.matchScore, 0);
      expect(style.recommended, isFalse);
    });
  });
}
