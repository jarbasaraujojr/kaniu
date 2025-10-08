import os
from typing import Any, Dict, List

import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException

load_dotenv()

app = FastAPI()

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise ValueError("DATABASE_URL environment variable not set")

RACA_IDENTIFIER = "\"ra" + chr(0xE7) + "a\""

ANIMALS_QUERY = f"""
    SELECT
        animal_id,
        nome,
        especie,
        sexo,
        {RACA_IDENTIFIER} AS raca,
        porte,
        canil,
        faixa_etaria,
        foto,
        album,
        status
    FROM public.animais_site_publico
    ORDER BY nome;
"""


def _row_to_payload(row: Dict[str, Any]) -> Dict[str, Any]:
    # Convert database column names to response keys expected by the client.
    return {
        "id": str(row["animal_id"]),
        "name": row.get("nome"),
        "species": row.get("especie"),
        "sex": row.get("sexo"),
        "breed": row.get("raca"),
        "size": row.get("porte"),
        "kennel": row.get("canil"),
        "age_range": row.get("faixa_etaria"),
        "picture_url": row.get("foto"),
        "album_url": row.get("album"),
        "status": row.get("status"),
    }


@app.get("/animals")
def get_animals() -> Dict[str, List[Dict[str, Any]]]:
    try:
        with psycopg2.connect(DATABASE_URL) as connection:
            with connection.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute(ANIMALS_QUERY)
                records = cursor.fetchall()
    except psycopg2.Error as exc:
        raise HTTPException(
            status_code=500,
            detail="Failed to query animals from the database.",
        ) from exc

    animals = [_row_to_payload(record) for record in records]
    return {"animals": animals}


@app.get("/")
def read_root() -> Dict[str, str]:
    return {"message": "Welcome to the Animal API!"}
