module pending_migrations

import PormG.Migrations
import OrderedCollections: OrderedDict

# table: status
status = OrderedDict{String, String}(
"New model" =>
 """CREATE TABLE IF NOT EXISTS status (
  "status" varchar(250) NOT NULL,
  "id" bigint PRIMARY KEY UNIQUE NOT NULL GENERATED BY DEFAULT AS IDENTITY
);""",
 
"Create index on id" =>
 """CREATE INDEX IF NOT EXISTS "status_id_a8vfyhqg_idx" ON "status" ("id");""")

# table: dim_municipio_populacao_hist
dim_municipio_populacao_hist = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_municipio_populacao_hist" CASCADE;""")

# table: dim_uf
dim_uf = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_uf" CASCADE;""")

# table: dim_teste_timezone
dim_teste_timezone = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_teste_timezone" CASCADE;""")

# table: dim_tipologia
dim_tipologia = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_tipologia" CASCADE;""")

# table: dim_municipio
dim_municipio = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_municipio" CASCADE;""")

# table: dim_ibge
dim_ibge = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_ibge" CASCADE;""")

# table: dim_ine_cat
dim_ine_cat = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_ine_cat" CASCADE;""")

# table: dim_servidor
dim_servidor = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_servidor" CASCADE;""")

# table: dim_estabelecimento
dim_estabelecimento = OrderedDict{String, String}(
"Drop table" =>
 """DROP TABLE IF EXISTS "dim_estabelecimento" CASCADE;""")

end
