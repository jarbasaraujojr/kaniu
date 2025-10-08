

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."get_prescricao_horarios"("p_dia" "date") RETURNS TABLE("id" bigint, "realizacao" timestamp without time zone, "prescricao" bigint, "pessoa" "uuid", "concluida" boolean, "observacao" "text", "dia" "date", "hora" time without time zone, "tratador" "text")
    LANGUAGE "sql" STABLE
    AS $$
  SELECT id, realizacao, prescricao, pessoa, concluida, observacao, dia, hora, tratador
  FROM public.prescricao_tarefa
  WHERE dia = p_dia
  ORDER BY hora;
$$;


ALTER FUNCTION "public"."get_prescricao_horarios"("p_dia" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_prescricoes_ativas"("p_data" "date") RETURNS TABLE("id" bigint, "receita" bigint, "inicio" "date", "animal" "uuid", "veterinario" "uuid", "medicamento" bigint, "continuo" boolean, "intervalo_horas" smallint, "duracao_dias" smallint, "dose" "text", "dosagem" "text", "via" "text", "descricao" "text", "finalizada" boolean, "veterinario_nome" "text", "medicamento_nome" "text", "animal_nome" "text", "inicio_horario" time without time zone, "termino" "date", "terminada" boolean, "horario_texto" "text", "tarefas" bigint, "canil" bigint)
    LANGUAGE "sql" STABLE
    AS $$
  SELECT pv.id,
         pv.receita,
         pv.inicio,
         pv.animal,
         pv.veterinario,
         pv.medicamento,
         pv.continuo,
         pv.intervalo_horas,
         pv.duracao_dias,
         pv.dose,
         pv.dosagem,
         pv.via,
         pv.descricao,
         pv.finalizada,
         pv.veterinario_nome,
         pv.medicamento_nome,
         pv.animal_nome,
         pv.inicio_horario,
         pv.termino,
         pv.terminada,
         pv.horario_texto,
         pv.tarefas,
         pv.canil
  FROM public.prescricao_view pv
  WHERE p_data > pv.inicio
    AND p_data < pv.termino
    AND COALESCE(pv.terminada, false) = false;
$$;


ALTER FUNCTION "public"."get_prescricoes_ativas"("p_data" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."hybrid_search"("query_text" "text", "query_embedding" "public"."vector", "match_count" integer, "full_text_weight" double precision DEFAULT 1, "semantic_weight" double precision DEFAULT 1, "rrf_k" integer DEFAULT 50) RETURNS TABLE("id" bigint, "content" "text", "metadata" "jsonb", "full_text_rank" real, "semantic_rank" real, "combined_rank" real)
    LANGUAGE "sql"
    AS $$
WITH full_text AS (
  SELECT
    id,
    ts_rank_cd(fts, websearch_to_tsquery(query_text)) AS full_text_rank,
    row_number() OVER (ORDER BY ts_rank_cd(fts, websearch_to_tsquery(query_text)) DESC) AS rank_ix
  FROM
    documents
  WHERE
    fts @@ websearch_to_tsquery(query_text)
  ORDER BY rank_ix
  LIMIT least(match_count, 30) * 2
),
semantic AS (
  SELECT
    id,
    -(embedding <#> query_embedding) AS semantic_similarity,
    row_number() OVER (ORDER BY -(embedding <#> query_embedding)) AS rank_ix
  FROM
    documents
  ORDER BY rank_ix
  LIMIT least(match_count, 30) * 2
)
SELECT
  documents.id,
  documents.content,
  documents.metadata,
  COALESCE(full_text.full_text_rank, 0) AS full_text_rank,
  COALESCE(semantic.semantic_similarity, 0) AS semantic_rank,
  COALESCE(1.0 / (rrf_k + full_text.rank_ix), 0.0) * full_text_weight +
  COALESCE(1.0 / (rrf_k + semantic.rank_ix), 0.0) * semantic_weight AS combined_rank
FROM
  full_text
  FULL OUTER JOIN semantic ON full_text.id = semantic.id
  JOIN documents ON COALESCE(full_text.id, semantic.id) = documents.id
ORDER BY
  combined_rank DESC
LIMIT
  least(match_count, 30)
$$;


ALTER FUNCTION "public"."hybrid_search"("query_text" "text", "query_embedding" "public"."vector", "match_count" integer, "full_text_weight" double precision, "semantic_weight" double precision, "rrf_k" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) RETURNS TABLE("id" bigint, "content" "text", "similarity" double precision)
    LANGUAGE "sql" STABLE
    AS $$
  select
    _n8n_documents.id,
    _n8n_documents.content,
    1 - (_n8n_documents.embedding <=> query_embedding) as similarity
  from _n8n_documents
  where _n8n_documents.embedding <=> query_embedding < 1 - match_threshold
  order by _n8n_documents.embedding <=> query_embedding
  limit match_count;
$$;


ALTER FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_count" integer DEFAULT NULL::integer, "filter" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("id" bigint, "content" "text", "metadata" "jsonb", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (_documents.embedding <=> query_embedding) as similarity
  from _documents
  where metadata @> filter
  order by _documents.embedding <=> query_embedding
  limit match_count;
end;
$$;


ALTER FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_count" integer, "filter" "jsonb") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."animais" (
    "animal_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "criado" timestamp with time zone DEFAULT "now"() NOT NULL,
    "nome" "text" DEFAULT ''::"text" NOT NULL,
    "nascimento" "date" DEFAULT "now"(),
    "genero" "text" DEFAULT ''::"text",
    "raça" "text" DEFAULT ''::"text",
    "especie" "text" DEFAULT ''::"text",
    "cor" "text" DEFAULT ''::"text",
    "pelagem" "text" DEFAULT ''::"text",
    "falecido" boolean DEFAULT false,
    "foto" "text" DEFAULT ''::"text",
    "castrado" boolean DEFAULT false,
    "desaparecido" boolean DEFAULT false,
    "vacinado" boolean DEFAULT false,
    "vermifugado" boolean DEFAULT false,
    "desparasitado" boolean DEFAULT false,
    "peso" real DEFAULT '0'::real,
    "porte" "text" DEFAULT ''::"text",
    "torax" integer DEFAULT 0,
    "comprimento" integer DEFAULT 0,
    "pescoço" integer DEFAULT 0,
    "altura" integer DEFAULT 0,
    "faixaetaria" "text" DEFAULT ''::"text",
    "canil" bigint,
    "adotado" boolean DEFAULT false,
    "diagnosticos" integer[],
    "internado" boolean DEFAULT false,
    "disponivel" boolean DEFAULT false,
    "idx" bigint NOT NULL,
    "album" "text"
);


ALTER TABLE "public"."animais" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."canis" (
    "id" bigint NOT NULL,
    "canil" "text",
    "proprietario" "uuid",
    "excluido" boolean DEFAULT false,
    "aceita_inscricoes" boolean,
    "logotipo_url" "text"
);


ALTER TABLE "public"."canis" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."_n8n_animais" WITH ("security_invoker"='on') AS
 SELECT "a"."animal_id",
    "a"."nome",
    "c"."id" AS "canil_id",
    "c"."canil" AS "canil_nome"
   FROM ("public"."animais" "a"
     JOIN "public"."canis" "c" ON (("a"."canil" = "c"."id")));


ALTER TABLE "public"."_n8n_animais" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."animais_descricao" (
    "animal" "uuid" NOT NULL,
    "descricao" "text",
    "id" integer NOT NULL
);


ALTER TABLE "public"."animais_descricao" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pesagens" (
    "id" bigint NOT NULL,
    "animal" "uuid" NOT NULL,
    "data" "date" NOT NULL,
    "peso" real NOT NULL
);


ALTER TABLE "public"."pesagens" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animais_detalhes" AS
 SELECT "animais"."animal_id",
    "animais"."canil",
    "animais"."nome",
    "animais"."nascimento",
    "animais"."genero",
    "animais"."raça",
    "animais"."especie",
    "animais"."cor",
    "animais"."pelagem",
    "animais"."porte",
    "animais"."comprimento",
    "animais"."altura",
    EXTRACT(year FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) AS "idade_anos",
    EXTRACT(month FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) AS "idade_meses",
        CASE
            WHEN (EXTRACT(year FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) > (8)::numeric) THEN 'Idoso'::"text"
            WHEN (EXTRACT(year FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) > (2)::numeric) THEN 'Adulto'::"text"
            WHEN (EXTRACT(year FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) > (1)::numeric) THEN 'Jovem'::"text"
            ELSE 'Filhote'::"text"
        END AS "faixa_etaria",
    ( SELECT "pesagens"."peso"
           FROM "public"."pesagens"
          WHERE ("pesagens"."animal" = "animais"."animal_id")
          ORDER BY "pesagens"."data" DESC
         LIMIT 1) AS "peso",
    "animais"."foto",
    "animais"."album",
    "animais_descricao"."descricao",
    "animais"."castrado",
    "animais"."adotado",
    "animais"."vacinado",
    "animais"."vermifugado",
    "animais"."desparasitado",
    "animais"."desaparecido",
    "animais"."disponivel",
    "animais"."internado",
    "animais"."falecido"
   FROM ("public"."animais"
     LEFT JOIN "public"."animais_descricao" ON (("animais"."animal_id" = "animais_descricao"."animal")));


ALTER TABLE "public"."animais_detalhes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."especies" (
    "especie" "text" NOT NULL,
    "indice" smallint,
    "canil_id" bigint
);


ALTER TABLE "public"."especies" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animal_status" WITH ("security_invoker"='true') AS
 SELECT "animais"."animal_id" AS "id",
    "animais"."nome",
    "especies"."especie",
        CASE
            WHEN ("animais"."falecido" = true) THEN 'Falecido'::"text"
            WHEN ("animais"."desaparecido" = true) THEN 'Desaparecido'::"text"
            WHEN ("animais"."adotado" = true) THEN 'Adotado'::"text"
            WHEN ("animais"."internado" = true) THEN 'Internado'::"text"
            ELSE 'Abrigado'::"text"
        END AS "status",
    "animais"."canil"
   FROM ("public"."animais"
     LEFT JOIN "public"."especies" ON (("especies"."especie" = "animais"."especie")));


ALTER TABLE "public"."animal_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."_n8n_animais_dados" AS
 SELECT "animais_detalhes"."animal_id",
    "animais_detalhes"."canil",
    "animais_detalhes"."nome",
    "animais_detalhes"."nascimento",
    "animais_detalhes"."genero" AS "sexo",
    "animais_detalhes"."raça",
    "animais_detalhes"."especie",
    "animais_detalhes"."cor",
    "animais_detalhes"."pelagem",
    "animais_detalhes"."porte",
    "animais_detalhes"."comprimento",
    "animais_detalhes"."altura",
    "animais_detalhes"."idade_anos",
    "animais_detalhes"."idade_meses",
    "animais_detalhes"."faixa_etaria",
    "animais_detalhes"."peso",
    "animais_detalhes"."foto",
    "animais_detalhes"."album",
    "animais_detalhes"."descricao",
    "animais_detalhes"."castrado",
    "animais_detalhes"."adotado",
    "animais_detalhes"."vacinado",
    "animais_detalhes"."vermifugado",
    "animais_detalhes"."desparasitado",
    "animais_detalhes"."desaparecido",
    "animais_detalhes"."disponivel",
    "animais_detalhes"."internado",
    "animais_detalhes"."falecido",
    "animal_status"."status"
   FROM ("public"."animais_detalhes"
     LEFT JOIN "public"."animal_status" ON (("animais_detalhes"."animal_id" = "animal_status"."id")));


ALTER TABLE "public"."_n8n_animais_dados" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."_n8n_animais_site" AS
 SELECT "animais_detalhes"."animal_id",
    "animais_detalhes"."canil",
    "animais_detalhes"."nome",
    "animais_detalhes"."nascimento",
    "animais_detalhes"."genero" AS "sexo",
    "animais_detalhes"."raça",
    "animais_detalhes"."especie",
    "animais_detalhes"."cor",
    "animais_detalhes"."pelagem",
    "animais_detalhes"."porte",
    "animais_detalhes"."comprimento",
    "animais_detalhes"."altura",
    "animais_detalhes"."idade_anos",
    "animais_detalhes"."idade_meses",
    "animais_detalhes"."faixa_etaria",
    "animais_detalhes"."peso",
    "animais_detalhes"."foto",
    "animais_detalhes"."album",
    "animais_detalhes"."descricao",
    "animais_detalhes"."castrado",
    "animais_detalhes"."adotado",
    "animais_detalhes"."vacinado",
    "animais_detalhes"."vermifugado",
    "animais_detalhes"."desparasitado",
    "animais_detalhes"."desaparecido",
    "animais_detalhes"."disponivel",
    "animais_detalhes"."internado",
    "animais_detalhes"."falecido",
    "animal_status"."status"
   FROM ("public"."animais_detalhes"
     LEFT JOIN "public"."animal_status" ON (("animais_detalhes"."animal_id" = "animal_status"."id")))
  WHERE (("animais_detalhes"."adotado" IS FALSE) AND ("animais_detalhes"."desaparecido" IS FALSE) AND ("animais_detalhes"."internado" IS FALSE) AND ("animais_detalhes"."falecido" IS FALSE) AND ("animais_detalhes"."disponivel" IS NOT FALSE));


ALTER TABLE "public"."_n8n_animais_site" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cores" (
    "cor" "text" NOT NULL,
    "canil_id" bigint
);


ALTER TABLE "public"."cores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."generos" (
    "genero" "text" NOT NULL
);


ALTER TABLE "public"."generos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."idades" (
    "idade" "text" DEFAULT ''::"text" NOT NULL,
    "indice" smallint DEFAULT '0'::smallint NOT NULL,
    "descritivo" "text"
);


ALTER TABLE "public"."idades" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pelagens" (
    "pelagem" "text" NOT NULL,
    "indice" smallint
);


ALTER TABLE "public"."pelagens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."portes" (
    "porte" "text" NOT NULL,
    "descritivo" "text",
    "indice" smallint,
    "limite_peso" smallint
);


ALTER TABLE "public"."portes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."racas" (
    "raca" "text" NOT NULL,
    "indice" smallint,
    "especie" "text" DEFAULT 'Cachorro'::"text",
    "canil_id" bigint
);


ALTER TABLE "public"."racas" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."_n8n_caracteristicas" WITH ("security_invoker"='on') AS
 WITH "base" AS (
         SELECT ( SELECT "array_agg"("generos"."genero") AS "array_agg"
                   FROM "public"."generos") AS "sexo",
            ( SELECT "array_agg"("portes"."porte") AS "array_agg"
                   FROM "public"."portes") AS "porte",
            ( SELECT "array_agg"("cores"."cor") AS "array_agg"
                   FROM "public"."cores") AS "cor",
            ( SELECT "array_agg"("especies"."especie") AS "array_agg"
                   FROM "public"."especies") AS "especie",
            ( SELECT "array_agg"("idades"."idade") AS "array_agg"
                   FROM "public"."idades") AS "faixa_etaria",
            ( SELECT "array_agg"("pelagens"."pelagem") AS "array_agg"
                   FROM "public"."pelagens") AS "pelagem",
            ( SELECT "array_agg"("racas"."raca") AS "array_agg"
                   FROM "public"."racas") AS "raça"
        )
 SELECT 'sexo'::"text" AS "caracteristica",
    ( SELECT "base"."sexo"
           FROM "base"
         LIMIT 1) AS "categorias"
UNION ALL
 SELECT 'porte'::"text" AS "caracteristica",
    ( SELECT "base"."porte"
           FROM "base"
         LIMIT 1) AS "categorias"
UNION ALL
 SELECT 'cor'::"text" AS "caracteristica",
    ( SELECT "base"."cor"
           FROM "base"
         LIMIT 1) AS "categorias"
UNION ALL
 SELECT 'especie'::"text" AS "caracteristica",
    ( SELECT "base"."especie"
           FROM "base"
         LIMIT 1) AS "categorias"
UNION ALL
 SELECT 'faixa_etaria'::"text" AS "caracteristica",
    ( SELECT "base"."faixa_etaria"
           FROM "base"
         LIMIT 1) AS "categorias"
UNION ALL
 SELECT 'pelagem'::"text" AS "caracteristica",
    ( SELECT "base"."pelagem"
           FROM "base"
         LIMIT 1) AS "categorias"
UNION ALL
 SELECT 'raça'::"text" AS "caracteristica",
    ( SELECT "base"."raça"
           FROM "base"
         LIMIT 1) AS "categorias";


ALTER TABLE "public"."_n8n_caracteristicas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medicamento" (
    "id" bigint NOT NULL,
    "nome" "text",
    "canil_id" bigint
);


ALTER TABLE "public"."medicamento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prescricao" (
    "id" bigint NOT NULL,
    "inicio" "date",
    "receita" bigint,
    "medicamento" bigint,
    "continuo" boolean DEFAULT false,
    "duracao_dias" smallint,
    "dosagem" "text" DEFAULT ''::"text",
    "via" "text" DEFAULT ''::"text",
    "descricao" "text" DEFAULT ''::"text",
    "intervalo_horas" smallint,
    "criacao" timestamp without time zone DEFAULT "now"(),
    "finalizada" boolean DEFAULT false,
    "inicio_horario" time without time zone,
    "salva" boolean DEFAULT false,
    "dose" "text" DEFAULT ''::"text"
);


