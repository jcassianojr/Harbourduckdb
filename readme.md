# DuckDB RDD para Harbour

Uma implementação nativa de **RDD (Replaceable Database Driver)** e de uma camada orientada a objetos para o Harbour, permitindo usar o **DuckDB** — um banco analítico em-process e serverless — com SQL direto e também com a ergonomia de comandos xBase, como `dbAppend()`, `dbSkip()`, `dbGoTop()` e `dbCommit()`.

O projeto foi pensado para facilitar a integração de aplicações Harbour com o DuckDB sem abrir um processo externo, mantendo a execução embutida na própria aplicação e aproveitando a performance do motor analítico da DuckDB.

---

## 🚀 Visão geral

Este repositório combina duas formas de uso:

- Camada orientada a objetos: `DuckDBClass` e `TDuckDBQuery`
- Camada RDD: `DUCKDBRDD` para trabalhar como tabela/xBase

Isso permite que você escolha entre:

- executar SQL diretamente para cargas analíticas e consultas complexas;
- usar a API RDD para manter compatibilidade com aplicações Harbour já estruturadas em tabelas e navegação por registros.

---

## ✨ Recursos principais

- Arquitetura in-process, sem daemon ou serviço externo
- Compatibilidade com programação SQL pura
- Compatibilidade com comandos xBase via RDD
- Suporte a banco em memória ou em disco
- Trabalho em 64 bits, preparado para ambiente Windows + MinGW64
- Estrutura de cache para reduzir acessos redundantes durante a navegação
- Interface simples para conexão, consulta, manipulação e controle transacional

---

## 📁 Estrutura do projeto

- `DuckDBClass.prg` — classes de conexão, execução de comandos e controle de consultas
- `duckdbrdd.prg` — implementação do RDD para compatibilidade com padrões xBase
- `duckdb.c` — ponte em C entre o Harbour e a C-API do DuckDB
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

- `DuckDBClass():New(cDatabase)` — cria a conexão
- `Execute(cQuery)` — executa comandos SQL sem retorno de linha
- `Query(cQuery)` — retorna uma consulta com navegação por registros
- `DBDUCKDBCONNECTION(cDatabase)` — inicia uma conexão para uso com o RDD
- `DUCKDB_SETPK(cAlias, cFields)` — define chave primária para a área
- `DBDUCKDBCLEARCONNECTION(nConn)` — encerra a conexão ativa

---

## 🧪 Testes

O diretório `teste/` contém exemplos prontos para validação do comportamento do driver e do RDD em cenários reais.

Você pode adaptar esses arquivos para realizar testes de:

- criação de tabelas;
- inserção de registros;
- consultas SQL;
- navegação xBase;
- persistência em disco.

---

## ✅ Quando usar este projeto

Este driver é uma boa escolha quando você precisa:

- usar o DuckDB como engine analítico embutido em aplicações Harbour;
- manter compatibilidade com lógica xBase e RDD;
- executar SQL sem depender de um processo externo;
- combinar performance analítica com uma camada familiar de acesso a dados.

---

## 📌 Observações

- O projeto foi projetado para ambientes Windows com MinGW64, mas sua estrutura pode ser adaptada para outros cenários conforme a sua toolchain Harbour.
- Para utilização real em produção, revise os caminhos de include e biblioteca do DuckDB no seu ambiente e ajuste os scripts de build conforme a instalação local.

Se quiser, posso também criar uma versão do README em inglês ou deixar este documento com um visual mais "GitHub style" e profissional, incluindo badges, tabela de comandos e uma seção de troubleshooting.