# Préparer le lancement de LAMSSA

État vérifié le 14/09/2026, sans modification du code.

**Déjà prêt :** signature Android configurée (`key.properties`), identifiant
`tn.lamssa.app`, version `1.0.0+1`, API en ligne sur
`https://lamssabeauty.onrender.com`, base `lamssa` sur Atlas, rappels J‑1 / H‑2
déclenchés par cron-job.org.

**Ordre conseillé :** 7 → 5 → 6 (sécurité, environ une heure) · 4 (nettoyage) ·
1 → 2 (SMS puis production) · 3 (paiement sur place) · 12 · 13. Le reste peut
suivre le lancement.

---

## 🔴 Bloquants — impossible de lancer sans

### 1. Envoyer de vrais SMS

- [ ] Ouvrir un compte chez un fournisseur SMS (Twilio ou fournisseur tunisien)
- [ ] Renseigner sur Render `SMS_PROVIDER`, `TWILIO_SID`, `TWILIO_TOKEN`, `TWILIO_FROM`
- [ ] Tester la réception d'un code sur un vrai numéro

**Pourquoi :** avec `SMS_PROVIDER=console`, le code OTP s'écrit dans les logs et
n'arrive jamais sur le téléphone. Un vrai client ne peut pas se connecter.

### 2. Passer le serveur en production

- [ ] Sur Render : `ENV=prod`
- [ ] Vérifier que `JWT_SECRET` et `PSP_WEBHOOK_SECRET` ne sont plus des valeurs par défaut
- [ ] Contrôler que la connexion avec `000000` échoue en **401**

**Pourquoi :** `ENV=dev` laisse ouverte la porte `OTP_DEV_CODE`. En production,
le serveur refuse de démarrer tant que le SMS réel (point 1) et les secrets ne
sont pas configurés — c'est voulu.

### 3. Décider du paiement

- [ ] **Lancer en paiement sur place** et masquer le paiement en ligne
- [ ] *Ou* ouvrir un compte marchand Konnect ou Flouci (KYC : prévoir du délai)
      puis renseigner `PSP_PROVIDER`, `KONNECT_API_KEY` ou `FLOUCI_APP_TOKEN`

**Pourquoi :** `PSP_PROVIDER=mock` — le paiement en ligne actuel est factice.

### 4. Retirer les données de démo de la production

- [ ] Décider quels salons garder (Berber King ? Xbfbb ?)
- [ ] Retirer les salons de démonstration : Barbier El Menzah, Rania Beauty
      Lounge, Studio Mariées Carthage
- [ ] Retirer les 20 faux coiffeurs « Chaise walk-in »
- [ ] Retirer les comptes clients fictifs (`+21698000000` à `+21698000004`)
      et leurs rendez-vous

**Pourquoi :** les clients verraient des salons qui n'existent pas et
pourraient y réserver.

---

## 🟠 Sécurité — avant d'ouvrir au public

### 5. Changer le mot de passe MongoDB

- [ ] Atlas → Database Access → créer un utilisateur dédié, par exemple `lamssa_user`
- [ ] Rôle : `readWrite` sur la base `lamssa` **uniquement**
- [ ] Mettre la nouvelle URI dans `MONGO_URI` sur Render
- [ ] **Ensuite seulement**, changer le mot de passe de `benbrahimali_db_user`
      et mettre à jour `chantier_pro`

**Pourquoi :** l'ancien mot de passe est apparu dans les logs Render et dans une
conversation. Un utilisateur dédié cloisonne les deux applications : une fuite
chez l'une n'expose plus l'autre.

### 6. Régénérer le secret Cloudinary

- [ ] Console Cloudinary → Settings → Security → Regenerate API secret
- [ ] Mettre la nouvelle valeur dans `CLOUDINARY_API_SECRET` sur Render et en local

**Pourquoi :** la clé et le secret ont été commités dans `backend/.env.example`.
Ils ont été retirés du fichier, mais restent lisibles dans l'historique GitHub.

### 7. ⚠️ Débrancher le PC de la production

- [x] Dans `backend/.env` local, remettre `MONGO_URI=mongodb://localhost:27017` *(fait le 14/09)*