ALTER TABLE "public"."prescricao" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."receita" (
    "id" bigint NOT NULL,
    "data" "date" DEFAULT "now"() NOT NULL,
    "veterinario" "uuid",
    "animal" "uuid",
    "salva" boolean DEFAULT false
);


ALTER TABLE "public"."receita" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."veterinarios" (
    "nome" "text",
    "foto" "text",
    "crmv" bigint,
    "vet_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "indice" smallint,
    "usuario_id" "uuid",
    "canil_id" bigint
);


ALTER TABLE "public"."veterinarios" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."_n8n_prescricoes" WITH ("security_invoker"='true') AS
 SELECT "prescricao"."inicio",
    "receita"."animal" AS "animal_id",
    "prescricao"."continuo" AS "uso_continuo",
    "prescricao"."intervalo_horas",
    "prescricao"."duracao_dias",
    "prescricao"."dose",
    "prescricao"."dosagem",
    "prescricao"."via",
    "prescricao"."descricao",
    "prescricao"."finalizada",
    "veterinarios"."nome" AS "veterinario_nome",
    "medicamento"."nome" AS "medicamento_nome",
    "animais"."nome" AS "animal_nome",
    "prescricao"."inicio_horario" AS "horario_inicio",
    (("prescricao"."inicio" + ((
        CASE
            WHEN ("prescricao"."continuo" = true) THEN 9000
            ELSE ("prescricao"."duracao_dias")::integer
        END)::double precision * '1 day'::interval)))::"date" AS "data_termino",
    (("prescricao"."finalizada" = true) OR (CURRENT_DATE > (("prescricao"."inicio" + ((
        CASE
            WHEN ("prescricao"."continuo" = true) THEN 9000
            ELSE ("prescricao"."duracao_dias")::integer
        END)::double precision * '1 day'::interval)))::"date")) AS "terminada",
    "to_char"(("prescricao"."inicio_horario")::interval, 'HH24:MI'::"text") AS "horario_texto"
   FROM (((("public"."prescricao"
     LEFT JOIN "public"."receita" ON (("prescricao"."receita" = "receita"."id")))
     LEFT JOIN "public"."animais" ON (("receita"."animal" = "animais"."animal_id")))
     LEFT JOIN "public"."veterinarios" ON (("receita"."veterinario" = "veterinarios"."vet_id")))
     LEFT JOIN "public"."medicamento" ON (("prescricao"."medicamento" = "medicamento"."id")));


ALTER TABLE "public"."_n8n_prescricoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."anamneses_registros" (
    "id" bigint NOT NULL,
    "observacao" "text",
    "animal" "uuid",
    "data" "date" DEFAULT "now"(),
    "veterinario" "uuid",
    "condicoes" bigint[],
    "temperatura" real,
    "score" smallint,
    "pesagem" bigint
);


ALTER TABLE "public"."anamneses_registros" OWNER TO "postgres";


ALTER TABLE "public"."anamneses_registros" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."anamneses_registros_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."condicoes_parametro" (
    "condicao" "text" NOT NULL,
    "parametro" "text" DEFAULT ''::"text" NOT NULL,
    "id" bigint NOT NULL,
    "negativo" boolean DEFAULT false,
    "valor" smallint DEFAULT '0'::smallint NOT NULL,
    "canil_id" bigint
);


ALTER TABLE "public"."condicoes_parametro" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."anamneses_view" WITH ("security_invoker"='true') AS
 SELECT "anamneses_registros"."id",
    "anamneses_registros"."observacao",
    "anamneses_registros"."animal",
    "anamneses_registros"."data",
    "anamneses_registros"."veterinario",
    "anamneses_registros"."condicoes",
    "anamneses_registros"."temperatura",
    "anamneses_registros"."score",
    "anamneses_registros"."pesagem",
    COALESCE("veterinarios"."nome", ''::"text") AS "veterinario_nome",
    COALESCE("animais"."nome", ''::"text") AS "animal_nome",
    "pesagens"."peso",
    (1.0 - ((1.0 * (( SELECT "count"(*) AS "count"
           FROM ("unnest"("anamneses_registros"."condicoes") "cnd"("cnd")
             JOIN "public"."condicoes_parametro" ON (("condicoes_parametro"."id" = "cnd"."cnd")))
          WHERE ("condicoes_parametro"."negativo" = true)))::numeric) / (( SELECT "count"(*) AS "count"
           FROM "public"."condicoes_parametro"
          WHERE ("condicoes_parametro"."negativo" = true)))::numeric)) AS "nota",
    "animais"."canil"
   FROM ((("public"."anamneses_registros"
     JOIN "public"."veterinarios" ON (("veterinarios"."vet_id" = "anamneses_registros"."veterinario")))
     LEFT JOIN "public"."animais" ON (("animais"."animal_id" = "anamneses_registros"."animal")))
     LEFT JOIN "public"."pesagens" ON (("pesagens"."id" = "anamneses_registros"."pesagem")));


ALTER TABLE "public"."anamneses_view" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animais_dados" WITH ("security_invoker"='on') AS
 SELECT "animais"."animal_id",
    "animais"."criado",
    "animais"."nome",
    "animais"."nascimento",
    "animais"."genero",
    "animais"."raça",
    "animais"."especie",
    "animais"."cor",
    "animais"."pelagem",
    "animais"."falecido",
    "animais"."foto",
    "animais"."castrado",
    "animais"."desaparecido",
    "animais"."vacinado",
    "animais"."vermifugado",
    "animais"."desparasitado",
    "animais"."porte",
    "animais"."torax",
    "animais"."comprimento",
    "animais"."pescoço",
    "animais"."altura",
    "animais"."canil",
    "animais"."adotado",
    EXTRACT(year FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) AS "idade_anos",
    EXTRACT(month FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) AS "idade_meses",
        CASE
            WHEN (EXTRACT(year FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) > (10)::numeric) THEN 'Idoso'::"text"
            WHEN (EXTRACT(year FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) > (3)::numeric) THEN 'Adulto'::"text"
            WHEN (EXTRACT(year FROM "age"(CURRENT_TIMESTAMP, ("animais"."nascimento")::timestamp with time zone)) > (1)::numeric) THEN 'Jovem'::"text"
            ELSE 'Filhote'::"text"
        END AS "faixa_etaria",
    ( SELECT "pesagens"."peso"
           FROM "public"."pesagens"
          WHERE ("pesagens"."animal" = "animais"."animal_id")
          ORDER BY "pesagens"."data" DESC
         LIMIT 1) AS "peso",
    "animais"."diagnosticos",
    "animais"."disponivel",
    "animais"."internado",
    "animais"."album",
    "animais".*::"public"."animais" AS "animais"
   FROM ("public"."animais"
     LEFT JOIN "public"."animais_descricao" ON (("animais"."animal_id" = "animais_descricao"."animal")));


ALTER TABLE "public"."animais_dados" OWNER TO "postgres";


ALTER TABLE "public"."animais_descricao" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."animais_descricao_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."animais_disponiveis" WITH ("security_invoker"='true') AS
 SELECT "animais"."animal_id",
    "animais"."canil"
   FROM "public"."animais"
  WHERE (("animais"."falecido" = false) AND ("animais"."desaparecido" = false) AND ("animais"."internado" = false) AND ("animais"."adotado" = false));


ALTER TABLE "public"."animais_disponiveis" OWNER TO "postgres";


ALTER TABLE "public"."animais" ALTER COLUMN "idx" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."animais_idx_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."animais_quantidades" WITH ("security_invoker"='true') AS
 SELECT "c"."id" AS "canil_id",
    "c"."canil" AS "canil_nome",
    COALESCE(( SELECT "count"(*) AS "count"
           FROM "public"."animais"
          WHERE (("animais"."falecido" = true) AND ("animais"."canil" = "c"."id"))), (0)::bigint) AS "falecidos",
    COALESCE(( SELECT "count"(*) AS "count"
           FROM "public"."animais"
          WHERE (("animais"."falecido" = false) AND ("animais"."internado" = true) AND ("animais"."canil" = "c"."id"))), (0)::bigint) AS "internados",
    COALESCE(( SELECT "count"(*) AS "count"
           FROM "public"."animais"
          WHERE (("animais"."falecido" = false) AND ("animais"."internado" = false) AND ("animais"."desaparecido" = true) AND ("animais"."canil" = "c"."id"))), (0)::bigint) AS "desaparecidos",
    COALESCE(( SELECT "count"(*) AS "count"
           FROM "public"."animais"
          WHERE (("animais"."falecido" = false) AND ("animais"."internado" = false) AND ("animais"."desaparecido" = false) AND ("animais"."adotado" = false) AND ("animais"."canil" = "c"."id"))), (0)::bigint) AS "abrigados",
    COALESCE(( SELECT "count"(*) AS "count"
           FROM "public"."animais"
          WHERE (("animais"."falecido" = false) AND ("animais"."internado" = false) AND ("animais"."desaparecido" = false) AND ("animais"."adotado" = true) AND ("animais"."canil" = "c"."id"))), (0)::bigint) AS "adotados",
    COALESCE(( SELECT "count"(*) AS "count"
           FROM "public"."animais"
          WHERE ("animais"."canil" = "c"."id")), (0)::bigint) AS "todos"
   FROM ("public"."canis" "c"
     LEFT JOIN "public"."animais" "a" ON (("a"."canil" = "c"."id")))
  GROUP BY "c"."id", "c"."canil";


ALTER TABLE "public"."animais_quantidades" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animais_site" AS
 SELECT "animais"."animal_id",
    "animais"."nome",
    "animais"."especie",
    "animais"."genero" AS "sexo",
    "animais"."raça",
    "animais"."porte",
    "animais"."canil",
    "animais"."faixa_etaria",
    "animais"."foto",
    "animais"."album",
    "animal_status"."status",
    "animais_descricao"."descricao"
   FROM (("public"."animais_dados" "animais"
     LEFT JOIN "public"."animal_status" ON (("animais"."animal_id" = "animal_status"."id")))
     LEFT JOIN "public"."animais_descricao" ON (("animais"."animal_id" = "animais_descricao"."animal")));


ALTER TABLE "public"."animais_site" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animais_site_publico" AS
 SELECT "animais"."animal_id",
    "animais"."nome",
    "animais"."especie",
    "animais"."genero" AS "sexo",
    "animais"."raça",
    "animais"."porte",
    "animais"."canil",
    "animais"."faixa_etaria",
    "animais"."foto",
    "animais"."album",
    "animal_status"."status"
   FROM ("public"."animais_dados" "animais"
     LEFT JOIN "public"."animal_status" ON (("animais"."animal_id" = "animal_status"."id")))
  WHERE (("animais"."falecido" IS FALSE) AND ("animais"."adotado" IS FALSE) AND ("animais"."internado" IS FALSE) AND ("animais"."desaparecido" IS FALSE) AND ("animais"."disponivel" IS NOT FALSE));


ALTER TABLE "public"."animais_site_publico" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animal_condicoes" WITH ("security_invoker"='true') AS
 SELECT "ar"."animal",
    "ar"."condicoes",
    "ar"."data"
   FROM ("public"."anamneses_registros" "ar"
     JOIN ( SELECT "anamneses_registros"."animal",
            "max"("anamneses_registros"."data") AS "max_data"
           FROM "public"."anamneses_registros"
          GROUP BY "anamneses_registros"."animal") "max_data_per_animal" ON ((("ar"."animal" = "max_data_per_animal"."animal") AND ("ar"."data" = "max_data_per_animal"."max_data"))));


ALTER TABLE "public"."animal_condicoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."diagnostico" (
    "nome" "text" NOT NULL,
    "id" integer NOT NULL,
    "especie" "text",
    "canil_id" bigint
);


ALTER TABLE "public"."diagnostico" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animal_diagnosticos" WITH ("security_invoker"='true') AS
 SELECT "a"."animal_id",
    "d"."nome" AS "diagnostico"
   FROM ("public"."animais" "a"
     JOIN "public"."diagnostico" "d" ON (("d"."id" = ANY ("a"."diagnosticos"))))
  ORDER BY "a"."animal_id";


ALTER TABLE "public"."animal_diagnosticos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animal_diagnosticos_lista" WITH ("security_invoker"='true') AS
 SELECT "a"."animal_id",
    "a"."nome" AS "animal_nome",
    "array_agg"("d"."nome") AS "diagnosticos",
    "array_agg"("d"."id") AS "diagnosticos_ids"
   FROM ("public"."animais" "a"
     JOIN "public"."diagnostico" "d" ON (("d"."id" = ANY ("a"."diagnosticos"))))
  GROUP BY "a"."animal_id", "a"."nome"
  ORDER BY "a"."animal_id";


ALTER TABLE "public"."animal_diagnosticos_lista" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."animal_painel" AS
SELECT
    NULL::"uuid" AS "animal_id",
    NULL::"date" AS "vacina_anterior",
    NULL::"date" AS "vacina_proxima",
    NULL::integer AS "vacina_anterior_dias",
    NULL::integer AS "vacina_proxima_dias",
    NULL::"date" AS "vermifugo_anterior",
    NULL::"date" AS "vermifugo_proximo",
    NULL::integer AS "vermifugo_anterior_dias",
    NULL::integer AS "vermifugo_proxima_dias",
    NULL::"date" AS "desparasitacao_anterior",
    NULL::"date" AS "desparasitacao_proximo",
    NULL::integer AS "desparasitacao_anterior_dias",
    NULL::integer AS "desparasitacao_proxima_dias",
    NULL::"date" AS "avaliacao_data",
    NULL::smallint AS "score_ultimo",
    NULL::numeric AS "saude_indice",
    NULL::bigint[] AS "condicoes",
    NULL::integer AS "avaliacao_dias",
    NULL::"text" AS "observacao",
    NULL::"date" AS "peso_data",
    NULL::real AS "peso_anterior",
    NULL::real AS "peso_atual",
    NULL::real AS "peso_variacao";


ALTER TABLE "public"."animal_painel" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."arquivos" (
    "aquivo" "text" DEFAULT ''::"text" NOT NULL,
    "nome" "text" DEFAULT ''::"text" NOT NULL,
    "id" bigint NOT NULL,
    "animal" "uuid",
    "registro" bigint,
    "criacao" "date",
    "observacao" "text",
    "apagado" boolean DEFAULT false
);


ALTER TABLE "public"."arquivos" OWNER TO "postgres";


ALTER TABLE "public"."arquivos" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."arquivos_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."arquivos_view" WITH ("security_invoker"='true') AS
 SELECT "arquivos"."id",
    "arquivos"."aquivo",
    "arquivos"."nome",
    "arquivos"."criacao",
    "arquivos"."observacao",
    "arquivos"."animal",
    "animais"."nome" AS "nome_animal"
   FROM ("public"."arquivos"
     LEFT JOIN "public"."animais" ON (("arquivos"."animal" = "animais"."animal_id")))
  WHERE ("arquivos"."apagado" = false);


ALTER TABLE "public"."arquivos_view" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."avaliacoes_antigas" WITH ("security_invoker"='true') AS
 SELECT "ar"."id",
    "ar"."data",
    "ar"."animal",
    "a"."nome" AS "animal_nome",
    "a"."canil",
    COALESCE((CURRENT_DATE - "ar"."data"), NULL::integer) AS "dias_passados"
   FROM (( SELECT "ar_1"."id",
            "ar_1"."observacao",
            "ar_1"."animal",
            "ar_1"."data",
            "ar_1"."veterinario",
            "ar_1"."condicoes",
            "ar_1"."temperatura",
            "ar_1"."score",
            "ar_1"."pesagem",
            "row_number"() OVER (PARTITION BY "ar_1"."animal" ORDER BY "ar_1"."data" DESC) AS "rn"
           FROM "public"."anamneses_registros" "ar_1") "ar"
     JOIN "public"."animais" "a" ON (("ar"."animal" = "a"."animal_id")))
  WHERE (("ar"."rn" = 1) AND ("a"."adotado" = false) AND ("a"."falecido" = false) AND ("a"."desaparecido" = false))
  ORDER BY "ar"."id";


