O seu `readme.md` foi totalmente atualizado para incorporar todas as melhorias recentes: a migração para a API de vetores/chunks em C (DuckDB 1.5.6+), o suporte avançado a dialetos e extensões via RDD, e o tratamento universal de datas e horários.

Aqui está o arquivo `readme.md` melhorado e pronto para uso:

```markdown
# DuckDB RDD para Harbour

Uma implementação nativa de **RDD (Replaceable Database Driver)** e de uma camada orientada a objetos para o Harbour, permitindo usar o **DuckDB** — um banco analítico em-process e serverless — com SQL direto e também com a ergonomia de comandos xBase, como `dbAppend()`, `dbSkip()`, `dbGoTop()` e `dbCommit()`.

O projeto foi pensado para facilitar a integração de aplicações Harbour com o DuckDB sem abrir um processo externo, mantendo a execução embutida na própria aplicação e aproveitando ao máximo a performance do motor analítico da DuckDB.

---

## 🚀 Visão geral

Este repositório combina duas formas de uso:

- **Camada orientada a objetos**: `DuckDBClass` e `TDuckDBQuery
- **Camada RDD**: `DUCKDBRDD` para trabalhar como tabela/xBase

Isso permite que você escolha entre:
- Executar SQL diretamente para cargas analíticas e consultas complexas;
- Usar a API RDD para manter compatibilidade com aplicações Harbour já estruturadas em tabelas e navegação por registros.

---

## ✨ Recursos principais

- **Arquitetura In-Process**: Sem daemon ou serviço externo rodando em separado.
- **Motor de Baixo Nível Otimizado**: Interface em C (`duckdb.c`) atualizada para a API de Chunks e Vetores (`duckdb_data_chunk`, `duckdb_vector`), garantindo máxima performance de leitura em comparação com chamadas isoladas por célula
- **Compatibilidade Avançada (v1.5.6+)**: Suporte completo ao mapeamento de tipos da árvore oficial do DuckDB, incluindo subtipos de timestamps de alta precisão (`TIMESTAMP_S`, `TIMESTAMP_MS`, `TIMESTAMP_NS`)
- **Múltiplos Dialetos**: Suporte a conexões e anexação de fontes externas como SQLite, DuckLake, MySQL, PostgreSQL, arquivos planos (CSV, JSON, Parquet) e extensões ODBC
- **Segurança e Confiabilidade**: Conversor universal de datas e horários (`UniversalDateTime`) para evitar quebras em campos temporais complexos, além de tratamento seguro para identificadores (`QuoteIdent`)
- **Trabalho em 64 bits**: Preparado e testado para ambiente Windows + MinGW64 com suporte a inteiros de 64 bits (`HB_LONGLONG`)

---

## 📁 Estrutura do projeto

- `DuckDBClass.prg` — classes de conexão, execução de comandos e controle de consultas
- `duckdbrdd.prg` — implementação do RDD para compatibilidade com padrões xBase
- `duckdb.c` — ponte em C entre o Harbour e a C-API do DuckDB baseada em vetores
- `duckdb.ch` — definições de macros e mapeamento completo de tipos da API
- `hbduckdb.hbp` — arquivo de build do Harbour
- `compmingw64.bat` — script de compilação para ambiente MinGW 64 bits
- `teste/` — testes e exemplos de uso

---

## ⚙️ Requisitos

Antes de compilar, certifique-se de ter:

- Harbour 3.2+ ou superior
- MinGW 64 bits (GCC)
- DuckDB C API instalada (`duckdb.h`, `duckdb.dll` ou `libduckdb.dll.a`)
- `hbmk2` disponível no PATH

---

## 🛠️ Compilação

A configuração principal do projeto já está em `hbduckdb.hbp`.

Exemplo de uso com `hbmk2`:

```text
hbmk2 hbduckdb.hbp

```

Arquivo de projeto (`hbduckdb.hbp`):

```text
-hblib
-olib/${hb_plat}/${hb_comp}/${hb_name}

-Ic:/harbour/hb3rd/duckdb-x64/
-w3 -es2

{!xhb}-hbx=hbduckdb.hbx
{!xhb}hbduckdb.hbx

xhb.hbc
duckdb.c
duckdbrdd.prg
DuckDBClass.prg

$hb_pkg_install.hbm

```