**Pourquoi :** le `.env` local pointait sur Atlas. Lancer le seed, le smoke test
ou les tests d'intégration depuis le PC **agissait sur la production** — le seed
aurait vidé la base `lamssa` en ligne. Vérifié : le backend local lit désormais
`mongodb://localhost:27017`, aucune variable système ne l'écrase. L'URI de
production reste uniquement sur Render.

⚠️ Ne jamais recopier l'URI Atlas dans le `.env` local.

### 8. Restreindre la clé Google Maps

- [ ] Google Cloud → Credentials → restreindre à l'application Android
- [ ] Package : `tn.lamssa.app`
- [ ] SHA‑1 : `0C:F3:14:CF:9E:A7:6A:3A:AB:E3:F4:C0:59:CB:9B:BF:82:88:0E:52`

---

## 🟡 Fiabilité

### 9. Sauvegarder la base

- [ ] Vérifier dans Atlas si le cluster gratuit M0 propose des sauvegardes
- [ ] Sinon, mettre en place un export régulier :
      `mongodump --uri "<MONGO_URI>" --out sauvegarde-AAAA-MM-JJ`

### 10. Conserver les PDF de clôture

- [ ] Envoyer les rapports de clôture vers un stockage durable (Cloudinary ou autre)

**Pourquoi :** ils sont écrits sur le disque du conteneur Render, effacé à chaque
redéploiement. Ce sont des pièces comptables.

### 11. Surveiller le quota gratuit Render

- [ ] Render → onglet **Usage** : vérifier les heures consommées

**Pourquoi :** l'offre gratuite accorde un quota d'heures par espace de travail.
LAMSSA, gardé éveillé en permanence par le cron, **plus** `chantierbtp-backend`
risquent de le dépasser en fin de mois.

### 12. Savoir quand l'app plante

- [ ] Ajouter Firebase Crashlytics à l'app mobile (gratuit, Firebase déjà branché)
- [ ] Optionnel : Sentry côté backend

**Pourquoi :** aucun suivi d'erreurs aujourd'hui — un plantage chez un client
passe inaperçu.

---

## 🟢 Store et administratif

### 13. Publier sur Google Play

- [ ] Compte développeur Google Play (25 $, paiement unique)
- [ ] Politique de confidentialité sur une **URL publique**
- [ ] Formulaire *Data safety* : téléphone, localisation, photos, selfie Style DNA
- [ ] Classification du contenu
- [ ] Captures d'écran et fiche de l'application
- [ ] Construire l'APK / AAB : `cd mobile && flutter build appbundle --release`

### 14. Données personnelles

- [ ] Se renseigner sur la déclaration auprès de l'**INPDP**
      (téléphones, positions et selfies sont des données personnelles)
- [ ] Rédiger les conditions générales d'utilisation

### 15. Valider les salons des nouveaux gérants

Le gérant qui s'inscrit via « عندي صالون » crée son salon tout de suite et le
prépare (services, équipe, horaires, photos). Le salon reste **invisible** des
clients — ni recherche, ni carte, ni réservation — jusqu'à sa validation.

- [ ] Définir ce qu'on vérifie avant de valider (appel au gérant, adresse, photos)
- [ ] Consulter régulièrement l'onglet **Salons** de la console : les salons
      « à valider » apparaissent en premier
- [ ] Refuser avec une raison claire : elle est envoyée au gérant

**Console :** `https://lamssabeauty.onrender.com/admin` → Salons → Valider / Refuser

---

## ⚪ Qualité — non bloquant

- [ ] **Style DNA** : clés Anthropic et Gemini vides, la fonctionnalité est masquée.
      Lancer sans, ou ajouter du crédit.
- [ ] **Notifications push** : tester de bout en bout sur un vrai téléphone, contre Render
- [ ] **Arabe (RTL)** : relecture visuelle écran par écran
- [ ] **iOS** : non configuré — le lancement sera Android uniquement
- [ ] **Nom de domaine** `lamssa.tn` : optionnel, l'adresse Render fonctionne
- [ ] **Tests d'intégration** : 3 tests portfolio échouent (fenêtre de 14 jours
      sur des données anciennes) ; ne jamais lancer la suite contre la production