ALTER TABLE "public"."avaliacoes_antigas" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."avaliacoes_painel" WITH ("security_invoker"='true') AS
 SELECT DISTINCT "a"."animal_id" AS "animal",
    COALESCE("av"."id", (0)::bigint) AS "id",
    COALESCE("av"."data", NULL::"date") AS "data",
    "a"."nome" AS "animal_nome",
    "a"."canil",
    COALESCE((CURRENT_DATE - "av"."data"), 999) AS "dias_passados",
    COALESCE("av"."nota", (0)::numeric) AS "nota",
    "av"."score",
    "av"."condicoes"
   FROM ("public"."animais" "a"
     LEFT JOIN ( SELECT "av_1"."id",
            "av_1"."observacao",
            "av_1"."animal",
            "av_1"."data",
            "av_1"."veterinario",
            "av_1"."condicoes",
            "av_1"."temperatura",
            "av_1"."score",
            "av_1"."pesagem",
            "av_1"."veterinario_nome",
            "av_1"."animal_nome",
            "av_1"."peso",
            "av_1"."nota",
            "av_1"."canil",
            "av_1"."rn"
           FROM ( SELECT "ar"."id",
                    "ar"."observacao",
                    "ar"."animal",
                    "ar"."data",
                    "ar"."veterinario",
                    "ar"."condicoes",
                    "ar"."temperatura",
                    "ar"."score",
                    "ar"."pesagem",
                    "ar"."veterinario_nome",
                    "ar"."animal_nome",
                    "ar"."peso",
                    "ar"."nota",
                    "ar"."canil",
                    "row_number"() OVER (PARTITION BY "ar"."animal" ORDER BY "ar"."data" DESC) AS "rn"
                   FROM "public"."anamneses_view" "ar") "av_1"
          WHERE ("av_1"."rn" = 1)) "av" ON (("av"."animal" = "a"."animal_id")))
  WHERE ("a"."animal_id" IN ( SELECT "animais"."animal_id"
           FROM "public"."animais"
          WHERE (("animais"."adotado" = false) AND ("animais"."falecido" = false) AND ("animais"."desaparecido" = false))))
  ORDER BY "a"."animal_id";


ALTER TABLE "public"."avaliacoes_painel" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."canis_membros" (
    "id" bigint NOT NULL,
    "canil" bigint NOT NULL,
    "membro" "uuid" NOT NULL,
    "admin" boolean DEFAULT false,
    "guest" boolean DEFAULT false,
    "vet" boolean DEFAULT false NOT NULL,
    "solicitacao_aceita" boolean DEFAULT false,
    "solicitacao_realizada" boolean DEFAULT false
);


ALTER TABLE "public"."canis_membros" OWNER TO "postgres";


COMMENT ON COLUMN "public"."canis_membros"."solicitacao_aceita" IS 'NULL - NÃO SOLICITADO // FALSE - RECUSADA // TRUE - ACEITA';



COMMENT ON COLUMN "public"."canis_membros"."solicitacao_realizada" IS 'foi feito pedido de acesso ao canil pelo usuario';



CREATE TABLE IF NOT EXISTS "public"."usuarios" (
    "user_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_name" "text",
    "user_email" "text" NOT NULL,
    "foto" "text"
);


ALTER TABLE "public"."usuarios" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."canil_prioritario" WITH ("security_invoker"='true') AS
 SELECT DISTINCT "u"."user_id" AS "usuario_id",
    COALESCE("c"."id", "cm"."canil") AS "canil_id"
   FROM (("public"."usuarios" "u"
     LEFT JOIN "public"."canis" "c" ON (("c"."proprietario" = "u"."user_id")))
     LEFT JOIN "public"."canis_membros" "cm" ON ((("cm"."membro" = "u"."user_id") AND (("cm"."admin" = true) OR ("cm"."guest" = true) OR ("cm"."vet" = true)))));


ALTER TABLE "public"."canil_prioritario" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."canil_tratador" (
    "id" bigint NOT NULL,
    "canil" bigint,
    "usuario" "text" NOT NULL,
    "nome" "text",
    "senha" "text"
);


ALTER TABLE "public"."canil_tratador" OWNER TO "postgres";


ALTER TABLE "public"."canil_tratador" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."canil_tratador_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."canis_disponiveis" WITH ("security_invoker"='true') AS
 SELECT "u"."user_id" AS "usuario",
    "c"."id" AS "canil",
    ("cm"."membro" = "u"."user_id") AS "membro",
    "cm"."solicitacao_realizada" AS "solicitado",
    "cm"."solicitacao_aceita" AS "aceito"
   FROM (("public"."usuarios" "u"
     LEFT JOIN "public"."canis" "c" ON (("c"."proprietario" <> "u"."user_id")))
     LEFT JOIN "public"."canis_membros" "cm" ON ((("cm"."membro" = "u"."user_id") AND ("cm"."canil" = "c"."id"))));


ALTER TABLE "public"."canis_disponiveis" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."canis_membros_view" WITH ("security_invoker"='true') AS
 SELECT "cm"."id",
    "cm"."canil",
    "cm"."membro",
    "cm"."admin",
    "cm"."guest",
    "c"."canil" AS "canil_nome",
    "cm"."vet",
    "u"."user_name" AS "membro_nome",
    "cm"."solicitacao_aceita",
    "cm"."solicitacao_realizada"
   FROM (("public"."canis_membros" "cm"
     LEFT JOIN "public"."canis" "c" ON (("c"."id" = "cm"."canil")))
     LEFT JOIN "public"."usuarios" "u" ON (("u"."user_id" = "cm"."membro")));


ALTER TABLE "public"."canis_membros_view" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."canis_disponiveis_usuario" WITH ("security_invoker"='true') AS
 SELECT "u"."user_id",
    ( SELECT "array_agg"("cmv"."id") AS "array_agg"
           FROM "public"."canis_membros_view" "cmv"
          WHERE ("cmv"."membro" <> "u"."user_id")) AS "canis_disponiveis"
   FROM "public"."usuarios" "u";


ALTER TABLE "public"."canis_disponiveis_usuario" OWNER TO "postgres";


ALTER TABLE "public"."canis" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."canis_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."canis_membros" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."canis_responsaveis_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."canis_view" WITH ("security_invoker"='true') AS
 SELECT "canis"."id",
    "canis"."canil" AS "canil_nome",
    "canis"."proprietario",
    "usuarios"."user_name" AS "proprietario_nome",
    "right"(("canis"."proprietario")::"text", 8) AS "chave",
    "canis"."aceita_inscricoes"
   FROM ("public"."canis"
     LEFT JOIN "public"."usuarios" ON (("usuarios"."user_id" = "canis"."proprietario")));


ALTER TABLE "public"."canis_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."caracteristicas" (
    "caracteristica" bigint NOT NULL,
    "positiva" boolean
);


ALTER TABLE "public"."caracteristicas" OWNER TO "postgres";


ALTER TABLE "public"."caracteristicas" ALTER COLUMN "caracteristica" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."caracteristicas_caracteristica_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."castracao_pendente" WITH ("security_invoker"='true') AS
 SELECT "a"."animal_id",
    "a"."nome" AS "animal_nome",
    "a"."genero",
    "a"."especie",
    "a"."peso",
    "a"."canil"
   FROM "public"."animais" "a"
  WHERE (("a"."castrado" = false) AND ("a"."falecido" = false) AND ("a"."desaparecido" = false) AND ("a"."adotado" = false))
  ORDER BY "a"."animal_id";


ALTER TABLE "public"."castracao_pendente" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clinicas" (
    "clinica" "text" NOT NULL,
    "telefone" "text" DEFAULT ''::"text",
    "endereco" "text" DEFAULT ''::"text",
    "logo" "text" DEFAULT ''::"text",
    "canil_id" bigint
);


ALTER TABLE "public"."clinicas" OWNER TO "postgres";


ALTER TABLE "public"."condicoes_parametro" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."condicoes_parametro_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."conexao" (
    "id" bigint NOT NULL,
    "data" "date" DEFAULT "now"() NOT NULL,
    "pessoa" bigint,
    "animal" "uuid",
    "encerrada" boolean DEFAULT false
);


ALTER TABLE "public"."conexao" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."conexao_registro" (
    "id" bigint NOT NULL,
    "data" timestamp without time zone DEFAULT "now"() NOT NULL,
    "status" "text" NOT NULL,
    "observacao" "text"
);


ALTER TABLE "public"."conexao_registro" OWNER TO "postgres";


ALTER TABLE "public"."conexao_registro" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."conexao_registro_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."conexao_status" (
    "id" "text" NOT NULL,
    "indice" smallint,
    "negativo" boolean DEFAULT false,
    "terminou" boolean DEFAULT false
);


ALTER TABLE "public"."conexao_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."database_schema" AS
 WITH "column_info" AS (
         SELECT "c"."table_name",
            "c"."column_name",
            "c"."data_type",
            COALESCE(( SELECT ((('FOREIGN_KEY '::"text" || ("kcu2"."table_name")::"text") || '.'::"text") || ("kcu2"."column_name")::"text")
                   FROM ("information_schema"."referential_constraints" "rc"
                     JOIN "information_schema"."key_column_usage" "kcu2" ON ((("rc"."constraint_name")::"name" = ("kcu2"."constraint_name")::"name")))
                  WHERE ((("kcu2"."constraint_name")::"name" = ("kcu"."constraint_name")::"name") AND (("rc"."constraint_schema")::"name" = 'public'::"name"))
                 LIMIT 1), ''::"text") AS "foreign_key_info"
           FROM (("information_schema"."columns" "c"
             LEFT JOIN "information_schema"."table_constraints" "tc" ON (((("c"."table_schema")::"name" = ("tc"."table_schema")::"name") AND (("c"."table_name")::"name" = ("tc"."table_name")::"name") AND (("tc"."constraint_type")::"text" = 'FOREIGN KEY'::"text"))))
             LEFT JOIN "information_schema"."key_column_usage" "kcu" ON (((("tc"."constraint_name")::"name" = ("kcu"."constraint_name")::"name") AND (("c"."column_name")::"name" = ("kcu"."column_name")::"name"))))
          WHERE (("c"."table_schema")::"name" = 'public'::"name")
        )
 SELECT "column_info"."table_name",
    "jsonb_agg"(DISTINCT ((((("column_info"."column_name")::"text" || ' ('::"text") || ("column_info"."data_type")::"text") ||
        CASE
            WHEN ("column_info"."foreign_key_info" <> ''::"text") THEN (' '::"text" || "column_info"."foreign_key_info")
            ELSE ''::"text"
        END) || ')'::"text")) AS "fields"
   FROM "column_info"
  GROUP BY "column_info"."table_name"
  ORDER BY "column_info"."table_name";


ALTER TABLE "public"."database_schema" OWNER TO "postgres";


ALTER TABLE "public"."diagnostico" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."diagnostico_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."document_metadata" (
    "id" "text" NOT NULL,
    "title" "text",
    "url" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "schema" "text"
);


ALTER TABLE "public"."document_metadata" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."document_rows" (
    "id" integer NOT NULL,
    "dataset_id" "text",
    "row_data" "jsonb"
);


ALTER TABLE "public"."document_rows" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."document_rows_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."document_rows_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."document_rows_id_seq" OWNED BY "public"."document_rows"."id";



CREATE TABLE IF NOT EXISTS "public"."documents" (
    "id" bigint NOT NULL,
    "content" "text",
    "fts" "tsvector" GENERATED ALWAYS AS ("to_tsvector"('"portuguese"'::"regconfig", "content")) STORED,
    "embedding" "public"."vector"(1536),
    "metadata" "jsonb"
);


ALTER TABLE "public"."documents" OWNER TO "postgres";


ALTER TABLE "public"."documents" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."documents_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."escolaridade" (
    "id" "text" NOT NULL
);


ALTER TABLE "public"."escolaridade" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."export_animals" AS
 SELECT "animais"."animal_id" AS "id",
    "animais"."nome" AS "name",
    "animais"."nascimento" AS "birth_date",
    "animais"."especie" AS "species_name",
    "animais"."genero" AS "gender_name",
    "animais"."porte" AS "size_name",
    "animais"."raça" AS "breed_name",
    "animais"."pelagem" AS "fur_name",
    "animais"."cor" AS "color_name",
    "animais"."foto" AS "profile_picture_url",
    "animais"."canil" AS "shelter_old_id",
    "animais"."falecido" AS "deceased",
    "animais"."castrado" AS "castrated",
    "animais"."adotado" AS "adopted",
    "animais"."internado" AS "hospitalized",
    "animais"."desaparecido" AS "missing"
   FROM "public"."animais";


ALTER TABLE "public"."export_animals" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."export_breeds" AS
 SELECT DISTINCT "racas"."raca" AS "name",
    "racas"."especie" AS "species_name"
   FROM "public"."racas";


ALTER TABLE "public"."export_breeds" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."export_colors" AS
 SELECT DISTINCT "cores"."cor" AS "name"
   FROM "public"."cores";


ALTER TABLE "public"."export_colors" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."export_furs" AS
 SELECT DISTINCT "pelagens"."pelagem" AS "name"
   FROM "public"."pelagens";


ALTER TABLE "public"."export_furs" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."export_genders" AS
 SELECT DISTINCT "generos"."genero" AS "name"
   FROM "public"."generos";


ALTER TABLE "public"."export_genders" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."export_sizes" AS
 SELECT DISTINCT "portes"."porte" AS "name",
    "portes"."limite_peso" AS "max_weight"
   FROM "public"."portes";


ALTER TABLE "public"."export_sizes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."export_species" AS
 SELECT DISTINCT "especies"."especie" AS "name"
   FROM "public"."especies";


ALTER TABLE "public"."export_species" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."export_weights" AS
 SELECT "pesagens"."id",
    "pesagens"."animal" AS "animal_id",
    "pesagens"."data" AS "date_time",
    "pesagens"."peso" AS "value"
   FROM "public"."pesagens";


ALTER TABLE "public"."export_weights" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."idades_view" WITH ("security_invoker"='true') AS
 SELECT "animais"."animal_id" AS "animal",
    "age"((CURRENT_DATE)::timestamp with time zone, ("animais"."nascimento")::timestamp with time zone) AS "idade"
   FROM "public"."animais";


ALTER TABLE "public"."idades_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."imunizacao" (
    "id" bigint NOT NULL,
    "criacao" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tipo" "text",
    "animal" "uuid",
    "veterinario" "uuid",
    "clinica" "text",
    "tarefa" bigint,
    "imunizante" bigint,
    "observacao" "text",
    "registro" bigint
);


ALTER TABLE "public"."imunizacao" OWNER TO "postgres";


ALTER TABLE "public"."imunizacao" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."imunizacao_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."imunizacao_tipo" (
    "id" "text" NOT NULL,
    "icone" "text",
    "canil_id" bigint
);


ALTER TABLE "public"."imunizacao_tipo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."imunizante" (
    "id" bigint NOT NULL,
    "imunizacao_tipo" "text",
    "especie" "text",
    "nome" "text",
    "canil_id" bigint
);


ALTER TABLE "public"."imunizante" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tarefa" (
    "id" bigint NOT NULL,
    "data_criada" "date" DEFAULT "now"() NOT NULL,
    "data_prevista" "date" DEFAULT "now"(),
    "data_realizada" "date",
    "animal" "uuid",
    "tipo" "text",
    "descricao" "text"
);


ALTER TABLE "public"."tarefa" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."imunizacao_view" WITH ("security_invoker"='true') AS
 SELECT "imunizacao"."id",
    "imunizacao"."animal",
    "imunizacao"."tipo",
    "imunizacao"."imunizante",
    "imunizacao"."veterinario",
    "imunizacao"."clinica",
    "imunizacao"."tarefa",
    COALESCE("veterinarios"."nome", NULL::"text") AS "veterinario_nome",
    COALESCE("tarefa"."data_prevista", NULL::"date") AS "data_prevista",
    COALESCE("tarefa"."data_realizada", NULL::"date") AS "data_realizada",
    COALESCE("tarefa"."descricao", NULL::"text") AS "descricao",
    COALESCE("imunizante"."nome", NULL::"text") AS "nome_imunizante",
    ("tarefa"."data_prevista" > CURRENT_DATE) AS "futura",
    ("tarefa"."data_realizada" IS NOT NULL) AS "aplicada",
    "animais"."canil",
    "animais"."nome",
    COALESCE("tarefa"."data_realizada", "tarefa"."data_prevista") AS "data_exibicao",
    "imunizacao"."registro"
   FROM (((("public"."imunizacao"
     LEFT JOIN "public"."tarefa" ON (("tarefa"."id" = "imunizacao"."tarefa")))
     LEFT JOIN "public"."veterinarios" ON (("veterinarios"."vet_id" = "imunizacao"."veterinario")))
     LEFT JOIN "public"."imunizante" ON (("imunizante"."id" = "imunizacao"."imunizante")))
     LEFT JOIN "public"."animais" ON (("animais"."animal_id" = "imunizacao"."animal")));


ALTER TABLE "public"."imunizacao_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."registros" (
    "registro_id" bigint NOT NULL,
    "data" "date" NOT NULL,
    "tipo" "text",
    "veterinario_id" "uuid",
    "descricao" "text" DEFAULT ''::"text",
    "animal_id" "uuid",
    "clinica" "text",
    "pendente" boolean DEFAULT false,
    "criado_em" timestamp without time zone DEFAULT "now"(),
    "criado_por" "uuid",
    "previsto_data" timestamp without time zone,
    "realizado_data" timestamp without time zone
);


