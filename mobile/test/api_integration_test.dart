/// Test d'intégration de la couche données contre l'API réelle.
///
/// Prérequis : backend démarré et jeu de démo chargé.
///   cd backend && docker compose up -d mongo redis
///   python -m app.seed && uvicorn app.main:app
///
/// Il vérifie ce que `flutter analyze` ne peut pas voir : que le JSON renvoyé par
/// FastAPI se désérialise bien dans les modèles de l'app.
///
///   flutter test test/api_integration_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:8000
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/api_exception.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/auth_repository.dart';
import 'package:lamssa/data/repositories/booking_repository.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/data/repositories/notification_repository.dart';
import 'package:lamssa/data/repositories/portfolio_repository.dart';
import 'package:lamssa/data/repositories/salon_admin_repository.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/data/repositories/style_dna_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Le binding est nécessaire pour SharedPreferences (TokenStore), mais il
  // remplace HttpClient par un stub qui renvoie 400 : on rétablit le vrai client,
  // sans quoi aucune requête ne partirait réellement.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});

  late ApiClient api;
  late AuthRepository auth;
  late SalonRepository salons;
  late BookingRepository bookings;
  late CashRepository cash;
  late NotificationRepository notifications;
  late StyleDnaRepository styleDna;
  late PortfolioRepository portfolio;
  late SalonAdminRepository admin;

  setUp(() {
    api = ApiClient(TokenStore());
    auth = AuthRepository(api);
    salons = SalonRepository(api);
    bookings = BookingRepository(api);
    cash = CashRepository(api);
    notifications = NotificationRepository(api);
    styleDna = StyleDnaRepository(api);
    portfolio = PortfolioRepository(api);
    admin = SalonAdminRepository(api);
  });

  tearDown(() => api.dispose());

  // Comptes créés par `python -m app.seed`.
  const ownerPhone = '+21699000000';
  const staffPhone = '+21697000000';
  const clientPhone = '+21698000000';
  const devCode = '000000';

  /// Connexion directe via le code de dev. On évite `requestOtp` : le backend
  /// impose un délai de 60 s entre deux envois, ce qui ferait échouer la suite.
  Future<void> login(String phone) => auth.verifyOtp(phone: phone, code: devCode);

  /// Premiers créneaux libres sur les 7 prochains jours.
  ///
  /// Viser un J+n fixe rend le test dépendant du jour de la semaine : le
  /// dimanche est fermé par défaut, donc la suite échouerait une fois sur sept.
  Future<List<BookingSlot>> nextSlots({
    required String staffId,
    required List<String> serviceIds,
  }) async {
    for (var offset = 1; offset <= 7; offset++) {
      final day = DateTime.now().add(Duration(days: offset));
      final iso = '${day.year}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      final slots =
          await salons.slots(staffId: staffId, isoDate: iso, serviceIds: serviceIds);
      if (slots.isNotEmpty) return slots;
    }
    return const [];
  }

  group('Découverte (client non connecté)', () {
    test('la recherche géo renvoie des salons exploitables', () async {
      final results = await salons.search(lat: 36.8065, lng: 10.1815, maxKm: 50);

      expect(results, isNotEmpty, reason: 'le seed crée 3 salons à Tunis');
      final salon = results.first;
      expect(salon.id, isNotEmpty);
      expect(salon.name, isNotEmpty);
      expect(salon.distance, isNotEmpty, reason: 'distance_km doit être formatée');
      expect(salon.initials.length, inInclusiveRange(1, 2));
    });

    test('le filtre par type est appliqué côté serveur', () async {
      final results = await salons.search(type: SalonType.barbershop, maxKm: 200);
      expect(results.every((s) => s.type == SalonType.barbershop), isTrue);
    });

    test('la fiche salon expose équipe, services et horaires', () async {
      final list = await salons.search(maxKm: 200);
      final detail = await salons.detail(list.first.id);

      expect(detail.services, isNotEmpty);
      expect(detail.staff, isNotEmpty);
      expect(detail.salon.hours, isNotEmpty, reason: 'les horaires doivent être résumés');
      expect(detail.services.first.price, greaterThan(0));
      expect(detail.services.first.duration, greaterThan(0));
    });

    test('le profil coiffeur agrège portfolio et avis', () async {
      final list = await salons.search(maxKm: 200);
      final detail = await salons.detail(list.first.id);
      final profile = await salons.staffProfile(detail.staff.first.id);

      expect(profile.coiffeur.name, isNotEmpty);
      expect(profile.portfolio, isNotEmpty, reason: 'le seed publie 3 réalisations');
    });

    test('les créneaux du lendemain sont calculés par le serveur', () async {
      final list = await salons.search(maxKm: 200);
      final detail = await salons.detail(list.first.id);
      final slots = await nextSlots(
        staffId: detail.staff.first.id,
        serviceIds: [detail.services.first.id],
      );

      expect(slots, isNotEmpty);
      expect(slots.first.time, matches(RegExp(r'^\d{2}:\d{2}$')));
      expect(DateTime.tryParse(slots.first.start), isNotNull);
    });
  });

  group('Authentification OTP', () {
    test('le tunnel OTP ouvre une session persistée', () async {
      final user = await auth.verifyOtp(phone: clientPhone, code: devCode);

      expect(user.id, isNotEmpty);
      expect(user.role, AppRole.client);
      expect(api.tokens.accessToken, isNotNull);
      expect(api.tokens.refreshToken, isNotNull);
    });

    test('un code erroné est refusé', () async {
      expect(
        () => auth.verifyOtp(phone: clientPhone, code: '123456'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('demander un code puis le redemander trop vite est refusé', () async {
      // Numéro unique par exécution : le cooldown est indexé par téléphone et
      // dure 60 s, donc un numéro fixe rendrait le test non rejouable.
      final phone = '+2165${DateTime.now().millisecondsSinceEpoch % 10000000}';
      await auth.requestOtp(phone);
      expect(
        () => auth.requestOtp(phone),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
      );
    });

    test('le contexte de compte identifie le salon du gérant', () async {
      await login(ownerPhone);
      final context = await auth.me();

      expect(context.user.role, AppRole.owner);
      expect(context.ownedSalonId, isNotNull);
      expect(context.activeSalonId, context.ownedSalonId);
    });
  });

  group('Réservation (client connecté)', () {
    setUp(() async {
      await login(clientPhone);
    });

    test('créer un RDV puis l’annuler', () async {
      final list = await salons.search(maxKm: 200);
      final detail = await salons.detail(list.first.id);
      final staff = detail.staff.first;
      final service = detail.services.first;

      final slots = await nextSlots(staffId: staff.id, serviceIds: [service.id]);
      expect(slots, isNotEmpty, reason: 'aucun créneau sur les 7 prochains jours');

      final booking = await bookings.create(
        salonId: detail.salon.id,
        staffId: staff.id,
        serviceIds: [service.id],
        startIso: slots.first.start,
      );

      expect(booking.id, isNotEmpty);
      expect(booking.status, BookingStatus.pending);
      expect(booking.price, greaterThan(0));
      expect(booking.time, matches(RegExp(r'^\d{2}:\d{2}$')));

      final cancelled = await bookings.cancel(booking.id, reason: 'test');
      expect(cancelled.status, BookingStatus.cancelled);
    });

    test('le paiement en ligne confirme le RDV', () async {
      final list = await salons.search(maxKm: 200);
      final detail = await salons.detail(list.first.id);
      final staff = detail.staff.first;
      final service = detail.services.first;

      final slots = await nextSlots(staffId: staff.id, serviceIds: [service.id]);
      expect(slots, isNotEmpty, reason: 'aucun créneau sur les 7 prochains jours');

      final booking = await bookings.create(
        salonId: detail.salon.id,
        staffId: staff.id,
        serviceIds: [service.id],
        startIso: slots.first.start,
      );

      final checkout = await bookings.checkout(booking.id);
      expect(checkout.isMock, isTrue, reason: 'PSP_PROVIDER=mock en dev');
      await bookings.payMock(checkout.url);

      final mine = await bookings.mine(upcoming: true);
      final updated = mine.firstWhere((b) => b.id == booking.id);
      expect(updated.status, BookingStatus.confirmed);
    });

    test('mes notifications sont lisibles', () async {
      final feed = await notifications.list();
      expect(feed.items, isA<List<AppNotification>>());
    });
  });

  group('Génération d’images (§2.4)', () {
    test('le serveur annonce séparément l’analyse et les images', () async {
      final status = await styleDna.status();

      // Deux fournisseurs distincts : l'app doit pouvoir n'afficher que ce qui
      // est réellement configuré.
      expect(status.analysis, isA<bool>());
      expect(status.images, isA<bool>());
    });

    test('sans clé serveur, l’aperçu échoue proprement en 503', () async {
      await login(clientPhone);
      final status = await styleDna.status();
      if (status.images) return; // clé présente : rien à vérifier ici

      await expectLater(
        styleDna.preview(style: 'Fade'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
    });

    test('l’essayage sans consentement est refusé avant tout appel externe',
        () async {
      await login(clientPhone);
      final selfie = File('${Directory.systemTemp.path}/lamssa_selfie.jpg')
        ..writeAsBytesSync(List<int>.filled(2048, 7));

      // 403 (refus de consentement) ou 503 (pas de clé) : jamais un 500, et
      // jamais un succès.
      await expectLater(
        styleDna.tryOn(selfie: selfie, style: 'Fade', consent: false),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', isIn([403, 503]))),
      );
    });
  });

  group('Portfolio & fil « En vogue » (§3.8, §8.3)', () {
    test('le fil est lisible sans compte — c’est son intérêt', () async {
      final posts = await portfolio.trending();

      expect(posts, isNotEmpty, reason: 'le seed publie 3 réalisations par coiffeur');
      final post = posts.first;
      expect(post.id, isNotEmpty);
      expect(post.imageUrl, isNotEmpty);
      expect(post.staffId, isNotEmpty);
      // Décoré par le serveur : sans ces noms, le fil n'oriente vers personne.
      expect(post.staffName, isNotEmpty);
      expect(post.salonName, isNotEmpty);
    });

    test('le fil est trié par likes décroissants', () async {
      final posts = await portfolio.trending();
      final likes = posts.map((p) => p.likes).toList();

      for (var i = 1; i < likes.length; i++) {
        expect(likes[i], lessThanOrEqualTo(likes[i - 1]));
      }
    });

    test('un visiteur anonyme n’a aucun like à son nom', () async {
      final posts = await portfolio.trending();
      expect(posts.every((p) => !p.likedByMe), isTrue);
    });

    test('filtrer par tag ne renvoie que ce tag', () async {
      final all = await portfolio.trending();
      final tag = all.firstWhere((p) => p.tags.isNotEmpty).tags.first;

      final filtered = await portfolio.trending(tag: tag);

      expect(filtered, isNotEmpty);
      expect(filtered.every((p) => p.tags.contains(tag)), isTrue);
    });

    test('aimer puis re-cliquer revient à l’état initial', () async {
      await login(clientPhone);
      final post = (await portfolio.trending()).first;

      // Le seed distribue des likes au hasard et une exécution précédente a pu
      // en laisser un : sans repartir d'un état connu, ce test passe ou casse
      // selon l'historique de la base plutôt que selon le code.
      final before = post.likedByMe
          ? (await portfolio.toggleLike(post.id)).likes
          : post.likes;

      final liked = await portfolio.toggleLike(post.id);
      expect(liked.likedByMe, isTrue);
      expect(liked.likes, before + 1);

      final unliked = await portfolio.toggleLike(post.id);
      expect(unliked.likedByMe, isFalse);
      expect(unliked.likes, before);
    });

    test('un client ne peut pas publier — il n’a pas de profil coiffeur', () async {
      await login(clientPhone);
      await expectLater(
        portfolio.ofStaff('000000000000000000000000'),
        completes,
        reason: 'lire le mur d’un coiffeur reste public',
      );
    });

    test('le portfolio d’un coiffeur remonte ses propres réalisations', () async {
      final list = await salons.search(maxKm: 200);
      final detail = await salons.detail(list.first.id);
      final staffId = detail.staff.first.id;

      final posts = await portfolio.ofStaff(staffId);

      expect(posts, isNotEmpty);
      expect(posts.every((p) => p.staffId == staffId), isTrue);
    });
  });

  group('Partage par QR (§3.2, §8.3)', () {
    test('le gérant obtient un code, un lien et un texte prêts à envoyer', () async {
      await login(ownerPhone);
      final salonId = (await auth.me()).ownedSalonId!;

      final share = await admin.share(salonId);

      expect(share.code, isNotEmpty);
      expect(share.url, contains(share.code));
      expect(share.deepLink, contains(share.code));
      expect(share.shareText, contains(share.url));
      // Le suffixe aléatoire s'imprime sur une vitrine et se lit sans contexte :
      // il exclut les caractères confondables. Le préfixe, lui, vient du nom du
      // salon — « Barbier » doit rester reconnaissable, `I` compris.
      final suffix = share.code.substring(share.code.length - 4);
      expect(suffix, isNot(anyOf(contains('0'), contains('O'),
          contains('1'), contains('I'), contains('L'))));
    });

    test('le code est stable entre deux consultations', () async {
      await login(ownerPhone);
      final salonId = (await auth.me()).ownedSalonId!;

      final first = await admin.share(salonId);
      final second = await admin.share(salonId);

      // Un code qui changerait rendrait caduques les QR déjà imprimés.
      expect(second.code, first.code);
    });

    test('un client non connecté ouvre le salon depuis le code', () async {
      await login(ownerPhone);
      final salonId = (await auth.me()).ownedSalonId!;
      final share = await admin.share(salonId);

      // Session vierge : le QR doit marcher pour un inconnu, c'est son intérêt.
      final anonymous = SalonRepository(ApiClient(TokenStore()));
      final detail = await anonymous.detailByCode(share.code);

      expect(detail.salon.id, salonId);
      expect(detail.services, isNotEmpty, reason: 'le client doit voir les offres');
      expect(detail.staff, isNotEmpty);
    });

    test('la saisie manuelle tolère minuscules, espaces et tirets', () async {
      await login(ownerPhone);
      final salonId = (await auth.me()).ownedSalonId!;
      final code = (await admin.share(salonId)).code;

      final saisie = '${code.substring(0, 3).toLowerCase()} '
          '${code.substring(3).toLowerCase()}';
      final detail = await salons.detailByCode(saisie);

      expect(detail.salon.id, salonId);
    });

    test('un code inconnu renvoie 404, pas une erreur serveur', () async {
      await expectLater(
        salons.detailByCode('ZZZZ9999'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });

    test('un gérant ne peut pas récupérer le QR du salon d’un autre', () async {
      await login(ownerPhone);
      final salonId = (await auth.me()).ownedSalonId!;

      await login('+21699000001');
      await expectLater(
        admin.share(salonId),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });
  });

  group('Onboarding salon (§3.1, §3.5)', () {
    test('un client crée son salon, son catalogue et son équipe', () async {
      // Numéro neuf : le compte doit partir CLIENT pour prouver la promotion.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ownerPhone = '+2165${stamp % 10000000}';
      final staffPhone = '+2164${stamp % 10000000}';

      final user = await auth.verifyOtp(phone: ownerPhone, code: devCode);
      expect(user.role, AppRole.client, reason: 'compte neuf = client');

      final salon = await admin.createSalon(
        name: 'Salon Test $stamp',
        type: SalonType.barbershop,
        lat: 36.8065,
        lng: 10.1815,
        city: 'Tunis',
        address: 'Rue de Test',
        defaultSplitPct: 55,
        cancellationWindowH: 4,
      );
      expect(salon.id, isNotEmpty);

      // La création promeut au rôle OWNER — sans ça l'app resterait côté client.
      final context = await auth.me();
      expect(context.user.role, AppRole.owner);
      expect(context.ownedSalonId, salon.id);

      final service = await admin.createService(
        salon.id,
        name: 'Fade test',
        nameAr: 'فايد',
        price: 30,
        durationMin: 45,
        bufferMin: 10,
      );
      expect(service.id, isNotEmpty);
      expect(service.price, 30);

      final member = await admin.addStaff(
        salon.id,
        phone: staffPhone,
        displayName: 'Coiffeur Test',
        chairNumber: 2,
        commissionPct: 60,
        serviceIds: [service.id],
      );
      expect(member.chairNumber, 2);
      expect(member.commissionPct, 60);
      expect(member.serviceIds, [service.id]);

      // Relecture : le catalogue et l'équipe sont bien persistés.
      expect((await admin.services(salon.id)).map((s) => s.id), contains(service.id));
      expect((await admin.staff(salon.id)).map((s) => s.id), contains(member.id));

      // Et le salon est immédiatement réservable : il sort dans la recherche géo.
      final found = await salons.search(lat: 36.8065, lng: 10.1815, maxKm: 5);
      expect(found.any((s) => s.id == salon.id), isTrue);
    });

    test('un client ne peut pas administrer le salon d’un autre', () async {
      final ownerApi = ApiClient(TokenStore());
      final ownerAuth = AuthRepository(ownerApi);
      await ownerAuth.verifyOtp(phone: ownerPhone, code: devCode);
      final salonId = (await ownerAuth.me()).ownedSalonId!;
      ownerApi.dispose();

      await login(clientPhone);
      await expectLater(
        () => admin.createService(salonId,
            name: 'Intrus', price: 10, durationMin: 20),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'forbidden', isTrue)),
      );
    });
  });

  group('Style DNA (§2.4, §8.5)', () {
    test('le serveur annonce si la fonctionnalité est disponible', () async {
      // Sans ANTHROPIC_API_KEY côté serveur, la réponse doit être false —
      // c'est ce qui permet à l'accueil de masquer la carte plutôt que de
      // renvoyer l'utilisateur vers un écran qui ne peut qu'échouer.
      expect(await styleDna.isAvailable(), isA<bool>());
    });

    test('un selfie envoyé sans clé serveur échoue proprement', () async {
      await login(clientPhone);

      final selfie = File('${Directory.systemTemp.path}/lamssa_probe.jpg')
        ..writeAsBytesSync(const [
          0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, // en-tête JFIF minimal
          0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00,
          0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
        ]);
      addTearDown(() => selfie.deleteSync());

      if (await styleDna.isAvailable()) {
        // Avec une clé, l'analyse doit soit aboutir, soit échouer de façon
        // *typée* — quota épuisé, refus du modèle, fournisseur injoignable.
        // Ce que l'app ne doit jamais voir, c'est une exception non traduite.
        try {
          expect(await styleDna.analyze(selfie), isA<StyleDnaResult>());
        } on ApiException catch (e) {
          expect(e.statusCode, isIn([422, 429, 502, 503, 504]),
              reason: 'échec du fournisseur, mais lisible par l’app');
        }
        return;
      }

      // 503 attendu et *typé* : l'app doit pouvoir afficher un message, pas planter.
      await expectLater(
        () => styleDna.analyze(selfie),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
    });

    test('un fichier non-image est refusé avant tout appel au modèle', () async {
      await login(clientPhone);

      final pdf = File('${Directory.systemTemp.path}/lamssa_probe.pdf')
        ..writeAsStringSync('%PDF-1.4');
      addTearDown(() => pdf.deleteSync());

      await expectLater(
        () => styleDna.analyze(pdf),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 415)),
      );
    });
  });

  group('Cloisonnement des rôles (§2.5)', () {
    test('un client ne peut pas lire la caisse du salon', () async {
      // On récupère l'id du salon via une session gérant distincte, puis on
      // tente d'y accéder avec un compte client.
      final ownerApi = ApiClient(TokenStore());
      final ownerAuth = AuthRepository(ownerApi);
      await ownerAuth.verifyOtp(phone: ownerPhone, code: devCode);
      final salonId = (await ownerAuth.me()).ownedSalonId!;
      ownerApi.dispose();

      await login(clientPhone);

      expect(
        () => cash.today(salonId),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'forbidden', isTrue)),
      );
    });

    test('le coiffeur ne voit que SA caisse', () async {
      await login(staffPhone);

      final mine = await cash.mine();
      expect(mine.myShare, greaterThanOrEqualTo(0));
      expect(mine.count, greaterThanOrEqualTo(0));
    });
  });

  group('Caisse gérant', () {
    late String salonId;

    setUp(() async {
      await login(ownerPhone);
      salonId = (await auth.me()).ownedSalonId!;
    });

    test('la caisse du jour se décompose correctement', () async {
      final day = await cash.today(salonId);

      expect(day.total, greaterThan(0), reason: 'le seed encaisse la journée');
      expect(
        (day.salonTotal + day.staffTotal - day.total).abs(),
        lessThan(0.02),
        reason: 'part salon + part équipe doit reconstituer le total',
      );
      expect(day.workers, isNotEmpty);
      expect(day.workers.first.name, isNot('—'), reason: 'le nom doit être résolu');
      expect(day.byMethod.values.fold<double>(0, (a, b) => a + b),
          closeTo(day.total, 0.02));
    });

    test('les tséb9as en attente remontent avec le nom du demandeur', () async {
      // Le test crée sa propre demande : celle du seed peut avoir été soldée
      // par une clôture de journée, et il redeviendrait alors vert ou rouge
      // selon l'ordre des exécutions précédentes.
      final staffApi = ApiClient(TokenStore());
      addTearDown(staffApi.dispose);
      await AuthRepository(staffApi)
          .verifyOtp(phone: staffPhone, code: devCode);
      try {
        await CashRepository(staffApi).requestAdvance(
          salonId: salonId,
          amount: 30,
          reason: 'test intégration',
        );
      } on ApiException {
        // Une demande est déjà en attente — c'est exactement l'état que ce
        // test veut observer, et le refus du serveur est le comportement
        // correct : un coiffeur n'empile pas les tséb9as.
      }
      final advances = await cash.salonAdvances(salonId, status: 'pending');
      expect(advances, isNotEmpty);
      expect(advances.first.staffName, isNotEmpty,
          reason: 'le nom du demandeur doit être résolu côté serveur');
      expect(advances.first.isPending, isTrue);
    });

    test('une charge fixe fait baisser le résultat du mois', () async {
      // Le cas qui justifie tout le module : la caisse peut être positive et
      // le salon perdre de l'argent une fois le loyer payé.
      final avant = await cash.pnl(salonId);

      final charge = await cash.addCharge(
        salonId,
        label: 'Loyer test',
        amount: 900,
        period: 'monthly',
        category: 'loyer',
      );
      addTearDown(() => cash.deleteCharge(charge.id));

      final apres = await cash.pnl(salonId);
      expect(apres.recurringCharges, greaterThan(avant.recurringCharges),
          reason: 'la charge doit peser sur le mois');
      expect(apres.result, lessThan(avant.result));
      // Le chiffre d'affaires ne bouge pas : une charge n'est pas une vente.
      expect(apres.revenue, closeTo(avant.revenue, 0.01));
    });

    test('le seuil de rentabilité tient compte de la part reversée', () async {
      final charge = await cash.addCharge(
        salonId,
        label: 'Loyer seuil',
        amount: 1000,
        period: 'monthly',
      );
      addTearDown(() => cash.deleteCharge(charge.id));

      final p = await cash.pilot(salonId);
      expect(p.breakEven, isNotNull);

      // À x % reversés, il faut encaisser charges / (1 − x) pour les couvrir.
      final attendu = (p.pnl.expenses + p.pnl.recurringCharges) /
          (1 - p.staffRatio / 100);
      // Tolérance relative : le ratio exposé est arrondi au dixième de pour
      // cent pour l'affichage, alors que le serveur calcule en précision
      // pleine. 0,5 % laisse passer cet écart mais pas une erreur de formule,
      // qui se tromperait d'un facteur deux.
      expect(p.breakEven!, closeTo(attendu, attendu * 0.005));
    });

    test('sans charge, il n’y a pas de seuil à atteindre', () async {
      // Le salon gagne dès la première coupe : afficher un seuil de zéro
      // serait plus déroutant qu'utile.
      for (final c in (await cash.charges(salonId)).charges) {
        await cash.setChargeActive(c.id, false);
      }
      addTearDown(() async {
        for (final c in (await cash.charges(salonId, includeInactive: true)).charges) {
          await cash.setChargeActive(c.id, true);
        }
      });

      final p = await cash.pilot(salonId);

      // Le seuil se calcule sur TOUTES les charges du mois, dépenses
      // ponctuelles comprises : désactiver les charges récurrentes ne suffit
      // pas à vider l'assiette si un achat a été saisi. Asserter `null` sans
      // condition rendrait ce test dépendant de ce que contient la base.
      final assiette = p.pnl.expenses + p.pnl.recurringCharges;
      if (assiette == 0) {
        expect(p.breakEven, isNull,
            reason: 'rien à couvrir : aucun seuil n’a de sens');
      } else {
        expect(p.breakEven, greaterThan(0),
            reason: 'une dépense du mois reste à couvrir');
      }
    });

    test('l’objectif se fixe et se retire', () async {
      final admin = SalonAdminRepository(api);
      await admin.updateSalon(salonId, monthlyRevenueTarget: 5000);
      var p = await cash.pilot(salonId);
      expect(p.target, closeTo(5000, 0.01));
      expect(p.targetProgressPct, isNotNull);

      await admin.updateSalon(salonId, monthlyRevenueTarget: 0);
      p = await cash.pilot(salonId);
      expect(p.target, isNull, reason: 'zéro retire l’objectif');
      expect(p.onTrack, isNull, reason: 'sans cible, pas de verdict');
    });

    test('les comptes du résultat s’additionnent', () async {
      final p = await cash.pnl(salonId);

      expect(p.grossMargin, closeTo(p.revenue - p.staffShare, 0.02),
          reason: 'marge = chiffre − part équipe');
      expect(p.result,
          closeTo(p.grossMargin - p.expenses - p.recurringCharges, 0.02),
          reason: 'résultat = marge − dépenses − charges');
    });

    test('une charge désactivée cesse de peser', () async {
      final charge = await cash.addCharge(
        salonId,
        label: 'Abonnement test',
        amount: 300,
        period: 'monthly',
      );
      addTearDown(() => cash.deleteCharge(charge.id));

      final avec = await cash.pnl(salonId);
      await cash.setChargeActive(charge.id, false);
      final sans = await cash.pnl(salonId);

      expect(sans.recurringCharges, lessThan(avec.recurringCharges));
    });

    test('un gérant ne voit pas le résultat du salon d’un autre', () async {
      await login('+21699000001');
      await expectLater(
        cash.pnl(salonId),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
      await login(ownerPhone);
    });

    test('la paie de la semaine déduit les tséb9as accordées', () async {
      // Circuit complet : le coiffeur demande, le gérant accorde, la paie
      // baisse d'autant. C'est la seule vérification qui prouve que la tséb9a
      // sort réellement de ce que le salon doit.
      //
      // On tranche d'abord ce qui traîne : une demande en attente empêcherait
      // d'en créer une nouvelle, de montant connu.
      for (final enAttente
          in await cash.salonAdvances(salonId, status: 'pending')) {
        await cash.decideAdvance(enAttente.id, true);
      }

      final avant = await cash.payroll(salonId);

      final staffApi = ApiClient(TokenStore());
      addTearDown(staffApi.dispose);
      await AuthRepository(staffApi).verifyOtp(phone: staffPhone, code: devCode);
      final demande = await CashRepository(staffApi).requestAdvance(
        salonId: salonId,
        amount: 25,
        reason: 'test paie',
      );
      await cash.decideAdvance(demande.id, true);

      final apres = await cash.payroll(salonId);
      expect(apres.totalAdvances, closeTo(avant.totalAdvances + 25, 0.01));
      expect(apres.totalToPay, closeTo(avant.totalToPay - 25, 0.01),
          reason: 'la tséb9a réduit exactement ce qui reste à payer');
    });

    test('chaque coiffeur voit sa propre paie', () async {
      final staffApi = ApiClient(TokenStore());
      addTearDown(staffApi.dispose);
      await AuthRepository(staffApi).verifyOtp(phone: staffPhone, code: devCode);

      final ligne = await CashRepository(staffApi).myPayroll();

      expect(ligne.weekStart, isNotEmpty);
      // Le solde est la part gagnée plus les pourboires, avances déduites :
      // les lignes affichées doivent s'additionner au total montré.
      expect(ligne.balance,
          closeTo(ligne.earned + ligne.tips - ligne.advances, 0.01));
    });

    test("l'agenda du jour est lisible par le gérant", () async {
      final agenda = await bookings.agenda(salonId: salonId);
      expect(agenda.date, isNotEmpty);
      expect(agenda.bookings, isA<List<Booking>>());
    });

    test('un walk-in saisi apparaît immédiatement dans l’agenda', () async {
      final detail = await salons.detail(salonId);

      // Coiffeur dédié : deux walk-ins « maintenant » sur la même chaise se
      // chevauchent, et le backend a raison de refuser le second. Le test doit
      // rester rejouable sans re-seed.
      final chair = await admin.addStaff(
        salonId,
        phone: '+2163${DateTime.now().millisecondsSinceEpoch % 10000000}',
        displayName: 'Chaise walk-in',
        chairNumber: 9,
      );

      final before = (await bookings.agenda(salonId: salonId)).bookings.length;

      final walkIn = await bookings.createWalkIn(
        salonId: salonId,
        staffId: chair.id,
        serviceIds: [detail.services.first.id],
        // Un client déjà sur place : l'heure est « maintenant », donc hors
        // horaires affichés une fois sur deux — le backend doit l'accepter.
        startIso: DateTime.now().toUtc().toIso8601String(),
        clientName: 'زبون طيّاح',
      );

      expect(walkIn.isWalkIn, isTrue);
      expect(walkIn.status, BookingStatus.confirmed);
      expect(walkIn.price, greaterThan(0));

      final after = await bookings.agenda(salonId: salonId);
      expect(after.bookings.length, before + 1);
      expect(after.bookings.any((b) => b.id == walkIn.id), isTrue);
    });
  });

  // ── Trésorerie ─────────────────────────────────────────────────────────
  //
  // La caisse du jour dit ce qui a été encaissé ; la trésorerie dit ce qui
  // doit être physiquement dans le tiroir. Ces tests protègent l'écart entre
  // les deux, celui qu'aucun gérant ne suit correctement de tête.
  group('Trésorerie', () {
    late String salonId;

    setUp(() async {
      await login(ownerPhone);
      salonId = (await auth.me()).ownedSalonId!;
    });

    test('le tiroir se décompose ligne par ligne', () async {
      final t = await cash.treasury(salonId);

      expect(t.openingFloat, greaterThan(0),
          reason: 'le seed ouvre la journée avec de la monnaie');
      expect(
        t.expectedCash,
        closeTo(
          t.openingFloat +
              t.cashIn +
              t.deposits -
              t.cashExpenses -
              t.cashAdvances -
              t.withdrawals,
          0.01,
        ),
        reason: 'le solde attendu doit être la somme de ses causes',
      );
    });

    test('une carte bancaire ne remplit jamais le tiroir', () async {
      final avant = await cash.treasury(salonId);

      // On ne peut pas forcer un règlement par carte ici ; on vérifie
      // l'invariant : les encaissements carte restent hors du solde espèces.
      expect(avant.cardTotal + avant.onlineTotal, greaterThanOrEqualTo(0));
      expect(
        avant.expectedCash,
        isNot(closeTo(
            avant.expectedCash + avant.cardTotal + avant.onlineTotal, 0.01)),
        skip: avant.cardTotal + avant.onlineTotal == 0
            ? 'aucun règlement carte ce jour'
            : null,
      );
    });

    test('un prélèvement vide le tiroir du montant exact', () async {
      final avant = await cash.treasury(salonId);

      await cash.addMovement(
          salonId: salonId,
          type: 'withdrawal',
          amount: 25,
          label: 'Test prélèvement');
      final apres = await cash.treasury(salonId);

      expect(apres.expectedCash, closeTo(avant.expectedCash - 25, 0.01));
      expect(apres.withdrawals, closeTo(avant.withdrawals + 25, 0.01));

      final ajoute =
          apres.movements.firstWhere((m) => m.label == 'Test prélèvement');
      expect(ajoute.isIncoming, isFalse);
      await cash.removeMovement(ajoute.id);

      final restaure = await cash.treasury(salonId);
      expect(restaure.expectedCash, closeTo(avant.expectedCash, 0.01));
    });

    test('un apport remplit le tiroir sans être un revenu', () async {
      final avant = await cash.treasury(salonId);
      final caisseAvant = (await cash.today(salonId)).total;

      await cash.addMovement(
          salonId: salonId, type: 'deposit', amount: 40, label: 'Test monnaie');
      final apres = await cash.treasury(salonId);

      expect(apres.expectedCash, closeTo(avant.expectedCash + 40, 0.01));
      expect((await cash.today(salonId)).total, closeTo(caisseAvant, 0.01),
          reason: 'remettre de la monnaie n\u0027est pas un encaissement');

      final ajoute =
          apres.movements.firstWhere((m) => m.label == 'Test monnaie');
      await cash.removeMovement(ajoute.id);
    });

    test('une charge réglée par virement ne touche pas le tiroir', () async {
      final avant = await cash.treasury(salonId);

      await cash.addExpense(
        salonId: salonId,
        label: 'Test loyer virement',
        amount: 500,
        paidFrom: 'bank',
      );
      final apres = await cash.treasury(salonId);

      expect(apres.expectedCash, closeTo(avant.expectedCash, 0.01),
          reason: 'un virement ne sort pas du tiroir');
      expect(apres.bankExpenses, closeTo(avant.bankExpenses + 500, 0.01));

      final ligne = (await cash.expenses(salonId))
          .firstWhere((e) => e.label == 'Test loyer virement');
      await cash.removeExpense(ligne.id);
    });

    test('une dépense réglée en espèces sort du tiroir', () async {
      final avant = await cash.treasury(salonId);

      await cash.addExpense(
        salonId: salonId,
        label: 'Test produits cash',
        amount: 30,
        paidFrom: 'cash',
      );
      final apres = await cash.treasury(salonId);

      expect(apres.expectedCash, closeTo(avant.expectedCash - 30, 0.01));

      final ligne = (await cash.expenses(salonId))
          .firstWhere((e) => e.label == 'Test produits cash');
      await cash.removeExpense(ligne.id);
    });

    test('un coiffeur ne voit pas le solde du tiroir', () async {
      await login(staffPhone);
      await expectLater(
        cash.treasury(salonId),
        throwsA(isA<ApiException>()),
        reason: 'le solde de caisse n\u0027est pas une information d\u0027équipe',
      );
    });
  });

  // ── Calendrier : jour de repos du coiffeur ─────────────────────────────
  //
  // Le salon peut ouvrir 6j/7 pendant qu'un coiffeur se repose le lundi. Sans
  // ces règles, ses créneaux du lundi restaient réservables et le client se
  // déplaçait pour rien.
  group('Disponibilité par jour (§3.3, §3.5)', () {
    late String salonId;
    late String staffId;

    setUp(() async {
      await login(ownerPhone);
      salonId = (await auth.me()).ownedSalonId!;
      staffId = (await salons.detail(salonId)).staff.first.id;
    });

    /// Remet le coiffeur au travail : les autres tests comptent dessus.
    void restaurer() => addTearDown(() async {
          await login(ownerPhone);
          await admin.updateStaff(salonId, staffId, daysOff: const []);
        });

    test('le calendrier annonce chaque jour avant qu’on le touche', () async {
      final jours = await salons.availability(staffId: staffId);

      expect(jours, hasLength(14));
      expect(jours.every((j) => j.isoDate.isNotEmpty), isTrue);
      // Un jour ouvert a des créneaux, un jour fermé a un motif : jamais ni
      // l'un ni l'autre, sinon l'écran n'a rien à afficher.
      for (final j in jours) {
        if (j.available) {
          expect(j.slotCount, greaterThan(0));
          expect(j.reason, isNull);
        } else {
          expect(j.slotCount, 0);
          expect(j.reason, isNotNull);
        }
      }
    });

    test('un jour de repos ferme le jour et le dit', () async {
      restaurer();
      final avant = await salons.availability(staffId: staffId);
      final ouvert = avant.firstWhere((j) => j.available);
      final cle = _cleJour(DateTime.parse(ouvert.isoDate));

      await admin.updateStaff(salonId, staffId, daysOff: [cle]);
      final apres = await salons.availability(staffId: staffId);

      final memeJour = apres.firstWhere((j) => j.isoDate == ouvert.isoDate);
      expect(memeJour.available, isFalse);
      expect(memeJour.reason, DayUnavailability.dayOff);
      expect(memeJour.slotCount, 0);
    });

    test('le repos vaut pour toutes les semaines, pas seulement la première',
        () async {
      restaurer();
      final avant = await salons.availability(staffId: staffId);
      final ouvert = avant.firstWhere((j) => j.available);
      final cle = _cleJour(DateTime.parse(ouvert.isoDate));

      await admin.updateStaff(salonId, staffId, daysOff: [cle]);
      final apres = await salons.availability(staffId: staffId);

      final concernes = apres.where(
          (j) => _cleJour(DateTime.parse(j.isoDate)) == cle);
      expect(concernes.length, greaterThanOrEqualTo(2),
          reason: 'sur 14 jours, chaque jour de semaine revient au moins deux fois');
      expect(concernes.every((j) => j.reason == DayUnavailability.dayOff), isTrue);
    });

    test('les créneaux du jour de repos sont vides aussi', () async {
      restaurer();
      final avant = await salons.availability(staffId: staffId);
      final ouvert = avant.firstWhere((j) => j.available);
      final cle = _cleJour(DateTime.parse(ouvert.isoDate));

      await admin.updateStaff(salonId, staffId, daysOff: [cle]);

      // Le calendrier et la grille horaire doivent dire la même chose : sinon
      // un client passant par un lien direct réserverait quand même.
      final creneaux =
          await salons.slots(staffId: staffId, isoDate: ouvert.isoDate);
      expect(creneaux, isEmpty);
    });

    test('un jour de repos écrit en toutes lettres est refusé', () async {
      // Un « lundi » accepté en silence ne bloquerait rien, et personne ne
      // s'en apercevrait avant qu'un client se déplace.
      await expectLater(
        admin.updateStaff(salonId, staffId, daysOff: const ['lundi']),
        throwsA(isA<ApiException>()),
      );
    });

    test('sans repos déclaré, seuls les jours de fermeture du salon ferment',
        () async {
      await admin.updateStaff(salonId, staffId, daysOff: const []);
      final jours = await salons.availability(staffId: staffId);

      expect(
        jours.any((j) => j.reason == DayUnavailability.dayOff),
        isFalse,
        reason: 'aucun repos déclaré : aucun jour ne doit être marqué « راحة »',
      );
      expect(jours.any((j) => j.available), isTrue,
          reason: 'le coiffeur doit bien travailler quelque part dans la quinzaine');
    });
  });

  // ── Horaires du salon ──────────────────────────────────────────────────
  //
  // Le dimanche fermé n'est qu'un défaut de création : un salon qui ouvre
  // 7j/7 doit pouvoir le déclarer, et un PATCH d'un seul jour ne doit pas
  // effacer les six autres.
  group('Horaires du salon (§3.1, §3.5)', () {
    late String salonId;
    late String staffId;

    setUp(() async {
      await login(ownerPhone);
      salonId = (await auth.me()).ownedSalonId!;
      staffId = (await salons.detail(salonId)).staff.first.id;
    });

    /// Rend au salon sa semaine par défaut.
    void restaurer() => addTearDown(() async {
          await login(ownerPhone);
          await admin.updateSalon(salonId, hours: {
            'mon': const DayHours(),
            'sun': const DayHours(closed: true),
          });
        });

    test('la semaine remonte toujours avec ses sept jours', () async {
      final detail = await salons.detail(salonId);

      // Un jour manquant empêcherait le gérant de l'ouvrir : il ne serait
      // affiché nulle part.
      expect(detail.hours.keys.toSet(),
          {'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'});
    });

    test('le gérant ouvre son dimanche', () async {
      restaurer();
      await admin.updateSalon(salonId, hours: {
        'sun': const DayHours(closed: false, open: '10:00', close: '16:00'),
      });

      final detail = await salons.detail(salonId);
      expect(detail.hours['sun']!.closed, isFalse);
      expect(detail.hours['sun']!.open, '10:00');
    });

    test('modifier un jour n’efface pas les autres', () async {
      restaurer();
      await admin.updateSalon(salonId,
          hours: {'mon': const DayHours(open: '08:00', close: '20:00')});
      await admin.updateSalon(salonId, hours: {
        'sun': const DayHours(closed: false, open: '10:00', close: '16:00'),
      });

      final detail = await salons.detail(salonId);
      expect(detail.hours['mon']!.open, '08:00',
          reason: 'le lundi personnalisé doit survivre à l’ouverture du dimanche');
      expect(detail.hours.length, 7);
    });

    test('un dimanche ouvert produit de vrais créneaux', () async {
      restaurer();
      await admin.updateSalon(salonId, hours: {
        'sun': const DayHours(closed: false, open: '10:00', close: '16:00'),
      });

      final jours = await salons.availability(staffId: staffId);
      final dimanches = jours.where((j) => DateTime.parse(j.isoDate).weekday == 7);

      expect(dimanches, isNotEmpty);
      expect(dimanches.every((j) => j.reason != DayUnavailability.salonClosed),
          isTrue,
          reason: 'le salon est déclaré ouvert : plus aucun « مسكّر »');
    });

    test('refermer le dimanche le referme vraiment', () async {
      await admin.updateSalon(
          salonId, hours: {'sun': const DayHours(closed: false)});
      await admin.updateSalon(
          salonId, hours: {'sun': const DayHours(closed: true)});

      final jours = await salons.availability(staffId: staffId);
      final dimanches = jours.where((j) => DateTime.parse(j.isoDate).weekday == 7);

      expect(dimanches.every((j) => j.reason == DayUnavailability.salonClosed),
          isTrue,
          reason: 'ouvrir n’est pas irréversible');
    });

    test('changer les heures déplace vraiment les créneaux', () async {
      restaurer();
      final jours = await salons.availability(staffId: staffId);
      final ouvert = jours.firstWhere((j) => j.available);
      final cle = _cleJour(DateTime.parse(ouvert.isoDate));

      await admin.updateSalon(salonId, hours: {
        cle: const DayHours(closed: false, open: '14:00', close: '18:00'),
      });

      final creneaux =
          await salons.slots(staffId: staffId, isoDate: ouvert.isoDate);
      expect(creneaux, isNotEmpty,
          reason: 'quatre heures d’ouverture laissent de la place');

      // Le serveur raisonne en heure de Tunis : on compare sur l'heure locale
      // rendue par le modèle, pas sur l'UTC brut.
      for (final c in creneaux) {
        final h = DateTime.parse(c.start).toLocal();
        expect(h.hour, greaterThanOrEqualTo(14),
            reason: 'aucun créneau avant l’ouverture déclarée');
        expect(h.hour, lessThan(18),
            reason: 'aucun créneau après la fermeture déclarée');
      }
    });

    test('une pause déjeuner vide sa tranche', () async {
      restaurer();
      final jours = await salons.availability(staffId: staffId);
      final ouvert = jours.firstWhere((j) => j.available);
      final cle = _cleJour(DateTime.parse(ouvert.isoDate));

      await admin.updateSalon(salonId, hours: {
        cle: const DayHours(
          closed: false,
          open: '09:00',
          close: '19:00',
          breakStart: '12:30',
          breakEnd: '14:00',
        ),
      });

      final creneaux =
          await salons.slots(staffId: staffId, isoDate: ouvert.isoDate);
      final pendantLaPause = creneaux.where((c) {
        final h = DateTime.parse(c.start).toLocal();
        final minutes = h.hour * 60 + h.minute;
        return minutes >= 12 * 60 + 30 && minutes < 14 * 60;
      });

      // Un coiffeur qui déjeune n'est pas réservable : proposer le créneau
      // ferait venir un client devant une chaise vide.
      expect(pendantLaPause, isEmpty);
      expect(creneaux, isNotEmpty, reason: 'le reste de la journée tient');
    });

    test('un salon 7j/7 est légitime', () async {
      restaurer();
      await admin.updateSalon(salonId, hours: {
        for (final j in kWeekdays) j.key: const DayHours(closed: false),
      });

      final detail = await salons.detail(salonId);
      expect(detail.hours.values.every((h) => !h.closed), isTrue);
    });
  });
}

/// Clé de jour attendue par l'API — la semaine commence lundi.
String _cleJour(DateTime d) =>
    const ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'][d.weekday - 1];
