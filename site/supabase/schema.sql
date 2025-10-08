-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.anamneses_registros (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  observacao text,
  animal uuid,
  data date DEFAULT now(),
  veterinario uuid,
  condicoes ARRAY,
  temperatura real,
  score smallint,
  pesagem bigint,
  CONSTRAINT anamneses_registros_pkey PRIMARY KEY (id),
  CONSTRAINT anamneses_registros_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id),
  CONSTRAINT anamneses_registros_veterinario_fkey FOREIGN KEY (veterinario) REFERENCES public.veterinarios(vet_id),
  CONSTRAINT anamneses_registros_pesagem_fkey FOREIGN KEY (pesagem) REFERENCES public.pesagens(id)
);
CREATE TABLE public.animais (
  animal_id uuid NOT NULL DEFAULT gen_random_uuid(),
  criado timestamp with time zone NOT NULL DEFAULT now(),
  nome text NOT NULL DEFAULT ''::text,
  nascimento date DEFAULT now(),
  genero text DEFAULT ''::text,
  raça text DEFAULT ''::text,
  especie text DEFAULT ''::text,
  cor text DEFAULT ''::text,
  pelagem text DEFAULT ''::text,
  falecido boolean DEFAULT false,
  foto text DEFAULT ''::text,
  castrado boolean DEFAULT false,
  desaparecido boolean DEFAULT false,
  vacinado boolean DEFAULT false,
  vermifugado boolean DEFAULT false,
  desparasitado boolean DEFAULT false,
  peso real DEFAULT '0'::real,
  porte text DEFAULT ''::text,
  torax integer DEFAULT 0,
  comprimento integer DEFAULT 0,
  pescoço integer DEFAULT 0,
  altura integer DEFAULT 0,
  faixaetaria text DEFAULT ''::text,
  canil bigint,
  adotado boolean DEFAULT false,
  diagnosticos ARRAY,
  internado boolean DEFAULT false,
  disponivel boolean DEFAULT false,
  idx bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  album text,
  CONSTRAINT animais_pkey PRIMARY KEY (animal_id),
  CONSTRAINT animais_genero_fkey FOREIGN KEY (genero) REFERENCES public.generos(genero),
  CONSTRAINT animais_raça_fkey FOREIGN KEY (raça) REFERENCES public.racas(raca),
  CONSTRAINT animais_pelagem_fkey FOREIGN KEY (pelagem) REFERENCES public.pelagens(pelagem),
  CONSTRAINT animais_especie_fkey FOREIGN KEY (especie) REFERENCES public.especies(especie),
  CONSTRAINT animais_cor_fkey FOREIGN KEY (cor) REFERENCES public.cores(cor),
  CONSTRAINT animais_porte_fkey FOREIGN KEY (porte) REFERENCES public.portes(porte),
  CONSTRAINT animais_faixaetaria_fkey FOREIGN KEY (faixaetaria) REFERENCES public.idades(idade),
  CONSTRAINT animais_canil_fkey FOREIGN KEY (canil) REFERENCES public.canis(id)
);
CREATE TABLE public.animais_descricao (
  animal uuid NOT NULL,
  descricao text,
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  CONSTRAINT animais_descricao_pkey PRIMARY KEY (id),
  CONSTRAINT animais_descricao_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id)
);
CREATE TABLE public.arquivos (
  aquivo text NOT NULL DEFAULT ''::text,
  nome text NOT NULL DEFAULT ''::text,
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  animal uuid,
  registro bigint,
  criacao date,
  observacao text,
  apagado boolean DEFAULT false,
  CONSTRAINT arquivos_pkey PRIMARY KEY (id),
  CONSTRAINT arquivos_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id),
  CONSTRAINT arquivos_registro_fkey FOREIGN KEY (registro) REFERENCES public.registros(registro_id)
);
CREATE TABLE public.canil_tratador (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  canil bigint,
  usuario text NOT NULL,
  nome text,
  senha text,
  CONSTRAINT canil_tratador_pkey PRIMARY KEY (id),
  CONSTRAINT canil_tratador_canil_fkey FOREIGN KEY (canil) REFERENCES public.canis(id)
);
CREATE TABLE public.canis (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  canil text,
  proprietario uuid,
  excluido boolean DEFAULT false,
  aceita_inscricoes boolean,
  logotipo_url text,
  CONSTRAINT canis_pkey PRIMARY KEY (id),
  CONSTRAINT canis_proprietario_fkey FOREIGN KEY (proprietario) REFERENCES public.usuarios(user_id)
);
CREATE TABLE public.canis_membros (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  canil bigint NOT NULL,
  membro uuid NOT NULL,
  admin boolean DEFAULT false,
  guest boolean DEFAULT false,
  vet boolean NOT NULL DEFAULT false,
  solicitacao_aceita boolean DEFAULT false,
  solicitacao_realizada boolean DEFAULT false,
  CONSTRAINT canis_membros_pkey PRIMARY KEY (id),
  CONSTRAINT canis_responsaveis_canil_fkey FOREIGN KEY (canil) REFERENCES public.canis(id),
  CONSTRAINT canis_responsaveis_responsavel_fkey FOREIGN KEY (membro) REFERENCES public.usuarios(user_id)
);
CREATE TABLE public.caracteristicas (
  caracteristica bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  positiva boolean,
  CONSTRAINT caracteristicas_pkey PRIMARY KEY (caracteristica)
);
CREATE TABLE public.clinicas (
  clinica text NOT NULL,
  telefone text DEFAULT ''::text,
  endereco text DEFAULT ''::text,
  logo text DEFAULT ''::text,
  canil_id bigint,
  CONSTRAINT clinicas_pkey PRIMARY KEY (clinica),
  CONSTRAINT clinicas_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.condicoes_parametro (
  condicao text NOT NULL,
  parametro text NOT NULL DEFAULT ''::text,
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  negativo boolean DEFAULT false,
  valor smallint NOT NULL DEFAULT '0'::smallint,
  canil_id bigint,
  CONSTRAINT condicoes_parametro_pkey PRIMARY KEY (id),
  CONSTRAINT condicoes_parametro_parametro_fkey FOREIGN KEY (parametro) REFERENCES public.parametros_anamnese(parametro),
  CONSTRAINT condicoes_parametro_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.conexao (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  data date NOT NULL DEFAULT now(),
  pessoa bigint,
  animal uuid,
  encerrada boolean DEFAULT false,
  CONSTRAINT conexao_pkey PRIMARY KEY (id),
  CONSTRAINT interesse_pessoa_fkey FOREIGN KEY (pessoa) REFERENCES public.pessoa(id),
  CONSTRAINT interesse_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id)
);
CREATE TABLE public.conexao_registro (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  data timestamp without time zone NOT NULL DEFAULT now(),
  status text NOT NULL,
  observacao text,
  CONSTRAINT conexao_registro_pkey PRIMARY KEY (id),
  CONSTRAINT conexao_registro_status_fkey FOREIGN KEY (status) REFERENCES public.conexao_status(id)
);
CREATE TABLE public.conexao_status (
  id text NOT NULL,
  indice smallint,
  negativo boolean DEFAULT false,
  terminou boolean DEFAULT false,
  CONSTRAINT conexao_status_pkey PRIMARY KEY (id)
);
CREATE TABLE public.cores (
  cor text NOT NULL,
  canil_id bigint,
  CONSTRAINT cores_pkey PRIMARY KEY (cor),
  CONSTRAINT cores_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.diagnostico (
  nome text NOT NULL,
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  especie text,
  canil_id bigint,
  CONSTRAINT diagnostico_pkey PRIMARY KEY (id),
  CONSTRAINT diagnostico_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id),
  CONSTRAINT diagnostico_especie_fkey FOREIGN KEY (especie) REFERENCES public.especies(especie)
);
CREATE TABLE public.document_metadata (
  id text NOT NULL,
  title text,
  url text,
  created_at timestamp without time zone DEFAULT now(),
  schema text,
  CONSTRAINT document_metadata_pkey PRIMARY KEY (id)
);
CREATE TABLE public.document_rows (
  id integer NOT NULL DEFAULT nextval('document_rows_id_seq'::regclass),
  dataset_id text,
  row_data jsonb,
  CONSTRAINT document_rows_pkey PRIMARY KEY (id),
  CONSTRAINT document_rows_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.document_metadata(id)
);
CREATE TABLE public.documents (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  content text,
  fts tsvector DEFAULT to_tsvector('portuguese'::regconfig, content),
  embedding USER-DEFINED,
  metadata jsonb,
  CONSTRAINT documents_pkey PRIMARY KEY (id)
);
CREATE TABLE public.escolaridade (
  id text NOT NULL,
  CONSTRAINT escolaridade_pkey PRIMARY KEY (id)
);
CREATE TABLE public.especies (
  especie text NOT NULL,
  indice smallint,
  canil_id bigint,
  CONSTRAINT especies_pkey PRIMARY KEY (especie),
  CONSTRAINT especies_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.generos (
  genero text NOT NULL,
  CONSTRAINT generos_pkey PRIMARY KEY (genero)
);
CREATE TABLE public.idades (
  idade text NOT NULL DEFAULT ''::text,
  indice smallint NOT NULL DEFAULT '0'::smallint,
  descritivo text,
  CONSTRAINT idades_pkey PRIMARY KEY (idade)
);
CREATE TABLE public.imunizacao (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  criacao timestamp with time zone NOT NULL DEFAULT now(),
  tipo text,
  animal uuid,
  veterinario uuid,
  clinica text,
  tarefa bigint,
  imunizante bigint,
  observacao text,
  registro bigint,
  CONSTRAINT imunizacao_pkey PRIMARY KEY (id),
  CONSTRAINT imunizacao_registro_fkey FOREIGN KEY (registro) REFERENCES public.registros(registro_id),
  CONSTRAINT imunizacao_tipo_fkey FOREIGN KEY (tipo) REFERENCES public.imunizacao_tipo(id),
  CONSTRAINT imunizacao_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id),
  CONSTRAINT imunizacao_imunizante_fkey FOREIGN KEY (imunizante) REFERENCES public.imunizante(id),
  CONSTRAINT imunizacao_veterinario_fkey FOREIGN KEY (veterinario) REFERENCES public.veterinarios(vet_id),
  CONSTRAINT imunizacao_clinica_fkey FOREIGN KEY (clinica) REFERENCES public.clinicas(clinica),
  CONSTRAINT imunizacao_tarefa_fkey FOREIGN KEY (tarefa) REFERENCES public.tarefa(id)
);
CREATE TABLE public.imunizacao_tipo (
  id text NOT NULL,
  icone text,
  canil_id bigint,
  CONSTRAINT imunizacao_tipo_pkey PRIMARY KEY (id),
  CONSTRAINT imunizacao_tipo_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.imunizante (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  imunizacao_tipo text,
  especie text,
  nome text,
  canil_id bigint,
  CONSTRAINT imunizante_pkey PRIMARY KEY (id),
  CONSTRAINT imunizante_imunizacao_tipo_fkey FOREIGN KEY (imunizacao_tipo) REFERENCES public.imunizacao_tipo(id),
  CONSTRAINT imunizante_especie_fkey FOREIGN KEY (especie) REFERENCES public.especies(especie),
  CONSTRAINT imunizante_imunizacao_tipo_fkey1 FOREIGN KEY (imunizacao_tipo) REFERENCES public.imunizacao_tipo(id),
  CONSTRAINT imunizante_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.interessado_animal (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  data timestamp with time zone NOT NULL DEFAULT now(),
  pessoa bigint NOT NULL,
  animal uuid,
  CONSTRAINT interessado_animal_pkey PRIMARY KEY (id),
  CONSTRAINT interessado_animal_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id),
  CONSTRAINT interessado_animal_pessoa_fkey FOREIGN KEY (pessoa) REFERENCES public.questionario(id)
);
CREATE TABLE public.medicacao_falhas (
  id text NOT NULL,
  CONSTRAINT medicacao_falhas_pkey PRIMARY KEY (id)
);
CREATE TABLE public.medicamento (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nome text,
  canil_id bigint,
  CONSTRAINT medicamento_pkey PRIMARY KEY (id),
  CONSTRAINT medicamento_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.medicamento_dosagem (
  id text NOT NULL,
  indice smallint GENERATED ALWAYS AS IDENTITY NOT NULL,
  CONSTRAINT medicamento_dosagem_pkey PRIMARY KEY (id)
);
CREATE TABLE public.medicamento_via (
  id text NOT NULL,
  CONSTRAINT medicamento_via_pkey PRIMARY KEY (id)
);
CREATE TABLE public.medidas (
  medida_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  criacao timestamp with time zone NOT NULL DEFAULT now(),
  altura integer,
  comprimento integer,
  pescoco integer,
  torax integer,
  animal uuid,
  CONSTRAINT medidas_pkey PRIMARY KEY (medida_id),
  CONSTRAINT medidas_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id)
);
CREATE TABLE public.moradia_tipos (
  tipo_moradia text NOT NULL,
  CONSTRAINT moradia_tipos_pkey PRIMARY KEY (tipo_moradia)
);
CREATE TABLE public.n8n_chat_histories (
  id integer NOT NULL DEFAULT nextval('n8n_chat_histories_id_seq'::regclass),
  session_id character varying NOT NULL,
  message jsonb NOT NULL,
  CONSTRAINT n8n_chat_histories_pkey PRIMARY KEY (id)
);
CREATE TABLE public.parametros_anamnese (
  parametro text NOT NULL,
  canil_id bigint,
  CONSTRAINT parametros_anamnese_pkey PRIMARY KEY (parametro),
  CONSTRAINT parametros_anamnese_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.pelagens (
  pelagem text NOT NULL,
  indice smallint,
  CONSTRAINT pelagens_pkey PRIMARY KEY (pelagem)
);
CREATE TABLE public.pesagens (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  animal uuid NOT NULL,
  data date NOT NULL,
  peso real NOT NULL,
  CONSTRAINT pesagens_pkey PRIMARY KEY (id),
  CONSTRAINT pesagens_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id)
);
CREATE TABLE public.pessoa (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  cadastro date NOT NULL DEFAULT now(),
  nome text,
  nascimento date,
  telefone text,
  email text UNIQUE,
  usuario uuid,
  sexo smallint,
  renda_sm smallint,
  escolaridade text,
  profissao text,
  end_cep text,
  end_uf character varying,
  end_cidade text,
  end_bairro text,
  end_numero bigint,
  end_complemento text,
  end_logradouro text,
  whatsap_id text,
  contacts_id text,
  CONSTRAINT pessoa_pkey PRIMARY KEY (id),
  CONSTRAINT pessoa_sexo_fkey FOREIGN KEY (sexo) REFERENCES public.sexo(id),
  CONSTRAINT pessoa_usuario_fkey FOREIGN KEY (usuario) REFERENCES public.usuarios(user_id),
  CONSTRAINT pessoa_escolaridade_fkey FOREIGN KEY (escolaridade) REFERENCES public.escolaridade(id)
);
CREATE TABLE public.pessoa_likes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  pessoa_id bigint,
  animais ARRAY,
  usuario uuid,
  CONSTRAINT pessoa_likes_pkey PRIMARY KEY (id),
  CONSTRAINT pessoa_likes_usuario_fkey FOREIGN KEY (usuario) REFERENCES public.usuarios(user_id),
  CONSTRAINT pessoa_likes_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoa(id)
);
CREATE TABLE public.portes (
  porte text NOT NULL,
  descritivo text,
  indice smallint,
  limite_peso smallint,
  CONSTRAINT portes_pkey PRIMARY KEY (porte)
);
CREATE TABLE public.prescricao (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inicio date,
  receita bigint,
  medicamento bigint,
  continuo boolean DEFAULT false,
  duracao_dias smallint,
  dosagem text DEFAULT ''::text,
  via text DEFAULT ''::text,
  descricao text DEFAULT ''::text,
  intervalo_horas smallint,
  criacao timestamp without time zone DEFAULT now(),
  finalizada boolean DEFAULT false,
  inicio_horario time without time zone,
  salva boolean DEFAULT false,
  dose text DEFAULT ''::text,
  CONSTRAINT prescricao_pkey PRIMARY KEY (id),
  CONSTRAINT prescricao_medicamento_fkey FOREIGN KEY (medicamento) REFERENCES public.medicamento(id),
  CONSTRAINT prescricao_receita_fkey FOREIGN KEY (receita) REFERENCES public.receita(id)
);
CREATE TABLE public.prescricao_tarefa (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  realizacao timestamp without time zone NOT NULL DEFAULT now(),
  prescricao bigint NOT NULL,
  pessoa uuid,
  concluida boolean DEFAULT false,
  observacao text,
  dia date,
  hora time without time zone,
  tratador text,
  CONSTRAINT prescricao_tarefa_pkey PRIMARY KEY (id),
  CONSTRAINT prescricao_tarefa_prescricao_fkey FOREIGN KEY (prescricao) REFERENCES public.prescricao(id),
  CONSTRAINT prescricao_tarefa_pessoa_fkey FOREIGN KEY (pessoa) REFERENCES public.usuarios(user_id)
);
CREATE TABLE public.questionario (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  criacao date NOT NULL DEFAULT now(),
  profissao text,
  renda smallint,
  endereco text NOT NULL,
  rede_social text,
  moradia_tipo text,
  moradia_propria boolean,
  moradores_quantidade smallint,
  moradores_favoraveis boolean,
  moradores_alergia boolean,
  caes_qtd smallint,
  vacinar_concorda boolean,
  castrar_concorda boolean,
  educar_concorda boolean,
  passear_concorda boolean,
  informar_concorda boolean,
  passeios_mes smallint,
  endCep text,
  endLogradouro text,
  endNumero text,
  endCidade text,
  endUF text,
  endBairro text,
  animais_castrados boolean,
  animais_vacinados boolean,
  animais_falecimento boolean,
  gatos_qtd smallint,
  janelas_teladas boolean,
  animal_dormir text,
  animais_responsavel text,
  acesso_casa boolean,
  acesso_rua boolean,
  sozinho_horas smallint,
  buscar_concorda boolean,
  racao_tipo text,
  animal_incomodo ARRAY,
  contribuir_concorda boolean,
  outros_animais boolean,
  passeios text,
  animais_permitidos boolean,
  pessoa_id bigint,
  CONSTRAINT questionario_pkey PRIMARY KEY (id),
  CONSTRAINT questionario_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoa(id),
  CONSTRAINT interessados_moradia_tipo_fkey FOREIGN KEY (moradia_tipo) REFERENCES public.moradia_tipos(tipo_moradia)
);
CREATE TABLE public.racas (
  raca text NOT NULL UNIQUE,
  indice smallint,
  especie text DEFAULT 'Cachorro'::text,
  canil_id bigint,
  CONSTRAINT racas_pkey PRIMARY KEY (raca),
  CONSTRAINT racas_especie_fkey FOREIGN KEY (especie) REFERENCES public.especies(especie),
  CONSTRAINT racas_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);
CREATE TABLE public.receita (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  data date NOT NULL DEFAULT now(),
  veterinario uuid,
  animal uuid,
  salva boolean DEFAULT false,
  CONSTRAINT receita_pkey PRIMARY KEY (id),
  CONSTRAINT receita_veterinario_fkey FOREIGN KEY (veterinario) REFERENCES public.veterinarios(vet_id),
  CONSTRAINT receita_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id)
);
CREATE TABLE public.registros (
  registro_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  data date NOT NULL,
  tipo text,
  veterinario_id uuid,
  descricao text DEFAULT ''::text,
  animal_id uuid,
  clinica text,
  pendente boolean DEFAULT false,
  criado_em timestamp without time zone DEFAULT now(),
  criado_por uuid,
  previsto_data timestamp without time zone,
  realizado_data timestamp without time zone,
  CONSTRAINT registros_pkey PRIMARY KEY (registro_id),
  CONSTRAINT registros_tipo_fkey FOREIGN KEY (tipo) REFERENCES public.registros_tipos(tipoRegistro),
  CONSTRAINT registros_veterinario_fkey FOREIGN KEY (veterinario_id) REFERENCES public.veterinarios(vet_id),
  CONSTRAINT registros_animal_fkey FOREIGN KEY (animal_id) REFERENCES public.animais(animal_id),
  CONSTRAINT registros_clinica_fkey FOREIGN KEY (clinica) REFERENCES public.clinicas(clinica),
  CONSTRAINT registros_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.usuarios(user_id)
);
CREATE TABLE public.registros_tipos (
  tipoRegistro text NOT NULL,
  indice smallint,
  icone text,
  CONSTRAINT registros_tipos_pkey PRIMARY KEY (tipoRegistro)
);
CREATE TABLE public.resgates (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  data date NOT NULL,
  animal uuid,
  local text,
  CONSTRAINT resgates_pkey PRIMARY KEY (id),
  CONSTRAINT resgates_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id)
);
CREATE TABLE public.sexo (
  id smallint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nome text,
  CONSTRAINT sexo_pkey PRIMARY KEY (id)
);
CREATE TABLE public.tarefa (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  data_criada date NOT NULL DEFAULT now(),
  data_prevista date DEFAULT now(),
  data_realizada date,
  animal uuid,
  tipo text,
  descricao text,
  CONSTRAINT tarefa_pkey PRIMARY KEY (id),
  CONSTRAINT tarefa_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id),
  CONSTRAINT tarefa_tipo_fkey FOREIGN KEY (tipo) REFERENCES public.tarefa_tipo(tipo)
);
CREATE TABLE public.tarefa_tipo (
  tipo text NOT NULL,
  icone text,
  CONSTRAINT tarefa_tipo_pkey PRIMARY KEY (tipo)
);
CREATE TABLE public.usuarios (
  user_id uuid NOT NULL DEFAULT gen_random_uuid(),
  created timestamp with time zone NOT NULL DEFAULT now(),
  user_name text,
  user_email text NOT NULL UNIQUE,
  foto text,
  CONSTRAINT usuarios_pkey PRIMARY KEY (user_id),
  CONSTRAINT usuarios_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
CREATE TABLE public.vacinacoes (
  animal uuid,
  data date NOT NULL,
  aplicada boolean DEFAULT false,
  tipo text,
  vacina_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  CONSTRAINT vacinacoes_pkey PRIMARY KEY (vacina_id),
  CONSTRAINT vacina_animal_fkey FOREIGN KEY (animal) REFERENCES public.animais(animal_id),
  CONSTRAINT vacinacoes_tipo_fkey FOREIGN KEY (tipo) REFERENCES public.vacinas_tipos(tipoVacina)
);
CREATE TABLE public.vacinas_tipos (
  tipoVacina text NOT NULL,
  especie text,
  canil_id bigint,
  CONSTRAINT vacinas_tipos_pkey PRIMARY KEY (tipoVacina),
  CONSTRAINT vacinas_tipos_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id),
  CONSTRAINT tipos_vacina_especie_fkey FOREIGN KEY (especie) REFERENCES public.especies(especie)
);
CREATE TABLE public.veterinarios (
  nome text,
  foto text,
  crmv bigint,
  vet_id uuid NOT NULL DEFAULT gen_random_uuid(),
  indice smallint,
  usuario_id uuid,
  canil_id bigint,
  CONSTRAINT veterinarios_pkey PRIMARY KEY (vet_id),
  CONSTRAINT veterinarios_id_usuario_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(user_id),
  CONSTRAINT veterinarios_canil_id_fkey FOREIGN KEY (canil_id) REFERENCES public.canis(id)
);