Se o ambiente for Windows e você usa MinGW, também pode utilizar o script de build do projeto:

```bat
compmingw64.bat

```

---

## 📖 Exemplos de uso

### 1) Uso direto via `DuckDBClass`

```harbour
PROCEDURE Main()
   LOCAL oDB := NIL
   LOCAL oQry := NIL

   // Conecta ao banco físico; passe "" para usar em memória
   oDB := DuckDBClass():New( "meubanco.duckdb" )

   IF oDB:NetErr()
      ? "Erro:", oDB:Error()
      RETURN
   ENDIF

   // Cria uma tabela
   oDB:Execute( "CREATE TABLE IF NOT EXISTS clientes (id INTEGER, nome VARCHAR, limite DOUBLE)" )

   // Insere dados
   oDB:Execute( "INSERT INTO clientes VALUES (1, 'Ana Souza', 2500.00)" )
   oDB:Execute( "INSERT INTO clientes VALUES (2, 'Carlos Silva', 5000.00)" )

   // Executa uma consulta
   oQry := oDB:Query( "SELECT * FROM clientes ORDER BY id" )
   DO WHILE oQry:Fetch()
      ? oQry:FieldGet( 1 ), oQry:FieldGet( 2 ), oQry:FieldGet( 3 )
   ENDDO

   oQry:Destroy()
   oDB:Close()
RETURN

```

### 2) Uso com RDD tradicional (`DUCKDBRDD`)

```harbour
REQUEST DUCKDBRDD

PROCEDURE Main()
   LOCAL nConn
   LOCAL aStru

   // Inicia a conexão com o banco DuckDB
   nConn := DBDUCKDBCONNECTION( "meubanco.duckdb" )

   // Estrutura da tabela virtual
   aStru := { ;
      { "ID",     "N",  9, 0 }, ;
      { "NOME",   "C", 50, 0 }, ;
      { "LIMITE", "N", 15, 2 }  ;
   }

   // Cria e abre a tabela usando a RDD do DuckDB
   dbCreate( "clientes", aStru, "DUCKDBRDD", .T., "CLI" )

   // Configura a chave primária para permitir updates e deletes
   DUCKDB_SETPK( "CLI", "ID" )

   // Inserção estilo xBase
   CLI->( dbAppend() )
   CLI->ID     := 1
   CLI->NOME   := "Carlos Silva"
   CLI->LIMITE := 5000.00
   CLI->( dbCommit() )

   // Navegação
   CLI->( dbGoTop() )
   DO WHILE !CLI->( EOF() )
      ? CLI->ID, CLI->NOME, CLI->LIMITE
      CLI->( dbSkip() )
   ENDDO

   CLOSE ALL
   DBDUCKDBCLEARCONNECTION( nConn )
RETURN

```

---

## 🔧 Funções importantes

Algumas funções centrais do projeto:

* `DuckDBClass():New(cDatabase)` — cria a conexão orientada a objetos


* `Execute(cQuery)` — executa comandos SQL sem retorno de linha


* `Query(cQuery)` — retorna uma consulta com navegação por registros


* `DBDUCKDBCONNECTION(cDatabase, nDialect, cAlias, cConnStr)` — inicia uma conexão avançada para uso com o RDD


* `DUCKDB_SETPK(cAlias, cFields)` — define chave primária para a área RDD


* `DBDUCKDBCLEARCONNECTION(nConn)` — encerra a conexão ativa



---

## ✅ Quando usar este projeto

Este driver é ideal quando você precisa de:

* Alta performance analítica embutida diretamente na aplicação Harbour;


* Flexibilidade para alternar entre código SQL nativo e arquitetura orientada a objetos;


* Transparência total ao rodar rotinas legadas baseadas em comandos xBase através do RDD;


* Conectividade facilitada com múltiplos SGBDs e fontes de arquivos externos (Parquet, SQLite, CSV, JSON, etc.).



```

```