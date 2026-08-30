# LAMSSA

> Plateforme de réservation & gestion de salons de coiffure et beauté — Tunisie.
> Monorepo : API FastAPI + application mobile Flutter.

Implémentation du cahier des charges `LAMSSA-cahier-des-charges.md` (v1.0).

```text
lamssa/
├── backend/     API FastAPI + MongoDB + Redis + Celery   ← §4.3, §6
├── mobile/      Application Flutter (client + pro)        ← §4.1
└── _archive/    Squelette initial conservé pour référence (non versionné)
```

---

## Démarrage rapide

### Backend

```bash
cd backend
cp .env.example .env
docker compose up -d          # api + worker + beat + mongo + redis
docker compose exec api python -m app.seed    # jeu de données de démo
```

Sans Docker :

```bash
cd backend
python -m venv .venv && .venv/Scripts/activate      # Windows
pip install -r requirements.txt
uvicorn app.main:app --reload
```

- Documentation interactive : <http://localhost:8000/docs>
- Sonde : <http://localhost:8000/health>
- En dev, le code OTP est renvoyé dans la réponse de `/auth/otp/request` et `000000` est
  accepté partout (`OTP_DEV_CODE`, ignoré dès `ENV=prod`).

### Mobile

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # émulateur Android
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000  # téléphone réel
```

Sans `--dart-define`, l'app choisit seule : `10.0.2.2:8000` sur Android (l'hôte vu
depuis l'émulateur), `localhost:8000` ailleurs. En dev, l'écran de connexion
pré-remplit le code OTP renvoyé par l'API et le code `000000` fonctionne toujours.

---

## Couverture du cahier des charges

| § | Module | État | Où |
|---|---|---|---|
| 3.1 | Auth OTP SMS, 3 rôles, onboarding salon | ✅ | `api/v1/auth.py`, `api/v1/salons.py` |
| 3.2 | Recherche géo 2dsphere, fiche salon, profil coiffeur | ✅ | `api/v1/salons.py`, `api/v1/staff.py` |
| 3.3 | Créneaux, multi-services, verrou anti-conflit, walk-in, annulation | ✅ | `services/availability.py`, `services/booking_service.py` |
| 3.4 | Caisse, split configurable, tséb9a, clôture, dépenses, P&L | ✅ | `services/cash_service.py`, `services/split_engine.py`, `api/v1/advances.py` |
| 3.5 | Équipe, chaises, commissions, congés, classement | ✅ | `api/v1/salons.py` |
| 3.6 | Paiement Konnect/Flouci, webhook, remboursement, commission | ✅ | `services/payment_service.py`, `api/v1/payments.py` |
| 3.7 | Push FCM + SMS, historique in-app | ✅ | `services/notification_service.py`, `api/v1/notifications.py` |
| 3.8 | Avis vérifiés, portfolio, fil « En vogue » | ✅ | `api/v1/reviews.py`, `api/v1/portfolio.py` |
| 5.5 | Machine à états du RDV | ✅ | `models/enums.py` (`BOOKING_TRANSITIONS`) |
| 2.4 / 8.5 | Style DNA — analyse du selfie par modèle vision | ✅ | `services/style_dna_service.py`, `api/v1/style_dna.py` |
| 2.4 | Liste d'attente, programme fidélité | ❌ V2 | — |

### Agenda : voir au-delà d'aujourd'hui (§3.3)

Coiffeur et gérant étaient enfermés sur la journée en cours. Un RDV pris pour
demain leur arrivait en notification, puis restait **introuvable dans l'app**
jusqu'au jour même — alors que le client, lui, avait déjà sa confirmation.
Impossible de préparer sa journée.

Les deux agendas se déplacent maintenant d'un jour à l'autre, dans les deux
sens : le passé compte autant, on a souvent besoin de retrouver ce qu'on a
fait hier. Toucher la date revient directement à aujourd'hui plutôt que de
tapoter la flèche autant de fois qu'on s'est éloigné.

Sur la journée courante, aucune date n'est envoyée au serveur : c'est lui qui
décide de ce qu'est « aujourd'hui », en heure de Tunis. Laisser le téléphone
trancher exposerait l'agenda à un fuseau mal réglé.

**« مواعيدي » reste la vue client** — les RDV que *vous* avez pris, jamais
ceux que vous recevez. Elle est donc vide pour un gérant ou un coiffeur qui
n'a rien réservé pour lui-même, et c'est le comportement attendu : leur
planning professionnel vit dans l'agenda, pas là.

### Horaires : c'est le gérant qui décide (§3.1, §3.5)

Le dimanche fermé n'est **qu'un défaut de création**, jamais une règle : des
salons ouvrent 7j/7, et ils doivent pouvoir le déclarer. L'onglet
« الأوقات » de la gestion du salon donne les sept jours, chacun avec son
interrupteur ouvert/fermé, ses heures et sa pause facultative.

Le PATCH des horaires **fusionne** au lieu de remplacer. Envoyer le seul
dimanche remplaçait auparavant tout le dictionnaire : les six autres jours
disparaissaient et retombaient en silence sur les valeurs par défaut — un
gérant qui ouvrait son dimanche perdait ses horaires du lundi sans le voir.
L'app n'envoie donc que le jour modifié, et le serveur garde le reste.

Trois garde-fous côté saisie, parce que le serveur les refuserait de toute
façon et qu'un message clair vaut mieux qu'une erreur : le format `HH:MM` sur
24 heures, la fermeture après l'ouverture (une journée vide ne produirait
aucun créneau), et la pause déclarée des deux côtés ou pas du tout — une borne
seule ne veut rien dire.

Ces horaires se combinent avec le repos hebdomadaire du coiffeur ci-dessous :
le salon dit quand il ouvre, le coiffeur quand il travaille.

### Calendrier : le jour de repos du coiffeur (§3.3, §3.5)

Le salon ouvre six jours sur sept ; le coiffeur, lui, se repose le lundi. Les
horaires du salon ne suffisaient donc pas : les créneaux du lundi restaient
réservables et le client se déplaçait pour rien.

Chaque coiffeur déclare ses **jours de repos hebdomadaires** (`days_off`),
distincts des horaires du salon et des congés ponctuels (`TimeOff`, déjà
gérés). Une clé de jour inconnue est refusée en 422 plutôt qu'ignorée : un
« lundi » écrit en toutes lettres ne bloquerait rien, et personne ne s'en
apercevrait avant qu'un client se présente devant une chaise vide.

`GET /staff/{id}/availability` rend les quatorze jours d'un coup, chacun avec
son **motif** d'indisponibilité. L'ordre des motifs n'est pas décoratif :

```
salon fermé  →  coiffeur suspendu  →  jour de repos  →  complet
```

Un salon fermé explique déjà l'absence de créneaux ; annoncer « complet » ce
jour-là enverrait le client réessayer demain alors que le problème est
ailleurs. Et surtout, **« complet » et « en repos » n'appellent pas la même
réaction** : le premier invite à revenir un autre jour, le second à changer de
coiffeur. Les confondre faisait tourner le client en rond.

Le calendrier grise donc les jours fermés **avant** qu'on les touche, avec
l'étiquette du motif (`راحة`, `كامل`, `مسكّر`), et le tunnel s'ouvre sur le
premier jour réellement travaillé — sans quoi il affichait « complet » avant
même que le client ait choisi quoi que ce soit.

Si l'appel échoue, le calendrier reste entièrement ouvert : c'est un confort
perdu, pas une réservation perdue.

### Salons proches : la position réelle (§3.2)

La section « قريب منك » de l'accueil ne demandait jamais la position — les
salons arrivaient dans l'ordre du serveur, pas par proximité. Seul l'écran
Carte savait se localiser.

L'accueil tente désormais une localisation **silencieuse** à l'ouverture :
silencieuse au sens strict, elle n'ouvre aucune boîte de permission et
n'affiche aucune erreur. Une permission demandée sans geste de l'utilisateur
se fait refuser par réflexe, et un refus définitif ne se rattrape plus. Tant
qu'on n'a pas de position, l'écran affiche une invite discrète que
l'utilisateur peut toucher ; c'est seulement là que la demande système part.

### Gestion financière du gérant (§3.4)

La caisse dit ce qui est entré ; le compte de résultat dit ce qu'il reste. Un
salon peut encaisser 3 000 DT dans le mois et perdre de l'argent une fois le
loyer payé — c'est ce que `GET /cash/pnl` rend visible :

```
chiffre d'affaires  −  part de l'équipe  =  marge brute
marge brute  −  dépenses ponctuelles  −  charges fixes  =  résultat
```

Chaque salon décrit **ses propres charges** (`RecurringCharge`) avec ses
libellés, ses catégories et son rythme — hebdomadaire, mensuel, annuel. Rien
n'est imposé : un salon qui paie un loyer et une patente ne tient pas les mêmes
comptes qu'un salon avec trois salariés fixes.

Les charges sont ramenées au **coût journalier** puis comptées au prorata de la
période. Sans ça, la semaine où tombe le loyer paraîtrait catastrophique et les
trois autres, excellentes — le gérant ne pourrait comparer ses semaines. Le mois
moyen vaut 365,25/12 jours et non 30 : l'écart représenterait six jours de
charges par an, soit 180 DT sur un loyer de 900.

Les **pourboires sont exclus du résultat**. Ils transitent par la caisse quand le
client paie par carte, mais appartiennent à l'employé : les compter en revenu
gonflerait le résultat du salon. Ils restent affichés à part.

Une charge se **désactive**, elle ne se supprime pas : les mois déjà analysés
gardent des comptes justes.

### Pilotage : seuil de rentabilité et objectif (§3.4)

Un résultat seul ne dit pas s'il est bon. `GET /cash/pilot` ajoute les deux
repères qui lui donnent un sens.

Le **seuil de rentabilité** dépend de ce que le salon reverse à son équipe :

```
seuil = (charges fixes + dépenses du mois) / (1 − part reversée)
```

Les dépenses ponctuelles comptent autant que le loyer : un séchoir acheté ce
mois-ci doit être couvert lui aussi. Ne retenir que les charges récurrentes
annoncerait un seuil déjà franchi alors qu'il ne l'est pas.

À 50 % de commission, chaque dinar encaissé n'en laisse que 50 centimes pour
couvrir le loyer : il faut donc encaisser **le double** des charges. Un salon
qui emploie des salariés atteint son seuil bien plus tôt. C'est pourquoi aucun
seuil universel n'aurait de sens — et c'est le calcul que les gérants font de
tête, souvent faux.

Deux cas rendent le seuil inexistant, et l'app le dit plutôt que d'afficher un
chiffre trompeur : aucune charge — le salon gagne dès la première coupe — ou
100 % reversé à l'équipe, où aucun volume ne couvrirait quoi que ce soit.

L'**objectif** est facultatif et fixé par le gérant : on n'en invente pas à sa
place, il n'y aurait aucune raison de le croire. Il est jugé **au prorata du
temps écoulé** — comparer le réalisé à l'objectif entier afficherait « en
retard » tout le mois. La projection reste muette sous un jour de recul : une
grosse matinée annoncerait un mois record.

### Règles de rémunération (§3.4)

Deux salons voisins ne paient pas leur équipe de la même façon, et aucun des
deux n'a tort. L'app applique donc **la règle du salon**, pas une règle
Lamssa. Trois réglages suffisent à couvrir ce qui se pratique réellement.

**Le taux** se résout par ordre de précision, du plus spécifique au plus
général :

```
commission du service  →  commission du coiffeur  →  split par défaut du salon
```

Le taux du service existe parce qu'une coloration et une coupe ne se
rémunèrent presque jamais pareil : le gérant peut donner 35 % sur l'une et
50 % sur l'autre sans toucher aux contrats. Laissé vide, il s'efface et le
taux du coiffeur reprend la main.

**Le coût produit** est retenu par le salon *avant* le partage. C'est le point
qui fâche quand il est mal fait : une couleur à 60 DT dont 15 DT de produit
partagée à 35 % donne 15,75 DT au coiffeur, pas 21 DT — le salon ne peut pas
reverser une part du tube de teinture. Le détail du calcul remonte dans la
réponse d'encaissement (`product_cost`, `salon_tip`) pour que l'employé
comprenne son chiffre au lieu de le subir.

**Le pourboire** suit une politique de salon (`tip_staff_pct`) : 100 % au
coiffeur par défaut, mais un salon qui met les pourboires en commun règle 50 %
et la part du salon rejoint sa marge. Un pourboire n'est jamais soumis à la
commission — c'est un don au geste, pas un chiffre d'affaires.

Vérifié en conditions réelles : couleur 60 DT, commission 35 %, produit 15 DT,
pourboire 10 DT → **coiffeur 15,75 + 10 de pourboire, salon 44,25**.

### Trésorerie : ce qu'il y a vraiment dans le tiroir (§3.4)

La caisse du jour dit ce qui a été **encaissé**. La trésorerie dit ce qui est
**physiquement dans le tiroir**. Les deux divergent dès la première carte
bancaire, et c'est cet écart qu'aucun gérant ne suit correctement de tête.

```
solde attendu = fond de caisse
              + encaissements espèces (prestation + pourboire)
              + apports
              − dépenses réglées en espèces
              − tséb9as versées en espèces
              − prélèvements
