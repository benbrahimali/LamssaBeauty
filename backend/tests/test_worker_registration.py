"""Enregistrement des tâches Celery (§3.7, §4.2).

Un worker démarré sans ses tâches ne lève aucune erreur : beat publie
« lamssa.send_reminders », le worker la rejette comme inconnue, et plus aucun
rappel ne part — silencieusement. C'est exactement ce qui se passait, et c'est
la seule chose que ces tests protègent.
"""
from app.workers.celery_app import celery_app

#: Ce que `beat_schedule` publie, et qui doit donc exister côté worker.
PLANIFIEES = {
    "lamssa.send_reminders",
    "lamssa.expire_pending",
    "lamssa.mark_no_shows",
    "lamssa.closure_reminder",
}


def _registered() -> set[str]:
    """Force le chargement différé, comme le fait le worker à son démarrage."""
    celery_app.loader.import_default_modules()
    return {n for n in celery_app.tasks if n.startswith("lamssa.")}


def test_le_module_des_taches_est_bien_inclus():
    assert "app.workers.tasks" in celery_app.conf.include


def test_toutes_les_taches_planifiees_existent_cote_worker():
    manquantes = PLANIFIEES - _registered()
    assert not manquantes, f"tâches publiées mais non enregistrées : {manquantes}"


def test_chaque_entree_du_planning_pointe_sur_une_tache_reelle():
    """Une faute de frappe dans `beat_schedule` serait invisible en production."""
    registered = _registered()
    for nom, entree in celery_app.conf.beat_schedule.items():
        assert entree["task"] in registered, f"« {nom} » vise {entree['task']}, absente"


def test_les_rappels_tournent_assez_souvent_pour_un_h_moins_2():
    """Un rappel « 2 h avant » vérifié une fois par heure arriverait en retard."""
    schedule = celery_app.conf.beat_schedule["rappels-rdv"]["schedule"]
    # crontab(minute="*/10") : dix minutes de granularité au pire.
    assert schedule.minute != {0}, "granularité horaire insuffisante pour H-2"
