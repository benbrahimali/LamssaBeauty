"""Normalisation des réponses JSON.

Beanie sérialise l'identifiant sous l'alias Mongo `_id`, alors que les schémas
Pydantic de l'API exposent `id`. Sans harmonisation, le client mobile devrait gérer
les deux formes selon l'endpoint. On renomme donc `_id` -> `id` à la sortie —
uniquement au rendu HTTP, jamais à la persistance.
"""
from typing import Any

from fastapi.responses import JSONResponse


def normalize(value: Any) -> Any:
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            if key == "_id" and "id" not in value:
                key = "id"
            result[key] = normalize(item)
        return result
    if isinstance(value, list):
        return [normalize(item) for item in value]
    return value


class LamssaJSONResponse(JSONResponse):
    def render(self, content: Any) -> bytes:
        return super().render(normalize(content))