```

Trois séparations font tout le travail :

- **Espèces et banque ne se mélangent pas.** Un règlement par TPE ou en ligne
  part à la banque sans jamais passer par le tiroir. Les confondre est la
  première cause d'écart inexpliqué : le gérant cherche 800 DT qui n'ont
  jamais existé en billets.
- **Chaque dépense déclare sa source** (`paid_from`). Un loyer viré depuis le
  compte ne vide pas le tiroir ; des produits payés au comptoir, si. Sans
  cette distinction le solde théorique dérive dès le premier mois.
- **Une tséb9a sort du tiroir le jour où elle est accordée**, pas le jour où
  elle est demandée ni celui de la paie.

**Le comptage du soir reste facultatif.** Beaucoup de gérants ferment sans
compter ; les y obliger ferait saisir n'importe quel chiffre. Tant que
`counted_cash` est absent, aucun écart n'est affiché — un écart de zéro
inventé vaudrait moins que pas d'écart du tout. Quand le comptage a lieu,
c'est **lui** qui fait foi : l'écart est enregistré tel quel plutôt que
corrigé en silence, avec son motif, et c'est le montant compté — non le
théorique — qui devient le fond de caisse du lendemain, une fois le
prélèvement du soir retiré.

Le solde peut devenir négatif, et l'app l'affiche en rouge au lieu de le
ramener à zéro : des sorties sans fond de caisse sont une anomalie réelle que
le gérant doit voir. Une journée clôturée est arrêtée — plus aucun mouvement
ne s'y ajoute, sinon le rapport déjà signé deviendrait faux.

`GET /cash/treasury` rend le détail ligne par ligne ; `POST /cash/movements`
enregistre fond de caisse, apport et prélèvement. Le solde du tiroir n'est
jamais visible par l'équipe : c'est une information de gérant.

### Ville et adresse remplies depuis la position (§3.1)

« موقعي الحالي » ne posait que des coordonnées : ville et adresse restaient
vides et le gérant retapait ce que le téléphone savait déjà. Le sélecteur de
carte, lui, faisait un géocodage inverse mais fondait tout en une seule
chaîne — « Av. Habib Bourguiba, Menzah, Tunis » dans le champ adresse, et rien
dans le champ ville.

Un seul géocodeur sert maintenant les deux chemins, et il rend **la rue et la
ville séparément**, comme le formulaire les demande. Deux rendus différents
pour le même point donneraient l'impression que l'un des deux se trompe.

La règle est de **compléter, jamais d'écraser** : seuls les champs laissés
vides sont remplis. Le gérant connaît son quartier mieux qu'un géocodeur —
« Menzah 6 » vaut mieux que « Ariana » même quand le géocodeur préfère le
second. Et un géocodeur muet n'empêche pas de créer un salon : l'adresse
revient vide, le gérant saisit à la main.

### Position du salon : fraîche plutôt que précise (§3.1)

Un point GPS met parfois plus de quinze secondes à venir en intérieur — et
c'est justement là que se tient un gérant qui crée son salon. L'app se
rabattait alors **en silence** sur la dernière position connue de l'appareil,
qui peut dater d'hier et d'un autre quartier.

Passable pour trier des salons par distance ; inacceptable pour figer
l'adresse d'un salon, que le gérant n'aurait aucun moyen de vérifier sur des
coordonnées brutes. La chaîne dégrade donc par étapes, en préférant toujours
une mesure **fraîche** à une mesure précise mais périmée :

```
haute précision (12 s)  →  précision moyenne (6 s)  →  dernier point connu
```

Un point à cent mètres près obtenu maintenant vaut mieux que la position
d'hier. Et quand le repli est atteint, il est **signalé** : la création
affiche « الموقع تقريبي », garde le liseré doré au lieu du vert, et invite à
poser le point sur la carte — où il redevient exact.

### La carte « قريب منك » (§3.2)

C'est le premier contact d'un client avec un salon, et longtemps le plus
maltraité : le bloc visuel n'imposait aucune largeur, donc dans un `Column`
non étiré il se réduisait à la largeur du monogramme — **96 px au milieu d'une
carte de 240**, une bande étroite au lieu d'une vitrine.

La vitrine occupe désormais toute la carte, avec un voile dégradé en bas pour
que le badge et le prix restent lisibles sur une photo claire sans assombrir
l'image entière. Le prix passe sur la vitrine plutôt que sous le nom : la
carte gagne une ligne, et le chiffre se voit mieux.

Un salon sans avis affichait **« 0.0 ★ »**, ce qui se lit comme une mauvaise
note alors qu'il vient d'ouvrir — personne ne cliquerait. Il porte maintenant
la mention « جديد », et la note n'apparaît qu'à partir du premier avis, avec
son nombre d'avis.

**La photo se choisit dès la création du salon.** Le salon n'existe pas encore
au moment du choix : le fichier est gardé, puis envoyé une fois l'identifiant
obtenu. Un échec d'envoi n'emporte pas la création — le salon existe, il lui
manque sa vitrine, et le gérant l'ajoute depuis la gestion.

### Médias : Cloudinary, photos et reels (§3.2, §3.8)

Photos de salon et **reels vidéo** passent par Cloudinary quand ses clés sont
présentes — devant S3 et le disque local, parce qu'il redimensionne et sait
dériver la vignette d'une vidéo. Les requêtes sont **signées côté serveur** : un
`upload_preset` non signé embarqué dans l'app laisserait n'importe qui déposer
ce qu'il veut sur le compte, et la facturation suit le volume.

Un reel est publié par un coiffeur ou par le salon, et le fil est **public** —
un visiteur sans compte doit pouvoir regarder, sinon les reels n'attirent
personne. La durée est plafonnée à `REEL_MAX_SECONDS` (90 s) et vérifiée sur la
**mesure de Cloudinary**, jamais sur une valeur déclarée par le client. Une
vidéo refusée est supprimée du fournisseur : sinon on paierait le stockage d'un
média que personne ne verra.

Sans clés Cloudinary, les médias retombent sur `./media` et l'API les sert
elle-même : le développement ne dépend d'aucun compte externe.

### Partage par QR (§3.2, §8.3)

Chaque salon a un **code public court** (`BARBIE GV28`) que le gérant imprime en
QR pour sa vitrine ou envoie sur WhatsApp — l'app partage le QR **en image**,
pas seulement un lien. Le client arrive sur la fiche : services, prix, équipe,
prise de RDV.

Le code est lu par des caméras mais aussi par des humains. Le suffixe aléatoire
exclut donc `0/O` et `1/I/L`, et le préfixe reprend le nom du salon pour rester
reconnaissable une fois collé dans une conversation. La saisie manuelle tolère
casse, espaces et tirets — `GET /salons/code/{code}` est **public**, comme la
fiche salon, sinon un QR n'aurait aucun intérêt.

L'unicité vient d'un index Mongo `partial` sur `public_code`, pas d'un
`find_one` préalable : deux créations simultanées passeraient toutes deux la
vérification. `public_code.assign()` réessaie sur collision.

Le QR encode `PUBLIC_WEB_BASE/s/{code}` — une URL https, ouvrable par n'importe
quel appareil photo. **Tant qu'aucun domaine n'est publié, un client sans l'app
tombe sur une page inexistante** : c'est le seul maillon du partage qui dépend
d'une infra externe.

### Notifications push

Le §3.7 classe les push en *Must*. L'implémentation utilise **FCM HTTP v1** :
l'API legacy (`POST /fcm/send` avec `Authorization: key=…`) a été fermée par
Google le **22/07/2024** et aucune « server key » n'est plus délivrée. On
s'authentifie donc avec le **compte de service** du projet Firebase, dont
l'assertion JWT RS256 est échangée contre un jeton OAuth2 mis en cache
(`services/fcm.py`).

L'API v1 n'accepte qu'un destinataire par requête — il n'y a pas d'équivalent
REST à `registration_ids` — donc les envois sont parallélisés, et les tokens que
FCM déclare définitivement morts (`UNREGISTERED`, `SENDER_ID_MISMATCH`) sont
retirés du compte. Une panne passagère (`UNAVAILABLE`) ne purge rien : sinon un
incident FCM rendrait les utilisateurs injoignables pour de bon.

Deux fichiers, jamais versionnés (voir `.gitignore`) :

| Fichier | Rôle |
|---|---|
| `mobile/android/app/google-services.json` | identifie l'app Android ; son `package_name` doit être identique à `applicationId` (`tn.lamssa.app`) |
| `backend/secrets/firebase-admin.json` | compte de service ; permet d'envoyer une notification à **tout** utilisateur — ne quitte jamais le serveur |

Sans `FCM_CREDENTIALS_FILE`, les push sont loggés en console et le reste de
l'API fonctionne à l'identique.

### Style DNA

Le selfie est analysé par **Claude Opus 5** (`claude-opus-5`, vision), appelé
**depuis le backend** : une clé d'API embarquée dans l'APK serait extractible en
quelques minutes. L'image transite en mémoire, n'est ni écrite sur disque ni
journalisée — l'écran promet « الصورة ما تتحفظش » et le code tient la promesse.

La réponse est contrainte par un JSON Schema (structured outputs), donc l'app
reçoit toujours la même forme : forme du visage, confiance, analyse en arabe
tunisien, 3 à 5 coupes classées, et ce qu'il faut éviter. Le modèle peut
répondre « pas de visage détecté » — l'écran l'affiche alors tel quel au lieu
d'inventer un résultat.

Sans `ANTHROPIC_API_KEY`, `GET /style-dna/status` renvoie `available: false` et
l'accueil masque la carte : le reste de l'app fonctionne à l'identique.

### Règles métier appliquées

- **Cloisonnement des rôles** : un `STAFF` sur `/cash/today` reçoit `403` ; sur
  `/cash/me` il ne voit que ses propres transactions. Un `OWNER` n'accède qu'à ses salons.
- **Split** : la commission appliquée est toujours celle du coiffeur qui a *exécuté* le
  RDV, même si le gérant encaisse depuis son téléphone. Le pourboire ne rentre jamais
  dans le split (100 % employé).
- **Anti-double-réservation** : verrou Redis `SETNX` (TTL 30 s) + re-vérification du
  chevauchement en base à l'intérieur du verrou. Un conflit renvoie `409` avec des
  créneaux alternatifs.
- **Clôture** : idempotente (index unique `salon_id + day`), verrouille les transactions
  du jour, déduit les tséb9as approuvées et les passe en `settled`.
- **Fuseau** : tout est stocké en UTC, tout le raisonnement métier se fait en heure locale
  `Africa/Tunis` — la « caisse du jour » ne dérive donc pas à minuit.

---

## Tests

```bash
cd backend
python -m pytest -q          # 249 tests unitaires, sans MongoDB ni Redis
python -m tests.smoke_e2e    # 51 assertions bout en bout (mongo + redis requis)