ALTER TABLE "public"."registros" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."imunizacoes_view_2" WITH ("security_invoker"='true') AS
 SELECT "imunizacao"."id",
    "imunizacao"."animal",
    "imunizacao"."tipo",
    "imunizacao"."imunizante",
    "imunizacao"."veterinario",
    "imunizacao"."clinica",
    "imunizacao"."tarefa",
    COALESCE("veterinarios"."nome", NULL::"text") AS "veterinario_nome",
    (COALESCE("registros"."previsto_data", NULL::timestamp without time zone))::"date" AS "data_prevista",
    (COALESCE("registros"."realizado_data", NULL::timestamp without time zone))::"date" AS "data_realizada",
    COALESCE("registros"."descricao", NULL::"text") AS "descricao",
    COALESCE("imunizante"."nome", NULL::"text") AS "nome_imunizante",
    ("registros"."previsto_data" > CURRENT_DATE) AS "futura",
    ("registros"."realizado_data" IS NOT NULL) AS "aplicada",
    "animais"."canil",
    "animais"."nome",
    (COALESCE("registros"."realizado_data", "registros"."previsto_data"))::"date" AS "data_exibicao"
   FROM (((("public"."imunizacao"
     LEFT JOIN "public"."registros" ON (("registros"."registro_id" = "imunizacao"."registro")))
     LEFT JOIN "public"."veterinarios" ON (("veterinarios"."vet_id" = "imunizacao"."veterinario")))
     LEFT JOIN "public"."imunizante" ON (("imunizante"."id" = "imunizacao"."imunizante")))
     LEFT JOIN "public"."animais" ON (("animais"."animal_id" = "imunizacao"."animal")))
  WHERE (("imunizacao"."registro" IS NULL) AND ("animais"."canil" = 19));


ALTER TABLE "public"."imunizacoes_view_2" OWNER TO "postgres";


ALTER TABLE "public"."imunizante" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."imunizante_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."interessado_animal" (
    "id" bigint NOT NULL,
    "data" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pessoa" bigint NOT NULL,
    "animal" "uuid"
);


ALTER TABLE "public"."interessado_animal" OWNER TO "postgres";


ALTER TABLE "public"."interessado_animal" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."interessado_animal_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."questionario" (
    "id" bigint NOT NULL,
    "criacao" "date" DEFAULT "now"() NOT NULL,
    "profissao" "text",
    "renda" smallint,
    "endereco" "text" NOT NULL,
    "rede_social" "text",
    "moradia_tipo" "text",
    "moradia_propria" boolean,
    "moradores_quantidade" smallint,
    "moradores_favoraveis" boolean,
    "moradores_alergia" boolean,
    "caes_qtd" smallint,
    "vacinar_concorda" boolean,
    "castrar_concorda" boolean,
    "educar_concorda" boolean,
    "passear_concorda" boolean,
    "informar_concorda" boolean,
    "passeios_mes" smallint,
    "endCep" "text",
    "endLogradouro" "text",
    "endNumero" "text",
    "endCidade" "text",
    "endUF" "text",
    "endBairro" "text",
    "animais_castrados" boolean,
    "animais_vacinados" boolean,
    "animais_falecimento" boolean,
    "gatos_qtd" smallint,
    "janelas_teladas" boolean,
    "animal_dormir" "text",
    "animais_responsavel" "text",
    "acesso_casa" boolean,
    "acesso_rua" boolean,
    "sozinho_horas" smallint,
    "buscar_concorda" boolean,
    "racao_tipo" "text",
    "animal_incomodo" "text"[],
    "contribuir_concorda" boolean,
    "outros_animais" boolean,
    "passeios" "text",
    "animais_permitidos" boolean,
    "pessoa_id" bigint
);


ALTER TABLE "public"."questionario" OWNER TO "postgres";


ALTER TABLE "public"."questionario" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."interessados_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."conexao" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."interesse_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."medicacao_falhas" (
    "id" "text" NOT NULL
);


ALTER TABLE "public"."medicacao_falhas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medicamento_dosagem" (
    "id" "text" NOT NULL,
    "indice" smallint NOT NULL
);


ALTER TABLE "public"."medicamento_dosagem" OWNER TO "postgres";


ALTER TABLE "public"."medicamento_dosagem" ALTER COLUMN "indice" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."medicamento_dosagem_indice_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."medicamento" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."medicamento_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."medicamento_via" (
    "id" "text" NOT NULL
);


ALTER TABLE "public"."medicamento_via" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."medicamento_view" WITH ("security_invoker"='true') AS
 SELECT "m"."nome",
    "upper"("replace"("m"."nome", ' '::"text", ''::"text")) AS "codigo"
   FROM "public"."medicamento" "m";


ALTER TABLE "public"."medicamento_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medidas" (
    "medida_id" bigint NOT NULL,
    "criacao" timestamp with time zone DEFAULT "now"() NOT NULL,
    "altura" integer,
    "comprimento" integer,
    "pescoco" integer,
    "torax" integer,
    "animal" "uuid"
);


ALTER TABLE "public"."medidas" OWNER TO "postgres";


ALTER TABLE "public"."medidas" ALTER COLUMN "medida_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."medidas_medida_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."moradia_tipos" (
    "tipo_moradia" "text" NOT NULL
);


ALTER TABLE "public"."moradia_tipos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."n8n_chat_histories" (
    "id" integer NOT NULL,
    "session_id" character varying(255) NOT NULL,
    "message" "jsonb" NOT NULL
);


ALTER TABLE "public"."n8n_chat_histories" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."n8n_chat_histories_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."n8n_chat_histories_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."n8n_chat_histories_id_seq" OWNED BY "public"."n8n_chat_histories"."id";



CREATE OR REPLACE VIEW "public"."painel_avaliacoes" WITH ("security_invoker"='true') AS
 SELECT DISTINCT "a"."animal_id" AS "animal",
    COALESCE("av"."id", (0)::bigint) AS "id",
    COALESCE("av"."data", NULL::"date") AS "data",
    "a"."nome" AS "animal_nome",
    "a"."canil",
    COALESCE((CURRENT_DATE - ( SELECT "max"("ar"."data") AS "max"
           FROM "public"."anamneses_registros" "ar"
          WHERE ("ar"."animal" = "a"."animal_id"))), 999) AS "dias_passados",
    COALESCE("av"."nota", (0)::numeric) AS "nota",
    "av"."score",
    "av"."condicoes"
   FROM ("public"."animais" "a"
     LEFT JOIN "public"."anamneses_view" "av" ON (("av"."animal" = "a"."animal_id")))
  WHERE ("a"."animal_id" IN ( SELECT "animais"."animal_id"
           FROM "public"."animais"
          WHERE (("animais"."adotado" = false) AND ("animais"."falecido" = false) AND ("animais"."desaparecido" = false))))
  ORDER BY "a"."animal_id";


ALTER TABLE "public"."painel_avaliacoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."parametros_anamnese" (
    "parametro" "text" NOT NULL,
    "canil_id" bigint
);


ALTER TABLE "public"."parametros_anamnese" OWNER TO "postgres";


ALTER TABLE "public"."pesagens" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."pesagens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."pesagens_view" WITH ("security_invoker"='on') AS
 SELECT "pesagens"."id",
    "pesagens"."animal",
    "animais"."nome" AS "animal_nome",
    "pesagens"."data",
    "pesagens"."peso",
    "lag"("pesagens"."peso") OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data") AS "anterior",
    ("pesagens"."peso" - "lag"("pesagens"."peso") OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data")) AS "diferenca",
    (("pesagens"."peso" - "lag"("pesagens"."peso") OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data")) / NULLIF("lag"("pesagens"."peso") OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data"), (0)::double precision)) AS "variacao",
    COALESCE("anamneses_registros"."id", NULL::bigint) AS "avaliacao_id",
    ("pesagens"."data" - CURRENT_DATE) AS "dias",
    "lag"("pesagens"."peso", 2) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data") AS "anterior2",
    "lag"("pesagens"."peso", 3) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data") AS "anterior3",
    ("pesagens"."peso" - "lag"("pesagens"."peso", 2) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data")) AS "diferenca2",
    ("pesagens"."peso" - "lag"("pesagens"."peso", 3) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data")) AS "diferenca3",
    (("lag"("pesagens"."peso") OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data") - "lag"("pesagens"."peso", 2) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data")) / NULLIF("lag"("pesagens"."peso", 3) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data"), (0)::double precision)) AS "variacao2",
    (("lag"("pesagens"."peso", 2) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data") - "lag"("pesagens"."peso", 3) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data")) / NULLIF("lag"("pesagens"."peso", 3) OVER (PARTITION BY "pesagens"."animal" ORDER BY "pesagens"."data"), (0)::double precision)) AS "variacao3"
   FROM (("public"."pesagens"
     LEFT JOIN "public"."animais" ON (("animais"."animal_id" = "pesagens"."animal")))
     LEFT JOIN "public"."anamneses_registros" ON (("pesagens"."id" = "anamneses_registros"."pesagem")));


ALTER TABLE "public"."pesagens_view" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."pesagens_painel" WITH ("security_invoker"='true') AS
 SELECT DISTINCT ON ("a"."animal_id") "pv"."id",
    "pv"."animal",
    "a"."nome" AS "animal_nome",
    "pv"."data",
    "pv"."peso" AS "peso_pesagem",
    "pv"."anterior",
    "pv"."diferenca",
    "pv"."variacao",
    "pv"."avaliacao_id",
    "pv"."dias",
    "pv"."anterior2",
    "pv"."anterior3",
    "pv"."diferenca2",
    "pv"."diferenca3",
    "pv"."variacao2",
    "pv"."variacao3",
    "a"."canil"
   FROM ("public"."pesagens_view" "pv"
     JOIN "public"."animais" "a" ON (("a"."animal_id" = "pv"."animal")))
  WHERE ("pv"."animal" IN ( SELECT "a_1"."animal_id"
           FROM "public"."animais" "a_1"
          WHERE (("a_1"."adotado" = false) AND ("a_1"."falecido" = false) AND ("a_1"."desaparecido" = false))))
  ORDER BY "a"."animal_id", "pv"."data" DESC;


ALTER TABLE "public"."pesagens_painel" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pessoa" (
    "id" bigint NOT NULL,
    "cadastro" "date" DEFAULT "now"() NOT NULL,
    "nome" "text",
    "nascimento" "date",
    "telefone" "text",
    "email" "text",
    "usuario" "uuid",
    "sexo" smallint,
    "renda_sm" smallint,
    "escolaridade" "text",
    "profissao" "text",
    "end_cep" "text",
    "end_uf" character varying,
    "end_cidade" "text",
    "end_bairro" "text",
    "end_numero" bigint,
    "end_complemento" "text",
    "end_logradouro" "text",
    "whatsap_id" "text",
    "contacts_id" "text"
);


ALTER TABLE "public"."pessoa" OWNER TO "postgres";


ALTER TABLE "public"."pessoa" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."pessoa_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."pessoa_likes" (
    "id" bigint NOT NULL,
    "pessoa_id" bigint,
    "animais" "text"[],
    "usuario" "uuid"
);


ALTER TABLE "public"."pessoa_likes" OWNER TO "postgres";


ALTER TABLE "public"."pessoa_likes" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."pessoa_likes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."pessoa_questionario_view" WITH ("security_invoker"='true') AS
 SELECT "p"."email",
    "p"."nascimento",
    "p"."nome",
    "p"."sexo",
    "p"."telefone",
    "p"."usuario" AS "usuario_id",
    "q"."id",
    "q"."criacao",
    "q"."profissao",
    "q"."renda",
    "q"."endereco",
    "q"."rede_social",
    "q"."moradia_tipo",
    "q"."moradia_propria",
    "q"."moradores_quantidade",
    "q"."moradores_favoraveis",
    "q"."moradores_alergia",
    "q"."caes_qtd",
    "q"."vacinar_concorda",
    "q"."castrar_concorda",
    "q"."educar_concorda",
    "q"."passear_concorda",
    "q"."informar_concorda",
    "q"."passeios_mes",
    "q"."endCep",
    "q"."endLogradouro",
    "q"."endNumero",
    "q"."endCidade",
    "q"."endUF",
    "q"."endBairro",
    "q"."animais_castrados",
    "q"."animais_vacinados",
    "q"."animais_falecimento",
    "q"."gatos_qtd",
    "q"."janelas_teladas",
    "q"."animal_dormir",
    "q"."animais_responsavel",
    "q"."acesso_casa",
    "q"."acesso_rua",
    "q"."sozinho_horas",
    "q"."buscar_concorda",
    "q"."racao_tipo",
    "q"."animal_incomodo",
    "q"."contribuir_concorda",
    "q"."outros_animais",
    "q"."passeios",
    "q"."animais_permitidos",
    "q"."pessoa_id",
    EXTRACT(year FROM "age"(("p"."nascimento")::timestamp with time zone)) AS "idade"
   FROM ("public"."pessoa" "p"
     LEFT JOIN "public"."questionario" "q" ON (("p"."id" = "q"."pessoa_id")));


ALTER TABLE "public"."pessoa_questionario_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sexo" (
    "id" smallint NOT NULL,
    "nome" "text"
);


ALTER TABLE "public"."sexo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."pessoa_view" WITH ("security_invoker"='true') AS
 SELECT "p"."id",
    "p"."cadastro",
    "p"."nome",
    "p"."nascimento",
    "p"."telefone",
    "p"."email",
    "p"."usuario",
    "s"."nome" AS "sexo",
    "p"."renda_sm",
    "p"."escolaridade",
    "p"."profissao",
    "p"."end_cep",
    "p"."end_uf",
    "p"."end_cidade",
    "p"."end_bairro",
    "p"."end_numero",
    "p"."end_complemento",
    "p"."end_logradouro",
    EXTRACT(year FROM "age"(("p"."nascimento")::timestamp with time zone)) AS "idade"
   FROM ("public"."pessoa" "p"
     LEFT JOIN "public"."sexo" "s" ON (("p"."sexo" = "s"."id")));


ALTER TABLE "public"."pessoa_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prescricao_tarefa" (
    "id" bigint NOT NULL,
    "realizacao" timestamp without time zone DEFAULT "now"() NOT NULL,
    "prescricao" bigint NOT NULL,
    "pessoa" "uuid",
    "concluida" boolean DEFAULT false,
    "observacao" "text",
    "dia" "date",
    "hora" time without time zone,
    "tratador" "text"
);


ALTER TABLE "public"."prescricao_tarefa" OWNER TO "postgres";


COMMENT ON TABLE "public"."prescricao_tarefa" IS 'Cada administração de uma determinada prescrição medicamentosa';



CREATE OR REPLACE VIEW "public"."prescricao_view" WITH ("security_invoker"='true') AS
 SELECT "prescricao"."id",
    "prescricao"."receita",
    "prescricao"."inicio",
    "receita"."animal",
    "receita"."veterinario",
    "prescricao"."medicamento",
    "prescricao"."continuo",
    "prescricao"."intervalo_horas",
    "prescricao"."duracao_dias",
    "prescricao"."dose",
    "prescricao"."dosagem",
    "prescricao"."via",
    "prescricao"."descricao",
    "prescricao"."finalizada",
    "veterinarios"."nome" AS "veterinario_nome",
    "medicamento"."nome" AS "medicamento_nome",
    "animais"."nome" AS "animal_nome",
    "prescricao"."inicio_horario",
    (("prescricao"."inicio" + ((
        CASE
            WHEN ("prescricao"."continuo" = true) THEN 9000
            ELSE ("prescricao"."duracao_dias")::integer
        END)::double precision * '1 day'::interval)))::"date" AS "termino",
    (("prescricao"."finalizada" = true) OR (CURRENT_DATE > (("prescricao"."inicio" + ((
        CASE
            WHEN ("prescricao"."continuo" = true) THEN 9000
            ELSE ("prescricao"."duracao_dias")::integer
        END)::double precision * '1 day'::interval)))::"date")) AS "terminada",
    "to_char"(("prescricao"."inicio_horario")::interval, 'HH24:MI'::"text") AS "horario_texto",
    ( SELECT "count"(*) AS "count"
           FROM "public"."prescricao_tarefa"
          WHERE ("prescricao_tarefa"."prescricao" = "prescricao"."id")) AS "tarefas",
    "animais"."canil"
   FROM (((("public"."prescricao"
     LEFT JOIN "public"."receita" ON (("prescricao"."receita" = "receita"."id")))
     LEFT JOIN "public"."animais" ON (("receita"."animal" = "animais"."animal_id")))
     LEFT JOIN "public"."veterinarios" ON (("receita"."veterinario" = "veterinarios"."vet_id")))
     LEFT JOIN "public"."medicamento" ON (("prescricao"."medicamento" = "medicamento"."id")));


ALTER TABLE "public"."prescricao_view" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."prescricao_diaria" AS
 SELECT "prescricao_view"."id",
    "prescricao_view"."receita",
    "prescricao_view"."inicio",
    "prescricao_view"."animal",
    "prescricao_view"."veterinario",
    "prescricao_view"."medicamento",
    "prescricao_view"."continuo",
    "prescricao_view"."intervalo_horas",
    "prescricao_view"."duracao_dias",
    "prescricao_view"."dose",
    "prescricao_view"."dosagem",
    "prescricao_view"."via",
    "prescricao_view"."descricao",
    "prescricao_view"."finalizada",
    "prescricao_view"."veterinario_nome",
    "prescricao_view"."medicamento_nome",
    "prescricao_view"."animal_nome",
    "prescricao_view"."inicio_horario",
    "prescricao_view"."termino",
    "prescricao_view"."terminada",
    "prescricao_view"."canil"
   FROM "public"."prescricao_view"
  WHERE (("prescricao_view"."inicio" <= CURRENT_DATE) AND (("prescricao_view"."continuo" = true) OR (CURRENT_DATE <= ("prescricao_view"."inicio" + ('1 day'::interval * ("prescricao_view"."duracao_dias")::double precision)))));


