# LAMSSA — API

FastAPI · MongoDB (Beanie) · Redis · Celery. Préfixe : `/api/v1`.

## Architecture (§4.3)

```
app/
├── api/v1/       routers : auth, salons, staff, bookings, cash, advances,
│                 payments, reviews, portfolio, notifications
├── core/         config, connexions, JWT & rôles, dépendances, helpers date
├── models/       enums du domaine + documents Beanie
├── schemas/      contrats d'entrée/sortie Pydantic
├── services/     logique métier (SplitEngine, disponibilités, caisse, PSP, PDF…)
├── workers/      tâches Celery (rappels, no-shows, clôture)
└── seed.py       jeu de données de démonstration
tests/            suite unitaire, sans infrastructure
```

Principes : **stateless**, injection de dépendances, un service métier par domaine,
verrouillage de créneau via Redis `SETNX` + re-vérification en base.

## Configuration

Tout passe par des variables d'environnement (voir `.env.example`). Les valeurs
sensibles à changer avant la prod :

| Variable | Pourquoi |
|---|---|
| `ENV=prod` | désactive `OTP_DEV_CODE`, le provider `mock` et le renvoi du code OTP |
| `JWT_SECRET` | signature des tokens — `python -c "import secrets;print(secrets.token_urlsafe(48))"` |
| `PSP_PROVIDER` + clés | `konnect` ou `flouci` au lieu de `mock` |
| `PSP_WEBHOOK_SECRET` | signature HMAC des webhooks, vérifiée uniquement en prod |
| `FCM_SERVER_KEY` | sans clé, les push sont seulement écrits dans les logs |
| `SMS_PROVIDER` | `console` en dev, `twilio` (ou provider local) en prod |
| `CORS_ORIGINS` | restreindre — `["*"]` par défaut |
| `ANTHROPIC_API_KEY` | active Style DNA ; sans elle `/style-dna/status` renvoie `available: false` |

## Style DNA

`POST /style-dna/analyze` reçoit un selfie en `multipart/form-data` et renvoie la
forme du visage plus 3 à 5 coupes adaptées. L'analyse est faite par
`claude-opus-5` en vision, avec un JSON Schema imposé (structured outputs) : la
réponse a toujours la même forme, y compris le cas « pas de visage détecté ».

| Réglage | Effet |
|---|---|
| `STYLE_DNA_MODEL` | modèle vision (`claude-opus-5` par défaut) |
| `STYLE_DNA_EFFORT` | `low`…`max` — `medium` garde l'analyse sous ~10 s ; monter pour plus de finesse |
| `STYLE_DNA_MAX_IMAGE_MB` | refuse au-delà, avant tout appel facturé |

Le selfie n'est ni écrit sur disque, ni journalisé, ni rattaché au compte : il
existe le temps de l'appel puis disparaît. Un refus des classifieurs de sécurité
arrive en HTTP 200 avec `stop_reason: "refusal"` — il est détecté et converti en
422 plutôt que de faire planter la lecture de la réponse.

## Authentification

```
POST /api/v1/auth/otp/request  { "phone": "98123456" }
POST /api/v1/auth/otp/verify   { "phone": "98123456", "code": "000000" }
   -> { access_token, refresh_token, user }
POST /api/v1/auth/refresh      { "refresh_token": "…" }   # rotation, usage unique
```

Le refresh est enregistré dans Redis et invalidé à chaque usage : rejouer un ancien
refresh échoue en `401`. Toutes les routes protégées attendent
`Authorization: Bearer <access_token>`.

## Endpoints par rôle

| Rôle | Accès typiques |
|---|---|
| `CLIENT` | `/salons`, `/staff/{id}/slots`, `POST /bookings`, `/payments/checkout`, `/reviews`, `/bookings/me` |
| `STAFF` | `/staff/me/agenda`, `/cash/me`, `/cash/me/balance`, `/advances`, `/portfolio` |
| `OWNER` | `/cash/today`, `/cash/monthly`, `/cash/closures`, `/advances?salon_id=`, `/salons/{id}/staff`, `/salons/{id}/services` |

## Worker

```bash
celery -A app.workers.celery_app.celery_app worker --loglevel=info
celery -A app.workers.celery_app.celery_app beat   --loglevel=info
```

| Tâche | Fréquence | Rôle |
|---|---|---|
| `send_reminders` | 10 min | rappels J-1 (push) et H-2 (push + SMS) |
| `expire_pending` | 5 min | libère les créneaux `PENDING` non payés |
| `mark_no_shows` | 15 min | passe les `CONFIRMED` dépassés en `NO_SHOW` |
| `closure_reminder` | 21 h | relance les gérants qui n'ont pas clôturé |

## Tests

```bash
python -m pytest -q          # 85 tests unitaires — aucune base requise
```

```bash
docker compose up -d mongo redis
python -m tests.smoke_e2e    # 51 assertions bout en bout — MongoDB + Redis requis
```

Le smoke test déroule le parcours réel : onboarding gérant → équipe & catalogue →
recherche géo → créneaux → réservation → paiement en ligne → encaissement avec split →
tséb9a → clôture + rapport PDF → avis → walk-in → rotation du refresh token. Il vérifie
aussi les refus attendus (double réservation, double encaissement, double clôture,
`STAFF` sur `/cash/today`, walk-in par un client). Il travaille sur la base
`lamssa_smoke`, qu'il vide à chaque exécution — jamais sur `lamssa`.