cd ../mobile
flutter analyze                                  # 0 issue
flutter test --exclude-tags integration          # 77 tests unitaires
flutter test --tags integration \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000   # 48 tests contre l'API réelle
```

Le cœur métier (split, créneaux, transitions, agrégation de caisse, normalisation
téléphone) est écrit en fonctions pures : la suite unitaire tourne hors infrastructure,
donc en CI sans conteneurs. Le smoke test, lui, déroule le parcours complet
réservation → paiement → encaissement → tséb9a → clôture → avis contre de vraies bases.
Côté mobile, les tests d'intégration valident ce que l'analyse statique ne voit pas :
que le JSON réel de FastAPI se désérialise bien dans les modèles de l'app.

---

## Architecture mobile

```text
mobile/lib/
├── core/          env, client HTTP (JWT + refresh transparent), erreurs, stockage tokens
├── data/
│   ├── models.dart      modèles + désérialisation du JSON de l'API
│   └── repositories/    auth, salons, bookings, cash, notifications
├── state/         contrôleurs Provider (auth, salons, booking, cash, notifications)
├── screens/       écrans, alimentés uniquement par les contrôleurs
└── widgets/       design system + états async (chargement / erreur / vide)
```

Aucune donnée n'est simulée : `mock_data.dart` a été supprimé. Chaque écran affiche un
état de chargement, une erreur réessayable ou un état vide explicite.

L'app couvre les trois rôles de bout en bout : le client cherche, réserve, suit et
annule ses RDV puis dépose un avis ; le coiffeur consulte son agenda, sa caisse et
demande une tséb9a ; le gérant ouvre son salon depuis le téléphone
(`create_salon_screen.dart`), saisit son catalogue et son équipe
(`manage_salon_screen.dart`), encaisse, saisit un walk-in et clôture sa journée.
La création d'un salon promeut le compte en `OWNER` côté serveur — l'app rafraîchit
donc son contexte d'authentification juste après.

## Reste à faire

Toutes les fonctionnalités du cahier des charges prévues pour la V1 sont
implémentées et testées. Ce qui suit ne dépend plus du code.

### Ce qui dépend de comptes externes

1. **Domaine `lamssa.tn`** — le QR encode `PUBLIC_WEB_BASE/s/{code}`. Un client
   qui n'a pas l'app tombe pour l'instant sur une page inexistante. Acheter le
   domaine et y servir une page de repli (fiche salon + lien de téléchargement)
   est ce qui rend le partage viral.
2. **Clés PSP réelles** — `PSP_PROVIDER=mock` par défaut ; passer à `konnect`
   ou `flouci` et vérifier le format des webhooks en préprod.
3. **`ANTHROPIC_API_KEY`** — Style DNA n'a jamais tourné contre le modèle réel,
   faute de clé sur la machine de développement. Le reste de l'app fonctionne
   sans, la carte est simplement masquée.
4. **`GEMINI_API_KEY`** — même chose pour l'illustration de coupe et l'essayage.
   La logique (consentement, cache, extraction de l'image) est testée, mais
   aucun appel n'a été passé au fournisseur.
5. **APNs** — le push iOS demande un compte Apple Developer payant. Android est
   opérationnel.

### Vérifications qu'aucun test ne remplace

6. **Push sur un vrai téléphone** — la chaîne FCM v1 est validée jusqu'aux
   serveurs Google (jeton OAuth2 obtenu, token mort correctement purgé), mais
   aucune notification n'a encore été reçue sur un appareil.
7. **Relecture visuelle en RTL** — l'interface est passée en base droite-à-gauche
   (elle était rendue en LTR alors qu'elle est rédigée en arabe tunisien). Les
   écrans construits avant ce changement méritent un coup d'œil sur téléphone :
   `flutter analyze` ne voit pas un alignement inversé.

### V2 (§2.4)

8. **Liste d'attente** et **programme de fidélité** — explicitement hors V1 dans
   le cahier des charges.