ALTER TABLE "public"."prescricao_diaria" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."prescricao_horarios" WITH ("security_invoker"='true') AS
 SELECT "pv"."animal",
    "pv"."animal_nome",
    "pv"."descricao",
    "pv"."dosagem",
    "pv"."dose",
    "pv"."id" AS "prescricao",
    "pv"."medicamento",
    "pv"."medicamento_nome",
    CURRENT_DATE AS "dia",
    "h"."hora",
    ( SELECT "pt"."concluida"
           FROM "public"."prescricao_tarefa" "pt"
          WHERE (("pt"."prescricao" = "pv"."id") AND ("pt"."dia" = CURRENT_DATE) AND ("pt"."hora" = "h"."hora"))
         LIMIT 1) AS "realizada",
    "ad"."canil"
   FROM (("public"."prescricao_view" "pv"
     JOIN LATERAL "unnest"(ARRAY( SELECT ("pv"."inicio_horario" + (("i"."i")::double precision * (("pv"."intervalo_horas")::double precision * '01:00:00'::interval)))
           FROM "generate_series"(0, ((COALESCE("round"((24.0 / (NULLIF("pv"."intervalo_horas", 0))::numeric)), (0)::numeric))::integer - 1)) "i"("i")
          WHERE (("pv"."intervalo_horas" IS NOT NULL) AND ("pv"."intervalo_horas" > 0)))) "h"("hora") ON (true))
     JOIN "public"."animais_disponiveis" "ad" ON (("ad"."animal_id" = "pv"."animal")))
  WHERE ("pv"."terminada" = false);


ALTER TABLE "public"."prescricao_horarios" OWNER TO "postgres";


ALTER TABLE "public"."prescricao" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."prescricao_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."prescricao_tarefa" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."prescricao_tarefa_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."prescricao_tarefa_view" WITH ("security_invoker"='true') AS
 SELECT "pt"."concluida",
    "pt"."observacao",
    "pt"."dia",
    "pt"."hora",
    "pv"."animal",
    "pv"."animal_nome",
    "pv"."medicamento_nome"
   FROM ("public"."prescricao_tarefa" "pt"
     JOIN "public"."prescricao_view" "pv" ON (("pt"."prescricao" = "pv"."id")))
  ORDER BY "pt"."dia", "pv"."animal";


ALTER TABLE "public"."prescricao_tarefa_view" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."prescricao_tarefas_resumo" WITH ("security_invoker"='true') AS
 SELECT "prescricao_tarefa_view"."dia",
    "count"(DISTINCT "prescricao_tarefa_view"."animal") AS "quantidade_animais",
    "count"(
        CASE
            WHEN "prescricao_tarefa_view"."concluida" THEN 1
            ELSE NULL::integer
        END) AS "quantidade_concluidas",
    "count"(
        CASE
            WHEN (NOT "prescricao_tarefa_view"."concluida") THEN 1
            ELSE NULL::integer
        END) AS "quantidade_nao_concluidas",
    "round"(((("count"(
        CASE
            WHEN "prescricao_tarefa_view"."concluida" THEN 1
            ELSE NULL::integer
        END))::numeric * 100.0) / (NULLIF("count"(*), 0))::numeric), 0) AS "percentual_conclusao"
   FROM "public"."prescricao_tarefa_view"
  GROUP BY "prescricao_tarefa_view"."dia"
  ORDER BY "prescricao_tarefa_view"."dia";


ALTER TABLE "public"."prescricao_tarefas_resumo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."prescricoes_receitas_view" WITH ("security_invoker"='true') AS
 SELECT "receita"."id",
    "array_agg"("prescricao"."id") AS "prescricoes"
   FROM ("public"."receita"
     LEFT JOIN "public"."prescricao" ON (("prescricao"."receita" = "receita"."id")))
  GROUP BY "receita"."id";


ALTER TABLE "public"."prescricoes_receitas_view" OWNER TO "postgres";


ALTER TABLE "public"."receita" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."receita_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."receita_view" AS
SELECT
    NULL::bigint AS "id",
    NULL::"date" AS "data",
    NULL::"uuid" AS "veterinario",
    NULL::"uuid" AS "animal",
    NULL::"text" AS "animal_nome",
    NULL::"text" AS "veterinario_nome",
    NULL::"text"[] AS "medicamentos",
    NULL::boolean AS "finalizada",
    NULL::bigint AS "canil";


ALTER TABLE "public"."receita_view" OWNER TO "postgres";


ALTER TABLE "public"."registros" ALTER COLUMN "registro_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."registros_registro_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."registros_tipos" (
    "tipoRegistro" "text" NOT NULL,
    "indice" smallint,
    "icone" "text"
);


ALTER TABLE "public"."registros_tipos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."registros_view" AS
SELECT
    NULL::bigint AS "registro_id",
    NULL::"date" AS "data",
    NULL::"text" AS "tipo",
    NULL::"uuid" AS "veterinario_id",
    NULL::"text" AS "descricao",
    NULL::"uuid" AS "animal_id",
    NULL::"text" AS "clinica",
    NULL::boolean AS "pendente",
    NULL::timestamp without time zone AS "criado_em",
    NULL::"uuid" AS "criado_por",
    NULL::timestamp without time zone AS "previsto_data",
    NULL::timestamp without time zone AS "realizado_data",
    NULL::bigint AS "canil",
    NULL::"text" AS "nome_animal",
    NULL::"text" AS "nome_veterinario",
    NULL::bigint AS "num_arquivos",
    NULL::boolean AS "concluido",
    NULL::boolean AS "atrasado",
    NULL::boolean AS "programado",
    NULL::"date" AS "data_exibicao";


ALTER TABLE "public"."registros_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."resgates" (
    "id" bigint NOT NULL,
    "data" "date" NOT NULL,
    "animal" "uuid",
    "local" "text"
);


ALTER TABLE "public"."resgates" OWNER TO "postgres";


ALTER TABLE "public"."resgates" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."resgates_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."sexo" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."sexo_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."tarefa" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."tarefa_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."tarefa_tipo" (
    "tipo" "text" NOT NULL,
    "icone" "text"
);


ALTER TABLE "public"."tarefa_tipo" OWNER TO "postgres";


COMMENT ON TABLE "public"."tarefa_tipo" IS 'This is a duplicate of registros_tipos';



CREATE OR REPLACE VIEW "public"."tarefa_view" WITH ("security_invoker"='true') AS
 SELECT "t"."id",
    "t"."data_criada",
    "t"."data_prevista",
    "t"."data_realizada",
    "t"."descricao",
    "a"."nome" AS "animal_nome",
    "tt"."tipo" AS "tipo_tarefa"
   FROM (("public"."tarefa" "t"
     LEFT JOIN "public"."animais" "a" ON (("t"."animal" = "a"."animal_id")))
     LEFT JOIN "public"."tarefa_tipo" "tt" ON (("t"."tipo" = "tt"."tipo")));


ALTER TABLE "public"."tarefa_view" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."tmp_imunizacao_sem_registro" WITH ("security_invoker"='true') AS
 SELECT "a"."animal_id",
    "a"."nome" AS "animal_nome",
    "i"."id" AS "imunizacao_id",
    "t"."id" AS "tarefa_id",
    "r"."registro_id",
    "i"."tipo" AS "tipo_tarefa",
    "r"."tipo" AS "tipo_registro",
    "t"."data_prevista" AS "dp_tarefa",
    "r"."previsto_data" AS "dp_registro",
    "t"."data_realizada" AS "dr_tarefa",
    "r"."realizado_data" AS "dr_registro",
    "i"."observacao",
    "i"."veterinario",
    "i"."clinica",
    "i"."criacao"
   FROM ((("public"."imunizacao" "i"
     JOIN "public"."tarefa" "t" ON (("t"."id" = "i"."tarefa")))
     LEFT JOIN "public"."registros" "r" ON ((("r"."data" = '2025-04-04'::"date") AND ("r"."previsto_data" = "t"."data_prevista") AND ("r"."animal_id" = "i"."animal"))))
     JOIN "public"."animais" "a" ON (("a"."animal_id" = "i"."animal")))
  WHERE ("i"."tipo" = 'Vacinação'::"text")
  ORDER BY "a"."nome", "i"."id";


ALTER TABLE "public"."tmp_imunizacao_sem_registro" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."tratamentos_painel" AS
SELECT
    NULL::"uuid" AS "animal_id",
    NULL::"text" AS "nome",
    NULL::bigint AS "canil",
    NULL::bigint AS "quantidade";


ALTER TABLE "public"."tratamentos_painel" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."usuario_dados" WITH ("security_invoker"='true') AS
 SELECT "u"."user_id" AS "id",
    "u"."user_name" AS "nome",
    "u"."user_email" AS "email",
    "u"."foto",
    "c"."id" AS "canil_id",
    "c"."canil" AS "canil_nome",
    (EXISTS ( SELECT 1
           FROM "public"."veterinarios" "v"
          WHERE ("v"."usuario_id" = "u"."user_id"))) AS "vet"
   FROM ("public"."usuarios" "u"
     LEFT JOIN "public"."canis" "c" ON (("u"."user_id" = "c"."proprietario")));


ALTER TABLE "public"."usuario_dados" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vacinacoes" (
    "animal" "uuid",
    "data" "date" NOT NULL,
    "aplicada" boolean DEFAULT false,
    "tipo" "text",
    "vacina_id" bigint NOT NULL
);


ALTER TABLE "public"."vacinacoes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vacinacoes_pendentes" WITH ("security_invoker"='true') AS
 SELECT "a"."animal_id" AS "id",
    "a"."nome",
    "a"."canil"
   FROM ("public"."animais" "a"
     LEFT JOIN "public"."imunizacao_view" "iv" ON ((("a"."animal_id" = "iv"."animal") AND ("iv"."tipo" = 'Vacinação'::"text"))))
  WHERE (("iv"."animal" IS NULL) AND ("a"."adotado" = false) AND ("a"."falecido" = false) AND ("a"."desaparecido" = false));


ALTER TABLE "public"."vacinacoes_pendentes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vacinacoes_view" WITH ("security_invoker"='true') AS
 SELECT "vacinacoes"."animal",
    "vacinacoes"."data",
    "vacinacoes"."aplicada",
    "vacinacoes"."tipo",
    "vacinacoes"."vacina_id",
    "animais"."nome" AS "animal_nome"
   FROM ("public"."vacinacoes"
     LEFT JOIN "public"."animais" ON (("animais"."animal_id" = "vacinacoes"."animal")));


ALTER TABLE "public"."vacinacoes_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vacinas_tipos" (
    "tipoVacina" "text" NOT NULL,
    "especie" "text",
    "canil_id" bigint
);


ALTER TABLE "public"."vacinas_tipos" OWNER TO "postgres";


COMMENT ON TABLE "public"."vacinas_tipos" IS 'This is a duplicate of tipos_registro';



ALTER TABLE "public"."vacinacoes" ALTER COLUMN "vacina_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."vacinas_vacina_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."document_rows" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."document_rows_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."n8n_chat_histories" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."n8n_chat_histories_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."anamneses_registros"
    ADD CONSTRAINT "anamneses_registros_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."animais_descricao"
    ADD CONSTRAINT "animais_descricao_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."animais_descricao"
    ADD CONSTRAINT "animais_descricao_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_pkey" PRIMARY KEY ("animal_id");



ALTER TABLE ONLY "public"."arquivos"
    ADD CONSTRAINT "arquivos_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."arquivos"
    ADD CONSTRAINT "arquivos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."canil_tratador"
    ADD CONSTRAINT "canil_tratador_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."canis"
    ADD CONSTRAINT "canis_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."canis_membros"
    ADD CONSTRAINT "canis_responsaveis_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."caracteristicas"
    ADD CONSTRAINT "caracteristicas_pkey" PRIMARY KEY ("caracteristica");



ALTER TABLE ONLY "public"."clinicas"
    ADD CONSTRAINT "clinicas_pkey" PRIMARY KEY ("clinica");



ALTER TABLE ONLY "public"."diagnostico"
    ADD CONSTRAINT "condicao_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."condicoes_parametro"
    ADD CONSTRAINT "condicoes_parametro_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."condicoes_parametro"
    ADD CONSTRAINT "condicoes_parametro_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conexao_registro"
    ADD CONSTRAINT "conexao_registro_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conexao_status"
    ADD CONSTRAINT "conexao_status_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cores"
    ADD CONSTRAINT "cores_pkey" PRIMARY KEY ("cor");



ALTER TABLE ONLY "public"."document_metadata"
    ADD CONSTRAINT "document_metadata_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."document_rows"
    ADD CONSTRAINT "document_rows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."documents"
    ADD CONSTRAINT "documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."escolaridade"
    ADD CONSTRAINT "escolaridade_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."especies"
    ADD CONSTRAINT "especies_pkey" PRIMARY KEY ("especie");



ALTER TABLE ONLY "public"."generos"
    ADD CONSTRAINT "generos_pkey" PRIMARY KEY ("genero");



ALTER TABLE ONLY "public"."idades"
    ADD CONSTRAINT "idades_pkey" PRIMARY KEY ("idade");



ALTER TABLE ONLY "public"."imunizacao"
    ADD CONSTRAINT "imunizacao_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."imunizacao_tipo"
    ADD CONSTRAINT "imunizacao_tipo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."imunizante"
    ADD CONSTRAINT "imunizante_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."interessado_animal"
    ADD CONSTRAINT "interessado_animal_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."questionario"
    ADD CONSTRAINT "interessados_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conexao"
    ADD CONSTRAINT "interesse_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medicacao_falhas"
    ADD CONSTRAINT "medicacao_falhas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medicamento_dosagem"
    ADD CONSTRAINT "medicamento_forma_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medicamento"
    ADD CONSTRAINT "medicamento_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medicamento_via"
    ADD CONSTRAINT "medicamento_via_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medidas"
    ADD CONSTRAINT "medidas_pkey" PRIMARY KEY ("medida_id");



ALTER TABLE ONLY "public"."moradia_tipos"
    ADD CONSTRAINT "moradia_tipos_pkey" PRIMARY KEY ("tipo_moradia");



ALTER TABLE ONLY "public"."n8n_chat_histories"
    ADD CONSTRAINT "n8n_chat_histories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."parametros_anamnese"
    ADD CONSTRAINT "parametros_anamnese_pkey" PRIMARY KEY ("parametro");



ALTER TABLE ONLY "public"."pelagens"
    ADD CONSTRAINT "pelagens_pkey" PRIMARY KEY ("pelagem");



ALTER TABLE ONLY "public"."pesagens"
    ADD CONSTRAINT "pesagens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pessoa"
    ADD CONSTRAINT "pessoa_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."pessoa_likes"
    ADD CONSTRAINT "pessoa_likes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pessoa"
    ADD CONSTRAINT "pessoa_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."portes"
    ADD CONSTRAINT "portes_pkey" PRIMARY KEY ("porte");



ALTER TABLE ONLY "public"."prescricao"
    ADD CONSTRAINT "prescricao_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prescricao_tarefa"
    ADD CONSTRAINT "prescricao_tarefa_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."racas"
    ADD CONSTRAINT "racas_pkey" PRIMARY KEY ("raca");



ALTER TABLE ONLY "public"."racas"
    ADD CONSTRAINT "racas_raca_nome_key" UNIQUE ("raca");



ALTER TABLE ONLY "public"."receita"
    ADD CONSTRAINT "receita_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."registros_tipos"
    ADD CONSTRAINT "registro_tipos_pkey" PRIMARY KEY ("tipoRegistro");



ALTER TABLE ONLY "public"."registros"
    ADD CONSTRAINT "registros_pkey" PRIMARY KEY ("registro_id");



ALTER TABLE ONLY "public"."resgates"
    ADD CONSTRAINT "resgates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sexo"
    ADD CONSTRAINT "sexo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tarefa"
    ADD CONSTRAINT "tarefa_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tarefa_tipo"
    ADD CONSTRAINT "tarefa_tipo_pkey" PRIMARY KEY ("tipo");



ALTER TABLE ONLY "public"."vacinas_tipos"
    ADD CONSTRAINT "tipos_vacina_pkey" PRIMARY KEY ("tipoVacina");



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_user_email_key" UNIQUE ("user_email");



ALTER TABLE ONLY "public"."vacinacoes"
    ADD CONSTRAINT "vacinas_pkey" PRIMARY KEY ("vacina_id");



ALTER TABLE ONLY "public"."vacinacoes"
    ADD CONSTRAINT "vacinas_vacina_id_key" UNIQUE ("vacina_id");



ALTER TABLE ONLY "public"."veterinarios"
    ADD CONSTRAINT "veterinarios_pkey" PRIMARY KEY ("vet_id");



CREATE INDEX "documents_embedding_idx" ON "public"."documents" USING "hnsw" ("embedding" "public"."vector_ip_ops");



