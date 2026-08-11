# DuckDB RDD for Harbour

Uma implementação nativa de **RDD (Replaceable Database Driver)** e camada de classes orientada a objetos para o Harbour, permitindo interagir com o **DuckDB** (banco de dados analítico e *serverless* em C/C++) usando tanto sintaxe SQL direta quanto comandos tradicionais xBase (`dbAppend`, `dbSkip`, `dbGoTop`, etc.).

---

## 🚀 Características

* **Arquitetura In-Process (Serverless):** Não exige a instalação de serviços ou daemons em background; roda diretamente embutido na aplicação via DLL.
* **Dual Interface:**
* Camada orientada a objetos (`DuckDBClass` / `TDuckDBQuery`) para manipulação via comandos SQL puros.
* Camada RDD (`DUCKDBRDD`) para navegação e manipulação estilo DBF através de áreas de trabalho (*WorkAreas*).




* **Suporte a 64-bits:** Totalmente otimizado para arquiteturas modernas de 64-bits no Windows (MinGW64).
* **Camada de Cache Inteligente:** Minimiza idas e vindas ao SGBD durante a navegação por registros através de um buffer local gerenciado pela RDD.

---

## 📦 Estrutura dos Arquivos

O projeto é composto por três componentes principais:

1. **`DuckDBClass.prg`**: Classes de conexão, execução de comandos e controle de consultas (*Query* e *Row*).
2. **`duckdbrdd.prg`**: Implementação das funções de RDD do USRRDD para compatibilidade xBase.


3. **`duckdb.c`**: Wrapper de baixo nível em C que faz a ponte entre a C-API do DuckDB e o ecossistema do Harbour.

---

## 🛠️ Configuração e Compilação

Para compilar o seu projeto utilizando o utilitário `hbmk2`, certifique-se de incluir os caminhos de *include* da API do DuckDB e de linkar a biblioteca dinâmica (`duckdb.dll` / `libduckdb.dll.a`).

Exemplo de arquivo de projeto (`hbduckdb.hbp`):

```text
-hblib
-olib/${hb_plat}/${hb_comp}/${hb_name}
-w3 -es2

# Caminho para os arquivos de cabeçalho (.h) do DuckDB
-Ic:/harbour/hb3rd/duckdb-x64/

# Caminho e biblioteca de linkagem
-Lc:/harbour/hb3rd/duckdb-x64/
-lduckdb

duckdb.c
duckdbrdd.prg
DuckDBClass.prg

```

---

## 📖 Exemplos de Uso

### 1. Utilizando via Classe (`DuckDBClass`)

```harbour
PROCEDURE Main()
   LOCAL oDB, oQry

   // Conecta ao banco físico (ou passe "" para banco em memória)
   oDB := DuckDBClass():New( "meubanco.duckdb" )
   
   IF oDB:NetErr()
      ? "Erro:", oDB:Error()
      RETURN
   ENDIF

   // Criação de Tabela
   oDB:Execute( "CREATE TABLE IF NOT EXISTS clientes (id INTEGER, nome VARCHAR, limite DOUBLE)" )

   // Inserção
   oDB:Execute( "INSERT INTO clientes VALUES (1, 'Ana Souza', 2500.00)" )

   // Consulta (Query)
   oQry := oDB:Query( "SELECT * FROM clientes" )
   DO WHILE oQry:Fetch()
      ? oQry:FieldGet( 1 ), oQry:FieldGet( 2 ), oQry:FieldGet( 3 )
   ENDDO
   oQry:Destroy()

   oDB:Close()
RETURN

```

### 2. Utilizando via RDD Tradicional (`DUCKDBRDD`)

```harbour
REQUEST DUCKDBRDD

PROCEDURE Main()
   LOCAL nConn, aStru

   // Inicia a conexão com o DuckDB
   nConn := DBDUCKDBCONNECTION( "meubanco.duckdb" )

   // Define a estrutura da tabela virtual
   aStru := { ;
      { "ID",     "N",  9, 0 }, ;
      { "NOME",   "C", 50, 0 }, ;
      { "LIMITE", "N", 15, 2 }  ;
   }

   // Cria e abre a tabela utilizando a RDD do DuckDB
   dbCreate( "clientes", aStru, "DUCKDBRDD", .T., "CLI" )

   // Configura a chave primária para permitir updates/deletes automáticos
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

## ⚙️ Requisitos

* **Harbour 3.2+** (ou superior)
* Compilador **MinGW 64-bits** (GCC)
* Biblioteca **DuckDB C-API** (`duckdb.h` e `duckdb.dll` de 64-bits)