CREATE INDEX "documents_fts_idx" ON "public"."documents" USING "gin" ("fts");



CREATE OR REPLACE VIEW "public"."receita_view" WITH ("security_invoker"='true') AS
 SELECT "receita"."id",
    "receita"."data",
    "receita"."veterinario",
    "receita"."animal",
    "animais"."nome" AS "animal_nome",
    "veterinarios"."nome" AS "veterinario_nome",
    COALESCE("array_agg"("medicamento"."nome"), '{}'::"text"[]) AS "medicamentos",
    COALESCE("bool_and"("prescricao_view"."terminada"), false) AS "finalizada",
    "animais"."canil"
   FROM (((("public"."receita"
     LEFT JOIN "public"."animais" ON (("receita"."animal" = "animais"."animal_id")))
     LEFT JOIN "public"."veterinarios" ON (("receita"."veterinario" = "veterinarios"."vet_id")))
     LEFT JOIN "public"."prescricao_view" ON (("receita"."id" = "prescricao_view"."receita")))
     LEFT JOIN "public"."medicamento" ON (("prescricao_view"."medicamento" = "medicamento"."id")))
  GROUP BY "receita"."id", "animais"."nome", "veterinarios"."nome", "animais"."canil";



CREATE OR REPLACE VIEW "public"."registros_view" WITH ("security_invoker"='true') AS
 SELECT "registros"."registro_id",
    "registros"."data",
    "registros"."tipo",
    "registros"."veterinario_id",
    "registros"."descricao",
    "registros"."animal_id",
    "registros"."clinica",
    "registros"."pendente",
    "registros"."criado_em",
    "registros"."criado_por",
    "registros"."previsto_data",
    "registros"."realizado_data",
    "animais"."canil",
    "animais"."nome" AS "nome_animal",
    COALESCE("veterinarios"."nome", ''::"text") AS "nome_veterinario",
    ( SELECT "count"(*) AS "count"
           FROM "public"."arquivos"
          WHERE ("arquivos"."registro" = "registros"."registro_id")) AS "num_arquivos",
    ("registros"."realizado_data" IS NOT NULL) AS "concluido",
    (("registros"."realizado_data" IS NULL) AND ("registros"."previsto_data" <= CURRENT_DATE)) AS "atrasado",
    (("registros"."realizado_data" IS NULL) AND ("registros"."previsto_data" > CURRENT_DATE)) AS "programado",
    (COALESCE(COALESCE("registros"."realizado_data", "registros"."previsto_data"), ("registros"."data")::timestamp without time zone))::"date" AS "data_exibicao"
   FROM (("public"."registros"
     LEFT JOIN "public"."animais" ON (("registros"."animal_id" = "animais"."animal_id")))
     LEFT JOIN "public"."veterinarios" ON (("registros"."veterinario_id" = "veterinarios"."vet_id")))
  GROUP BY "registros"."registro_id", "animais"."nome", "animais"."canil", "veterinarios"."nome";



CREATE OR REPLACE VIEW "public"."tratamentos_painel" WITH ("security_invoker"='true') AS
 SELECT "a"."animal_id",
    "a"."nome",
    "a"."canil",
    "count"("pd"."id") AS "quantidade"
   FROM ("public"."prescricao_diaria" "pd"
     JOIN "public"."animais" "a" ON (("pd"."animal" = "a"."animal_id")))
  WHERE (("pd"."terminada" = false) AND ("a"."falecido" = false) AND ("a"."desaparecido" = false) AND ("a"."adotado" = false))
  GROUP BY "a"."animal_id";



CREATE OR REPLACE VIEW "public"."animal_painel" WITH ("security_invoker"='true') AS
 WITH "imunizacao" AS (
         SELECT "a"."animal_id",
            "a"."falecido",
            "a"."desaparecido",
            COALESCE("max"("iv"."data_realizada") FILTER (WHERE ("iv"."tipo" = 'Vacinação'::"text")), NULL::"date") AS "vacina_anterior",
            COALESCE("min"("iv"."data_prevista") FILTER (WHERE (("iv"."data_prevista" > CURRENT_DATE) AND ("iv"."tipo" = 'Vacinação'::"text"))), NULL::"date") AS "vacina_proxima",
            COALESCE("max"("iv"."data_realizada") FILTER (WHERE ("iv"."tipo" = 'Vermifugação'::"text")), NULL::"date") AS "vermifugo_anterior",
            COALESCE("min"("iv"."data_prevista") FILTER (WHERE (("iv"."data_prevista" > CURRENT_DATE) AND ("iv"."tipo" = 'Vermifugação'::"text"))), NULL::"date") AS "vermifugo_proximo",
            COALESCE("max"("iv"."data_realizada") FILTER (WHERE ("iv"."tipo" = 'Desparasitação'::"text")), NULL::"date") AS "desparasitacao_anterior",
            COALESCE("min"("iv"."data_prevista") FILTER (WHERE (("iv"."data_prevista" > CURRENT_DATE) AND ("iv"."tipo" = 'Desparasitação'::"text"))), NULL::"date") AS "desparasitacao_proximo"
           FROM ("public"."animais" "a"
             LEFT JOIN "public"."imunizacao_view" "iv" ON (("a"."animal_id" = "iv"."animal")))
          GROUP BY "a"."animal_id"
        ), "avaliacao" AS (
         SELECT "ar"."animal",
            "ar"."data",
            "ar"."score",
            "ar"."nota",
            "ar"."condicoes",
            "ar"."observacao"
           FROM ("public"."anamneses_view" "ar"
             JOIN ( SELECT "anamneses_view"."animal",
                    "max"("anamneses_view"."data") AS "max_data"
                   FROM "public"."anamneses_view"
                  GROUP BY "anamneses_view"."animal") "max_data_per_animal" ON ((("ar"."animal" = "max_data_per_animal"."animal") AND ("ar"."data" = "max_data_per_animal"."max_data"))))
          ORDER BY "ar"."animal"
        ), "pesagens" AS (
         SELECT "p"."animal",
            "p"."data",
            "p"."peso",
            "lag"("p"."peso") OVER (PARTITION BY "p"."animal" ORDER BY "p"."data") AS "peso_anterior",
            "p"."peso" AS "peso_atual"
           FROM "public"."pesagens_view" "p"
        )
 SELECT "i"."animal_id",
    "i"."vacina_anterior",
    "i"."vacina_proxima",
    COALESCE((CURRENT_DATE - "i"."vacina_anterior"), NULL::integer) AS "vacina_anterior_dias",
    COALESCE(("i"."vacina_proxima" - CURRENT_DATE), NULL::integer) AS "vacina_proxima_dias",
    "i"."vermifugo_anterior",
    "i"."vermifugo_proximo",
    COALESCE((CURRENT_DATE - "i"."vermifugo_anterior"), NULL::integer) AS "vermifugo_anterior_dias",
    COALESCE(("i"."vermifugo_proximo" - CURRENT_DATE), NULL::integer) AS "vermifugo_proxima_dias",
    "i"."desparasitacao_anterior",
    "i"."desparasitacao_proximo",
    COALESCE((CURRENT_DATE - "i"."desparasitacao_anterior"), NULL::integer) AS "desparasitacao_anterior_dias",
    COALESCE(("i"."desparasitacao_proximo" - CURRENT_DATE), NULL::integer) AS "desparasitacao_proxima_dias",
    "av"."data" AS "avaliacao_data",
    "av"."score" AS "score_ultimo",
    "av"."nota" AS "saude_indice",
    "av"."condicoes",
    COALESCE((CURRENT_DATE - "av"."data"), NULL::integer) AS "avaliacao_dias",
    "av"."observacao",
    ( SELECT "p"."data"
           FROM "public"."pesagens_view" "p"
          WHERE ("p"."animal" = "i"."animal_id")
          ORDER BY "p"."data" DESC
         LIMIT 1) AS "peso_data",
    ( SELECT "p"."anterior"
           FROM "public"."pesagens_view" "p"
          WHERE ("p"."animal" = "i"."animal_id")
          ORDER BY "p"."data" DESC
         LIMIT 1) AS "peso_anterior",
    ( SELECT "p"."peso"
           FROM "public"."pesagens_view" "p"
          WHERE ("p"."animal" = "i"."animal_id")
          ORDER BY "p"."data" DESC
         LIMIT 1) AS "peso_atual",
    ( SELECT (("pesagens"."peso_atual" - "pesagens"."peso_anterior") / NULLIF("pesagens"."peso_anterior", (0)::double precision))
           FROM "pesagens"
          WHERE ("pesagens"."animal" = "i"."animal_id")
          ORDER BY "pesagens"."data" DESC
         LIMIT 1) AS "peso_variacao"
   FROM ("imunizacao" "i"
     LEFT JOIN "avaliacao" "av" ON (("av"."animal" = "i"."animal_id")));



ALTER TABLE ONLY "public"."anamneses_registros"
    ADD CONSTRAINT "anamneses_registros_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."anamneses_registros"
    ADD CONSTRAINT "anamneses_registros_pesagem_fkey" FOREIGN KEY ("pesagem") REFERENCES "public"."pesagens"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."anamneses_registros"
    ADD CONSTRAINT "anamneses_registros_veterinario_fkey" FOREIGN KEY ("veterinario") REFERENCES "public"."veterinarios"("vet_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_canil_fkey" FOREIGN KEY ("canil") REFERENCES "public"."canis"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_cor_fkey" FOREIGN KEY ("cor") REFERENCES "public"."cores"("cor");



ALTER TABLE ONLY "public"."animais_descricao"
    ADD CONSTRAINT "animais_descricao_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_especie_fkey" FOREIGN KEY ("especie") REFERENCES "public"."especies"("especie");



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_faixaetaria_fkey" FOREIGN KEY ("faixaetaria") REFERENCES "public"."idades"("idade") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_genero_fkey" FOREIGN KEY ("genero") REFERENCES "public"."generos"("genero");



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_pelagem_fkey" FOREIGN KEY ("pelagem") REFERENCES "public"."pelagens"("pelagem");



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_porte_fkey" FOREIGN KEY ("porte") REFERENCES "public"."portes"("porte") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."animais"
    ADD CONSTRAINT "animais_raça_fkey" FOREIGN KEY ("raça") REFERENCES "public"."racas"("raca");



ALTER TABLE ONLY "public"."arquivos"
    ADD CONSTRAINT "arquivos_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."arquivos"
    ADD CONSTRAINT "arquivos_registro_fkey" FOREIGN KEY ("registro") REFERENCES "public"."registros"("registro_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."canil_tratador"
    ADD CONSTRAINT "canil_tratador_canil_fkey" FOREIGN KEY ("canil") REFERENCES "public"."canis"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."canis"
    ADD CONSTRAINT "canis_proprietario_fkey" FOREIGN KEY ("proprietario") REFERENCES "public"."usuarios"("user_id");



ALTER TABLE ONLY "public"."canis_membros"
    ADD CONSTRAINT "canis_responsaveis_canil_fkey" FOREIGN KEY ("canil") REFERENCES "public"."canis"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."canis_membros"
    ADD CONSTRAINT "canis_responsaveis_responsavel_fkey" FOREIGN KEY ("membro") REFERENCES "public"."usuarios"("user_id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."clinicas"
    ADD CONSTRAINT "clinicas_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."condicoes_parametro"
    ADD CONSTRAINT "condicoes_parametro_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."condicoes_parametro"
    ADD CONSTRAINT "condicoes_parametro_parametro_fkey" FOREIGN KEY ("parametro") REFERENCES "public"."parametros_anamnese"("parametro") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."conexao_registro"
    ADD CONSTRAINT "conexao_registro_status_fkey" FOREIGN KEY ("status") REFERENCES "public"."conexao_status"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cores"
    ADD CONSTRAINT "cores_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."diagnostico"
    ADD CONSTRAINT "diagnostico_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."diagnostico"
    ADD CONSTRAINT "diagnostico_especie_fkey" FOREIGN KEY ("especie") REFERENCES "public"."especies"("especie") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."document_rows"
    ADD CONSTRAINT "document_rows_dataset_id_fkey" FOREIGN KEY ("dataset_id") REFERENCES "public"."document_metadata"("id");



ALTER TABLE ONLY "public"."especies"
    ADD CONSTRAINT "especies_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."imunizacao"
    ADD CONSTRAINT "imunizacao_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizacao"
    ADD CONSTRAINT "imunizacao_clinica_fkey" FOREIGN KEY ("clinica") REFERENCES "public"."clinicas"("clinica") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizacao"
    ADD CONSTRAINT "imunizacao_imunizante_fkey" FOREIGN KEY ("imunizante") REFERENCES "public"."imunizante"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizacao"
    ADD CONSTRAINT "imunizacao_registro_fkey" FOREIGN KEY ("registro") REFERENCES "public"."registros"("registro_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizacao"
    ADD CONSTRAINT "imunizacao_tarefa_fkey" FOREIGN KEY ("tarefa") REFERENCES "public"."tarefa"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizacao_tipo"
    ADD CONSTRAINT "imunizacao_tipo_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."imunizacao"
    ADD CONSTRAINT "imunizacao_tipo_fkey" FOREIGN KEY ("tipo") REFERENCES "public"."imunizacao_tipo"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizacao"
    ADD CONSTRAINT "imunizacao_veterinario_fkey" FOREIGN KEY ("veterinario") REFERENCES "public"."veterinarios"("vet_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizante"
    ADD CONSTRAINT "imunizante_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."imunizante"
    ADD CONSTRAINT "imunizante_especie_fkey" FOREIGN KEY ("especie") REFERENCES "public"."especies"("especie") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizante"
    ADD CONSTRAINT "imunizante_imunizacao_tipo_fkey" FOREIGN KEY ("imunizacao_tipo") REFERENCES "public"."imunizacao_tipo"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."imunizante"
    ADD CONSTRAINT "imunizante_imunizacao_tipo_fkey1" FOREIGN KEY ("imunizacao_tipo") REFERENCES "public"."imunizacao_tipo"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."interessado_animal"
    ADD CONSTRAINT "interessado_animal_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."interessado_animal"
    ADD CONSTRAINT "interessado_animal_pessoa_fkey" FOREIGN KEY ("pessoa") REFERENCES "public"."questionario"("id");



ALTER TABLE ONLY "public"."questionario"
    ADD CONSTRAINT "interessados_moradia_tipo_fkey" FOREIGN KEY ("moradia_tipo") REFERENCES "public"."moradia_tipos"("tipo_moradia") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."conexao"
    ADD CONSTRAINT "interesse_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conexao"
    ADD CONSTRAINT "interesse_pessoa_fkey" FOREIGN KEY ("pessoa") REFERENCES "public"."pessoa"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medicamento"
    ADD CONSTRAINT "medicamento_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medidas"
    ADD CONSTRAINT "medidas_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id");



ALTER TABLE ONLY "public"."parametros_anamnese"
    ADD CONSTRAINT "parametros_anamnese_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pesagens"
    ADD CONSTRAINT "pesagens_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id");



ALTER TABLE ONLY "public"."pessoa"
    ADD CONSTRAINT "pessoa_escolaridade_fkey" FOREIGN KEY ("escolaridade") REFERENCES "public"."escolaridade"("id");



ALTER TABLE ONLY "public"."pessoa_likes"
    ADD CONSTRAINT "pessoa_likes_pessoa_id_fkey" FOREIGN KEY ("pessoa_id") REFERENCES "public"."pessoa"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pessoa_likes"
    ADD CONSTRAINT "pessoa_likes_usuario_fkey" FOREIGN KEY ("usuario") REFERENCES "public"."usuarios"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pessoa"
    ADD CONSTRAINT "pessoa_sexo_fkey" FOREIGN KEY ("sexo") REFERENCES "public"."sexo"("id");



ALTER TABLE ONLY "public"."pessoa"
    ADD CONSTRAINT "pessoa_usuario_fkey" FOREIGN KEY ("usuario") REFERENCES "public"."usuarios"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."prescricao"
    ADD CONSTRAINT "prescricao_medicamento_fkey" FOREIGN KEY ("medicamento") REFERENCES "public"."medicamento"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."prescricao"
    ADD CONSTRAINT "prescricao_receita_fkey" FOREIGN KEY ("receita") REFERENCES "public"."receita"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."prescricao_tarefa"
    ADD CONSTRAINT "prescricao_tarefa_pessoa_fkey" FOREIGN KEY ("pessoa") REFERENCES "public"."usuarios"("user_id");



ALTER TABLE ONLY "public"."prescricao_tarefa"
    ADD CONSTRAINT "prescricao_tarefa_prescricao_fkey" FOREIGN KEY ("prescricao") REFERENCES "public"."prescricao"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."questionario"
    ADD CONSTRAINT "questionario_pessoa_id_fkey" FOREIGN KEY ("pessoa_id") REFERENCES "public"."pessoa"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."racas"
    ADD CONSTRAINT "racas_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."racas"
    ADD CONSTRAINT "racas_especie_fkey" FOREIGN KEY ("especie") REFERENCES "public"."especies"("especie") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."receita"
    ADD CONSTRAINT "receita_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."receita"
    ADD CONSTRAINT "receita_veterinario_fkey" FOREIGN KEY ("veterinario") REFERENCES "public"."veterinarios"("vet_id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."registros"
    ADD CONSTRAINT "registros_animal_fkey" FOREIGN KEY ("animal_id") REFERENCES "public"."animais"("animal_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."registros"
    ADD CONSTRAINT "registros_clinica_fkey" FOREIGN KEY ("clinica") REFERENCES "public"."clinicas"("clinica");



ALTER TABLE ONLY "public"."registros"
    ADD CONSTRAINT "registros_criado_por_fkey" FOREIGN KEY ("criado_por") REFERENCES "public"."usuarios"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."registros"
    ADD CONSTRAINT "registros_tipo_fkey" FOREIGN KEY ("tipo") REFERENCES "public"."registros_tipos"("tipoRegistro") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."registros"
    ADD CONSTRAINT "registros_veterinario_fkey" FOREIGN KEY ("veterinario_id") REFERENCES "public"."veterinarios"("vet_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."resgates"
    ADD CONSTRAINT "resgates_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tarefa"
    ADD CONSTRAINT "tarefa_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tarefa"
    ADD CONSTRAINT "tarefa_tipo_fkey" FOREIGN KEY ("tipo") REFERENCES "public"."tarefa_tipo"("tipo") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vacinas_tipos"
    ADD CONSTRAINT "tipos_vacina_especie_fkey" FOREIGN KEY ("especie") REFERENCES "public"."especies"("especie") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vacinacoes"
    ADD CONSTRAINT "vacina_animal_fkey" FOREIGN KEY ("animal") REFERENCES "public"."animais"("animal_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vacinacoes"
    ADD CONSTRAINT "vacinacoes_tipo_fkey" FOREIGN KEY ("tipo") REFERENCES "public"."vacinas_tipos"("tipoVacina") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vacinas_tipos"
    ADD CONSTRAINT "vacinas_tipos_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."veterinarios"
    ADD CONSTRAINT "veterinarios_canil_id_fkey" FOREIGN KEY ("canil_id") REFERENCES "public"."canis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."veterinarios"
    ADD CONSTRAINT "veterinarios_id_usuario_fkey" FOREIGN KEY ("usuario_id") REFERENCES "public"."usuarios"("user_id");



CREATE POLICY "Enable read access for all users" ON "public"."anamneses_registros" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."arquivos" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."canil_tratador" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."canis" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."clinicas" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."conexao" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."conexao_registro" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."conexao_status" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."cores" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."diagnostico" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."escolaridade" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."especies" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."generos" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."idades" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."imunizacao" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."imunizacao_tipo" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."imunizante" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."medicacao_falhas" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."medicamento" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."medicamento_dosagem" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."medicamento_via" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."medidas" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."parametros_anamnese" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."pelagens" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."pesagens" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."pessoa" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."pessoa_likes" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."portes" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."prescricao" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."prescricao_tarefa" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."questionario" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."racas" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."receita" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."registros" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."registros_tipos" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."sexo" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."tarefa" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."tarefa_tipo" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."vacinacoes" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."veterinarios" USING (true);



CREATE POLICY "all" ON "public"."canis_membros" USING (true);



CREATE POLICY "all" ON "public"."resgates" USING (true);



CREATE POLICY "all" ON "public"."vacinas_tipos" USING (true);



ALTER TABLE "public"."anamneses_registros" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."animais" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "animais.all" ON "public"."animais" USING (true);



ALTER TABLE "public"."animais_descricao" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."arquivos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."canil_tratador" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."canis" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."canis_membros" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."caracteristicas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."clinicas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."condicoes_parametro" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."conexao" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."conexao_registro" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."conexao_status" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cores" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."diagnostico" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."escolaridade" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."especies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."generos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."idades" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."imunizacao" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."imunizacao_tipo" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."imunizante" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."interessado_animal" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "liberado" ON "public"."condicoes_parametro" USING (true);



CREATE POLICY "liberado" ON "public"."interessado_animal" USING (true);



CREATE POLICY "liberado" ON "public"."moradia_tipos" USING (true);



ALTER TABLE "public"."medicacao_falhas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medicamento" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medicamento_dosagem" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medicamento_via" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medidas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."moradia_tipos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."n8n_chat_histories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."parametros_anamnese" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pelagens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pesagens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pessoa" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pessoa_likes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."portes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prescricao" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prescricao_tarefa" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."questionario" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."racas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."receita" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."registros" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."registros_tipos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."resgates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sexo" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tarefa" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tarefa_tipo" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."usuarios" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "usuarios.all" ON "public"."usuarios" USING (true);



ALTER TABLE "public"."vacinacoes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vacinas_tipos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."veterinarios" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."get_prescricao_horarios"("p_dia" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_prescricao_horarios"("p_dia" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_prescricao_horarios"("p_dia" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_prescricoes_ativas"("p_data" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_prescricoes_ativas"("p_data" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_prescricoes_ativas"("p_data" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."hybrid_search"("query_text" "text", "query_embedding" "public"."vector", "match_count" integer, "full_text_weight" double precision, "semantic_weight" double precision, "rrf_k" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."hybrid_search"("query_text" "text", "query_embedding" "public"."vector", "match_count" integer, "full_text_weight" double precision, "semantic_weight" double precision, "rrf_k" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hybrid_search"("query_text" "text", "query_embedding" "public"."vector", "match_count" integer, "full_text_weight" double precision, "semantic_weight" double precision, "rrf_k" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_count" integer, "filter" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_count" integer, "filter" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "match_count" integer, "filter" "jsonb") TO "service_role";



GRANT ALL ON TABLE "public"."animais" TO "anon";
GRANT ALL ON TABLE "public"."animais" TO "authenticated";
GRANT ALL ON TABLE "public"."animais" TO "service_role";



GRANT ALL ON TABLE "public"."canis" TO "anon";
GRANT ALL ON TABLE "public"."canis" TO "authenticated";
GRANT ALL ON TABLE "public"."canis" TO "service_role";



GRANT ALL ON TABLE "public"."_n8n_animais" TO "anon";
GRANT ALL ON TABLE "public"."_n8n_animais" TO "authenticated";
GRANT ALL ON TABLE "public"."_n8n_animais" TO "service_role";



GRANT ALL ON TABLE "public"."animais_descricao" TO "anon";
GRANT ALL ON TABLE "public"."animais_descricao" TO "authenticated";
GRANT ALL ON TABLE "public"."animais_descricao" TO "service_role";



GRANT ALL ON TABLE "public"."pesagens" TO "anon";
GRANT ALL ON TABLE "public"."pesagens" TO "authenticated";
GRANT ALL ON TABLE "public"."pesagens" TO "service_role";



GRANT ALL ON TABLE "public"."animais_detalhes" TO "anon";
GRANT ALL ON TABLE "public"."animais_detalhes" TO "authenticated";
GRANT ALL ON TABLE "public"."animais_detalhes" TO "service_role";



GRANT ALL ON TABLE "public"."especies" TO "anon";
GRANT ALL ON TABLE "public"."especies" TO "authenticated";
GRANT ALL ON TABLE "public"."especies" TO "service_role";



GRANT ALL ON TABLE "public"."animal_status" TO "anon";
GRANT ALL ON TABLE "public"."animal_status" TO "authenticated";
GRANT ALL ON TABLE "public"."animal_status" TO "service_role";



GRANT ALL ON TABLE "public"."_n8n_animais_dados" TO "anon";
GRANT ALL ON TABLE "public"."_n8n_animais_dados" TO "authenticated";
GRANT ALL ON TABLE "public"."_n8n_animais_dados" TO "service_role";



GRANT ALL ON TABLE "public"."_n8n_animais_site" TO "anon";
GRANT ALL ON TABLE "public"."_n8n_animais_site" TO "authenticated";
GRANT ALL ON TABLE "public"."_n8n_animais_site" TO "service_role";



GRANT ALL ON TABLE "public"."cores" TO "anon";
GRANT ALL ON TABLE "public"."cores" TO "authenticated";
GRANT ALL ON TABLE "public"."cores" TO "service_role";



GRANT ALL ON TABLE "public"."generos" TO "anon";
GRANT ALL ON TABLE "public"."generos" TO "authenticated";
GRANT ALL ON TABLE "public"."generos" TO "service_role";



GRANT ALL ON TABLE "public"."idades" TO "anon";
GRANT ALL ON TABLE "public"."idades" TO "authenticated";
GRANT ALL ON TABLE "public"."idades" TO "service_role";



GRANT ALL ON TABLE "public"."pelagens" TO "anon";
GRANT ALL ON TABLE "public"."pelagens" TO "authenticated";
GRANT ALL ON TABLE "public"."pelagens" TO "service_role";



GRANT ALL ON TABLE "public"."portes" TO "anon";
GRANT ALL ON TABLE "public"."portes" TO "authenticated";
GRANT ALL ON TABLE "public"."portes" TO "service_role";



GRANT ALL ON TABLE "public"."racas" TO "anon";
GRANT ALL ON TABLE "public"."racas" TO "authenticated";
GRANT ALL ON TABLE "public"."racas" TO "service_role";



GRANT ALL ON TABLE "public"."_n8n_caracteristicas" TO "anon";
GRANT ALL ON TABLE "public"."_n8n_caracteristicas" TO "authenticated";
GRANT ALL ON TABLE "public"."_n8n_caracteristicas" TO "service_role";



GRANT ALL ON TABLE "public"."medicamento" TO "anon";
GRANT ALL ON TABLE "public"."medicamento" TO "authenticated";
GRANT ALL ON TABLE "public"."medicamento" TO "service_role";



GRANT ALL ON TABLE "public"."prescricao" TO "anon";
GRANT ALL ON TABLE "public"."prescricao" TO "authenticated";
GRANT ALL ON TABLE "public"."prescricao" TO "service_role";



GRANT ALL ON TABLE "public"."receita" TO "anon";
GRANT ALL ON TABLE "public"."receita" TO "authenticated";
GRANT ALL ON TABLE "public"."receita" TO "service_role";



GRANT ALL ON TABLE "public"."veterinarios" TO "anon";
GRANT ALL ON TABLE "public"."veterinarios" TO "authenticated";
GRANT ALL ON TABLE "public"."veterinarios" TO "service_role";



GRANT ALL ON TABLE "public"."_n8n_prescricoes" TO "anon";
GRANT ALL ON TABLE "public"."_n8n_prescricoes" TO "authenticated";
GRANT ALL ON TABLE "public"."_n8n_prescricoes" TO "service_role";



GRANT ALL ON TABLE "public"."anamneses_registros" TO "anon";
GRANT ALL ON TABLE "public"."anamneses_registros" TO "authenticated";
GRANT ALL ON TABLE "public"."anamneses_registros" TO "service_role";



GRANT ALL ON SEQUENCE "public"."anamneses_registros_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."anamneses_registros_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."anamneses_registros_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."condicoes_parametro" TO "anon";
GRANT ALL ON TABLE "public"."condicoes_parametro" TO "authenticated";
GRANT ALL ON TABLE "public"."condicoes_parametro" TO "service_role";



GRANT ALL ON TABLE "public"."anamneses_view" TO "anon";
GRANT ALL ON TABLE "public"."anamneses_view" TO "authenticated";
GRANT ALL ON TABLE "public"."anamneses_view" TO "service_role";



GRANT ALL ON TABLE "public"."animais_dados" TO "anon";
GRANT ALL ON TABLE "public"."animais_dados" TO "authenticated";
GRANT ALL ON TABLE "public"."animais_dados" TO "service_role";



GRANT ALL ON SEQUENCE "public"."animais_descricao_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."animais_descricao_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."animais_descricao_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."animais_disponiveis" TO "anon";
GRANT ALL ON TABLE "public"."animais_disponiveis" TO "authenticated";
GRANT ALL ON TABLE "public"."animais_disponiveis" TO "service_role";



GRANT ALL ON SEQUENCE "public"."animais_idx_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."animais_idx_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."animais_idx_seq" TO "service_role";



GRANT ALL ON TABLE "public"."animais_quantidades" TO "anon";
GRANT ALL ON TABLE "public"."animais_quantidades" TO "authenticated";
GRANT ALL ON TABLE "public"."animais_quantidades" TO "service_role";



GRANT ALL ON TABLE "public"."animais_site" TO "anon";
GRANT ALL ON TABLE "public"."animais_site" TO "authenticated";
GRANT ALL ON TABLE "public"."animais_site" TO "service_role";



GRANT ALL ON TABLE "public"."animais_site_publico" TO "anon";
GRANT ALL ON TABLE "public"."animais_site_publico" TO "authenticated";
GRANT ALL ON TABLE "public"."animais_site_publico" TO "service_role";



GRANT ALL ON TABLE "public"."animal_condicoes" TO "anon";
GRANT ALL ON TABLE "public"."animal_condicoes" TO "authenticated";
GRANT ALL ON TABLE "public"."animal_condicoes" TO "service_role";



GRANT ALL ON TABLE "public"."diagnostico" TO "anon";
GRANT ALL ON TABLE "public"."diagnostico" TO "authenticated";
GRANT ALL ON TABLE "public"."diagnostico" TO "service_role";



GRANT ALL ON TABLE "public"."animal_diagnosticos" TO "anon";
GRANT ALL ON TABLE "public"."animal_diagnosticos" TO "authenticated";
GRANT ALL ON TABLE "public"."animal_diagnosticos" TO "service_role";



GRANT ALL ON TABLE "public"."animal_diagnosticos_lista" TO "anon";
GRANT ALL ON TABLE "public"."animal_diagnosticos_lista" TO "authenticated";
GRANT ALL ON TABLE "public"."animal_diagnosticos_lista" TO "service_role";



GRANT ALL ON TABLE "public"."animal_painel" TO "anon";
GRANT ALL ON TABLE "public"."animal_painel" TO "authenticated";
GRANT ALL ON TABLE "public"."animal_painel" TO "service_role";



GRANT ALL ON TABLE "public"."arquivos" TO "anon";
GRANT ALL ON TABLE "public"."arquivos" TO "authenticated";
GRANT ALL ON TABLE "public"."arquivos" TO "service_role";



GRANT ALL ON SEQUENCE "public"."arquivos_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."arquivos_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."arquivos_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."arquivos_view" TO "anon";
GRANT ALL ON TABLE "public"."arquivos_view" TO "authenticated";
GRANT ALL ON TABLE "public"."arquivos_view" TO "service_role";



GRANT ALL ON TABLE "public"."avaliacoes_antigas" TO "anon";
GRANT ALL ON TABLE "public"."avaliacoes_antigas" TO "authenticated";
GRANT ALL ON TABLE "public"."avaliacoes_antigas" TO "service_role";



GRANT ALL ON TABLE "public"."avaliacoes_painel" TO "anon";
GRANT ALL ON TABLE "public"."avaliacoes_painel" TO "authenticated";
GRANT ALL ON TABLE "public"."avaliacoes_painel" TO "service_role";



GRANT ALL ON TABLE "public"."canis_membros" TO "anon";
GRANT ALL ON TABLE "public"."canis_membros" TO "authenticated";
GRANT ALL ON TABLE "public"."canis_membros" TO "service_role";



GRANT ALL ON TABLE "public"."usuarios" TO "anon";
GRANT ALL ON TABLE "public"."usuarios" TO "authenticated";
GRANT ALL ON TABLE "public"."usuarios" TO "service_role";



GRANT ALL ON TABLE "public"."canil_prioritario" TO "anon";
GRANT ALL ON TABLE "public"."canil_prioritario" TO "authenticated";
GRANT ALL ON TABLE "public"."canil_prioritario" TO "service_role";



GRANT ALL ON TABLE "public"."canil_tratador" TO "anon";
GRANT ALL ON TABLE "public"."canil_tratador" TO "authenticated";
GRANT ALL ON TABLE "public"."canil_tratador" TO "service_role";



GRANT ALL ON SEQUENCE "public"."canil_tratador_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."canil_tratador_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."canil_tratador_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."canis_disponiveis" TO "anon";
GRANT ALL ON TABLE "public"."canis_disponiveis" TO "authenticated";
GRANT ALL ON TABLE "public"."canis_disponiveis" TO "service_role";



GRANT ALL ON TABLE "public"."canis_membros_view" TO "anon";
GRANT ALL ON TABLE "public"."canis_membros_view" TO "authenticated";
GRANT ALL ON TABLE "public"."canis_membros_view" TO "service_role";



GRANT ALL ON TABLE "public"."canis_disponiveis_usuario" TO "anon";
GRANT ALL ON TABLE "public"."canis_disponiveis_usuario" TO "authenticated";
GRANT ALL ON TABLE "public"."canis_disponiveis_usuario" TO "service_role";



GRANT ALL ON SEQUENCE "public"."canis_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."canis_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."canis_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."canis_responsaveis_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."canis_responsaveis_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."canis_responsaveis_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."canis_view" TO "anon";
GRANT ALL ON TABLE "public"."canis_view" TO "authenticated";
GRANT ALL ON TABLE "public"."canis_view" TO "service_role";



GRANT ALL ON TABLE "public"."caracteristicas" TO "anon";
GRANT ALL ON TABLE "public"."caracteristicas" TO "authenticated";
GRANT ALL ON TABLE "public"."caracteristicas" TO "service_role";



GRANT ALL ON SEQUENCE "public"."caracteristicas_caracteristica_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."caracteristicas_caracteristica_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."caracteristicas_caracteristica_seq" TO "service_role";



GRANT ALL ON TABLE "public"."castracao_pendente" TO "anon";
GRANT ALL ON TABLE "public"."castracao_pendente" TO "authenticated";
GRANT ALL ON TABLE "public"."castracao_pendente" TO "service_role";



GRANT ALL ON TABLE "public"."clinicas" TO "anon";
GRANT ALL ON TABLE "public"."clinicas" TO "authenticated";
GRANT ALL ON TABLE "public"."clinicas" TO "service_role";



GRANT ALL ON SEQUENCE "public"."condicoes_parametro_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."condicoes_parametro_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."condicoes_parametro_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."conexao" TO "anon";
GRANT ALL ON TABLE "public"."conexao" TO "authenticated";
GRANT ALL ON TABLE "public"."conexao" TO "service_role";



GRANT ALL ON TABLE "public"."conexao_registro" TO "anon";
GRANT ALL ON TABLE "public"."conexao_registro" TO "authenticated";
GRANT ALL ON TABLE "public"."conexao_registro" TO "service_role";



GRANT ALL ON SEQUENCE "public"."conexao_registro_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."conexao_registro_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."conexao_registro_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."conexao_status" TO "anon";
GRANT ALL ON TABLE "public"."conexao_status" TO "authenticated";
GRANT ALL ON TABLE "public"."conexao_status" TO "service_role";



GRANT ALL ON TABLE "public"."database_schema" TO "anon";
GRANT ALL ON TABLE "public"."database_schema" TO "authenticated";
GRANT ALL ON TABLE "public"."database_schema" TO "service_role";



GRANT ALL ON SEQUENCE "public"."diagnostico_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."diagnostico_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."diagnostico_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."document_metadata" TO "anon";
GRANT ALL ON TABLE "public"."document_metadata" TO "authenticated";
GRANT ALL ON TABLE "public"."document_metadata" TO "service_role";



GRANT ALL ON TABLE "public"."document_rows" TO "anon";
GRANT ALL ON TABLE "public"."document_rows" TO "authenticated";
GRANT ALL ON TABLE "public"."document_rows" TO "service_role";



GRANT ALL ON SEQUENCE "public"."document_rows_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."document_rows_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."document_rows_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."documents" TO "anon";
GRANT ALL ON TABLE "public"."documents" TO "authenticated";
GRANT ALL ON TABLE "public"."documents" TO "service_role";



GRANT ALL ON SEQUENCE "public"."documents_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."documents_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."documents_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."escolaridade" TO "anon";
GRANT ALL ON TABLE "public"."escolaridade" TO "authenticated";
GRANT ALL ON TABLE "public"."escolaridade" TO "service_role";



GRANT ALL ON TABLE "public"."export_animals" TO "anon";
GRANT ALL ON TABLE "public"."export_animals" TO "authenticated";
GRANT ALL ON TABLE "public"."export_animals" TO "service_role";



GRANT ALL ON TABLE "public"."export_breeds" TO "anon";
GRANT ALL ON TABLE "public"."export_breeds" TO "authenticated";
GRANT ALL ON TABLE "public"."export_breeds" TO "service_role";



GRANT ALL ON TABLE "public"."export_colors" TO "anon";
GRANT ALL ON TABLE "public"."export_colors" TO "authenticated";
GRANT ALL ON TABLE "public"."export_colors" TO "service_role";



GRANT ALL ON TABLE "public"."export_furs" TO "anon";
GRANT ALL ON TABLE "public"."export_furs" TO "authenticated";
GRANT ALL ON TABLE "public"."export_furs" TO "service_role";



GRANT ALL ON TABLE "public"."export_genders" TO "anon";
GRANT ALL ON TABLE "public"."export_genders" TO "authenticated";
GRANT ALL ON TABLE "public"."export_genders" TO "service_role";



GRANT ALL ON TABLE "public"."export_sizes" TO "anon";
GRANT ALL ON TABLE "public"."export_sizes" TO "authenticated";
GRANT ALL ON TABLE "public"."export_sizes" TO "service_role";



GRANT ALL ON TABLE "public"."export_species" TO "anon";
GRANT ALL ON TABLE "public"."export_species" TO "authenticated";
GRANT ALL ON TABLE "public"."export_species" TO "service_role";



GRANT ALL ON TABLE "public"."export_weights" TO "anon";
GRANT ALL ON TABLE "public"."export_weights" TO "authenticated";
GRANT ALL ON TABLE "public"."export_weights" TO "service_role";



GRANT ALL ON TABLE "public"."idades_view" TO "anon";
GRANT ALL ON TABLE "public"."idades_view" TO "authenticated";
GRANT ALL ON TABLE "public"."idades_view" TO "service_role";



GRANT ALL ON TABLE "public"."imunizacao" TO "anon";
GRANT ALL ON TABLE "public"."imunizacao" TO "authenticated";
GRANT ALL ON TABLE "public"."imunizacao" TO "service_role";



GRANT ALL ON SEQUENCE "public"."imunizacao_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."imunizacao_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."imunizacao_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."imunizacao_tipo" TO "anon";
GRANT ALL ON TABLE "public"."imunizacao_tipo" TO "authenticated";
GRANT ALL ON TABLE "public"."imunizacao_tipo" TO "service_role";



GRANT ALL ON TABLE "public"."imunizante" TO "anon";
GRANT ALL ON TABLE "public"."imunizante" TO "authenticated";
GRANT ALL ON TABLE "public"."imunizante" TO "service_role";



GRANT ALL ON TABLE "public"."tarefa" TO "anon";
GRANT ALL ON TABLE "public"."tarefa" TO "authenticated";
GRANT ALL ON TABLE "public"."tarefa" TO "service_role";



GRANT ALL ON TABLE "public"."imunizacao_view" TO "anon";
GRANT ALL ON TABLE "public"."imunizacao_view" TO "authenticated";
GRANT ALL ON TABLE "public"."imunizacao_view" TO "service_role";



GRANT ALL ON TABLE "public"."registros" TO "anon";
GRANT ALL ON TABLE "public"."registros" TO "authenticated";
GRANT ALL ON TABLE "public"."registros" TO "service_role";



GRANT ALL ON TABLE "public"."imunizacoes_view_2" TO "anon";
GRANT ALL ON TABLE "public"."imunizacoes_view_2" TO "authenticated";
GRANT ALL ON TABLE "public"."imunizacoes_view_2" TO "service_role";



GRANT ALL ON SEQUENCE "public"."imunizante_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."imunizante_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."imunizante_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."interessado_animal" TO "anon";
GRANT ALL ON TABLE "public"."interessado_animal" TO "authenticated";
GRANT ALL ON TABLE "public"."interessado_animal" TO "service_role";



GRANT ALL ON SEQUENCE "public"."interessado_animal_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."interessado_animal_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."interessado_animal_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."questionario" TO "anon";
GRANT ALL ON TABLE "public"."questionario" TO "authenticated";
GRANT ALL ON TABLE "public"."questionario" TO "service_role";



GRANT ALL ON SEQUENCE "public"."interessados_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."interessados_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."interessados_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."interesse_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."interesse_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."interesse_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."medicacao_falhas" TO "anon";
GRANT ALL ON TABLE "public"."medicacao_falhas" TO "authenticated";
GRANT ALL ON TABLE "public"."medicacao_falhas" TO "service_role";



GRANT ALL ON TABLE "public"."medicamento_dosagem" TO "anon";
GRANT ALL ON TABLE "public"."medicamento_dosagem" TO "authenticated";
GRANT ALL ON TABLE "public"."medicamento_dosagem" TO "service_role";



GRANT ALL ON SEQUENCE "public"."medicamento_dosagem_indice_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."medicamento_dosagem_indice_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."medicamento_dosagem_indice_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."medicamento_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."medicamento_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."medicamento_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."medicamento_via" TO "anon";
GRANT ALL ON TABLE "public"."medicamento_via" TO "authenticated";
GRANT ALL ON TABLE "public"."medicamento_via" TO "service_role";



GRANT ALL ON TABLE "public"."medicamento_view" TO "anon";
GRANT ALL ON TABLE "public"."medicamento_view" TO "authenticated";
GRANT ALL ON TABLE "public"."medicamento_view" TO "service_role";



GRANT ALL ON TABLE "public"."medidas" TO "anon";
GRANT ALL ON TABLE "public"."medidas" TO "authenticated";
GRANT ALL ON TABLE "public"."medidas" TO "service_role";



GRANT ALL ON SEQUENCE "public"."medidas_medida_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."medidas_medida_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."medidas_medida_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."moradia_tipos" TO "anon";
GRANT ALL ON TABLE "public"."moradia_tipos" TO "authenticated";
GRANT ALL ON TABLE "public"."moradia_tipos" TO "service_role";



GRANT ALL ON TABLE "public"."n8n_chat_histories" TO "anon";
GRANT ALL ON TABLE "public"."n8n_chat_histories" TO "authenticated";
GRANT ALL ON TABLE "public"."n8n_chat_histories" TO "service_role";



GRANT ALL ON SEQUENCE "public"."n8n_chat_histories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."n8n_chat_histories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."n8n_chat_histories_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."painel_avaliacoes" TO "anon";
GRANT ALL ON TABLE "public"."painel_avaliacoes" TO "authenticated";
GRANT ALL ON TABLE "public"."painel_avaliacoes" TO "service_role";



GRANT ALL ON TABLE "public"."parametros_anamnese" TO "anon";
GRANT ALL ON TABLE "public"."parametros_anamnese" TO "authenticated";
GRANT ALL ON TABLE "public"."parametros_anamnese" TO "service_role";



GRANT ALL ON SEQUENCE "public"."pesagens_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."pesagens_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."pesagens_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."pesagens_view" TO "anon";
GRANT ALL ON TABLE "public"."pesagens_view" TO "authenticated";
GRANT ALL ON TABLE "public"."pesagens_view" TO "service_role";



GRANT ALL ON TABLE "public"."pesagens_painel" TO "anon";
GRANT ALL ON TABLE "public"."pesagens_painel" TO "authenticated";
GRANT ALL ON TABLE "public"."pesagens_painel" TO "service_role";



GRANT ALL ON TABLE "public"."pessoa" TO "anon";
GRANT ALL ON TABLE "public"."pessoa" TO "authenticated";
GRANT ALL ON TABLE "public"."pessoa" TO "service_role";



GRANT ALL ON SEQUENCE "public"."pessoa_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."pessoa_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."pessoa_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."pessoa_likes" TO "anon";
GRANT ALL ON TABLE "public"."pessoa_likes" TO "authenticated";
GRANT ALL ON TABLE "public"."pessoa_likes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."pessoa_likes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."pessoa_likes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."pessoa_likes_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."pessoa_questionario_view" TO "anon";
GRANT ALL ON TABLE "public"."pessoa_questionario_view" TO "authenticated";
GRANT ALL ON TABLE "public"."pessoa_questionario_view" TO "service_role";



GRANT ALL ON TABLE "public"."sexo" TO "anon";
GRANT ALL ON TABLE "public"."sexo" TO "authenticated";
GRANT ALL ON TABLE "public"."sexo" TO "service_role";



GRANT ALL ON TABLE "public"."pessoa_view" TO "anon";
GRANT ALL ON TABLE "public"."pessoa_view" TO "authenticated";
GRANT ALL ON TABLE "public"."pessoa_view" TO "service_role";



GRANT ALL ON TABLE "public"."prescricao_tarefa" TO "anon";
GRANT ALL ON TABLE "public"."prescricao_tarefa" TO "authenticated";
GRANT ALL ON TABLE "public"."prescricao_tarefa" TO "service_role";



GRANT ALL ON TABLE "public"."prescricao_view" TO "anon";
GRANT ALL ON TABLE "public"."prescricao_view" TO "authenticated";
GRANT ALL ON TABLE "public"."prescricao_view" TO "service_role";



GRANT ALL ON TABLE "public"."prescricao_diaria" TO "anon";
GRANT ALL ON TABLE "public"."prescricao_diaria" TO "authenticated";
GRANT ALL ON TABLE "public"."prescricao_diaria" TO "service_role";



GRANT ALL ON TABLE "public"."prescricao_horarios" TO "anon";
GRANT ALL ON TABLE "public"."prescricao_horarios" TO "authenticated";
GRANT ALL ON TABLE "public"."prescricao_horarios" TO "service_role";



GRANT ALL ON SEQUENCE "public"."prescricao_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."prescricao_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."prescricao_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."prescricao_tarefa_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."prescricao_tarefa_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."prescricao_tarefa_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."prescricao_tarefa_view" TO "anon";
GRANT ALL ON TABLE "public"."prescricao_tarefa_view" TO "authenticated";
GRANT ALL ON TABLE "public"."prescricao_tarefa_view" TO "service_role";



GRANT ALL ON TABLE "public"."prescricao_tarefas_resumo" TO "anon";
GRANT ALL ON TABLE "public"."prescricao_tarefas_resumo" TO "authenticated";
GRANT ALL ON TABLE "public"."prescricao_tarefas_resumo" TO "service_role";



GRANT ALL ON TABLE "public"."prescricoes_receitas_view" TO "anon";
GRANT ALL ON TABLE "public"."prescricoes_receitas_view" TO "authenticated";
GRANT ALL ON TABLE "public"."prescricoes_receitas_view" TO "service_role";



GRANT ALL ON SEQUENCE "public"."receita_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."receita_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."receita_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."receita_view" TO "anon";
GRANT ALL ON TABLE "public"."receita_view" TO "authenticated";
GRANT ALL ON TABLE "public"."receita_view" TO "service_role";



GRANT ALL ON SEQUENCE "public"."registros_registro_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."registros_registro_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."registros_registro_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."registros_tipos" TO "anon";
GRANT ALL ON TABLE "public"."registros_tipos" TO "authenticated";
GRANT ALL ON TABLE "public"."registros_tipos" TO "service_role";



GRANT ALL ON TABLE "public"."registros_view" TO "anon";
GRANT ALL ON TABLE "public"."registros_view" TO "authenticated";
GRANT ALL ON TABLE "public"."registros_view" TO "service_role";



GRANT ALL ON TABLE "public"."resgates" TO "anon";
GRANT ALL ON TABLE "public"."resgates" TO "authenticated";
GRANT ALL ON TABLE "public"."resgates" TO "service_role";



GRANT ALL ON SEQUENCE "public"."resgates_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."resgates_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."resgates_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."sexo_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."sexo_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."sexo_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."tarefa_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."tarefa_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tarefa_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."tarefa_tipo" TO "anon";
GRANT ALL ON TABLE "public"."tarefa_tipo" TO "authenticated";
GRANT ALL ON TABLE "public"."tarefa_tipo" TO "service_role";



GRANT ALL ON TABLE "public"."tarefa_view" TO "anon";
GRANT ALL ON TABLE "public"."tarefa_view" TO "authenticated";
GRANT ALL ON TABLE "public"."tarefa_view" TO "service_role";



GRANT ALL ON TABLE "public"."tmp_imunizacao_sem_registro" TO "anon";
GRANT ALL ON TABLE "public"."tmp_imunizacao_sem_registro" TO "authenticated";
GRANT ALL ON TABLE "public"."tmp_imunizacao_sem_registro" TO "service_role";



GRANT ALL ON TABLE "public"."tratamentos_painel" TO "anon";
GRANT ALL ON TABLE "public"."tratamentos_painel" TO "authenticated";
GRANT ALL ON TABLE "public"."tratamentos_painel" TO "service_role";



GRANT ALL ON TABLE "public"."usuario_dados" TO "anon";
GRANT ALL ON TABLE "public"."usuario_dados" TO "authenticated";
GRANT ALL ON TABLE "public"."usuario_dados" TO "service_role";



GRANT ALL ON TABLE "public"."vacinacoes" TO "anon";
GRANT ALL ON TABLE "public"."vacinacoes" TO "authenticated";
GRANT ALL ON TABLE "public"."vacinacoes" TO "service_role";



GRANT ALL ON TABLE "public"."vacinacoes_pendentes" TO "anon";
GRANT ALL ON TABLE "public"."vacinacoes_pendentes" TO "authenticated";
GRANT ALL ON TABLE "public"."vacinacoes_pendentes" TO "service_role";



GRANT ALL ON TABLE "public"."vacinacoes_view" TO "anon";
GRANT ALL ON TABLE "public"."vacinacoes_view" TO "authenticated";
GRANT ALL ON TABLE "public"."vacinacoes_view" TO "service_role";



GRANT ALL ON TABLE "public"."vacinas_tipos" TO "anon";
GRANT ALL ON TABLE "public"."vacinas_tipos" TO "authenticated";
GRANT ALL ON TABLE "public"."vacinas_tipos" TO "service_role";



GRANT ALL ON SEQUENCE "public"."vacinas_vacina_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."vacinas_vacina_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."vacinas_vacina_id_seq" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






RESET ALL;
