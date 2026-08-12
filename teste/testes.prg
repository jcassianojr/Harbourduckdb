REQUEST DUCKDBRDD // Obriga o Harbour a linkar o nosso RDD

PROCEDURE Main()
   SetMode( 25, 80 )
   CLS
   
   ? "=================================================="
   ? "   INICIANDO TESTES DE INTEGRACAO DUCKDB          "
   ? "=================================================="
   ? ""
   
   TesteClasse()
   ? ""
   TesteRDD()
   
   ? ""
   ? "Testes concluidos. Pressione qualquer tecla..."
   Inkey(0)
RETURN

// ------------------------------------------------------------------
// TESTE 1: Usando Orientacao a Objetos (DuckDBClass)
// ------------------------------------------------------------------
PROCEDURE TesteClasse()
   LOCAL oDB, oQry
   
   ? ">>> TESTE 1: DuckDBClass (Via Comandos SQL) <<<"
   
   // 1. Criacao do Banco (Em memoria) oDB := DuckDBClass():New( "" ) 
   oDB := DuckDBClass():New( "teste1.db" ) 
   IF oDB:NetErr()
      ? "Erro ao conectar:", oDB:Error()
      RETURN
   ENDIF
   ? "- Conectado ao banco em memoria!"
   
   // 2. Criacao da Tabela (DDL)
   oDB:Execute( "CREATE TABLE clientes (id INTEGER, nome VARCHAR, limite DOUBLE)" )
   ? "- Tabela 'clientes' criada."
   
   // 3. Insercao de Registros (DML)
   oDB:Execute( "INSERT INTO clientes VALUES (1, 'Joao Silva', 1500.50)" )
   oDB:Execute( "INSERT INTO clientes VALUES (2, 'Maria Souza', 3200.00)" )
   ? "- 2 registros inseridos."
   
   // 4. Leitura (SELECT)
   ? "- Lendo registros:"
   oQry := oDB:Query( "SELECT * FROM clientes ORDER BY id" )
   DO WHILE oQry:Fetch()
      ? "  ->", oQry:FieldGet( 1 ), oQry:FieldGet( 2 ), oQry:FieldGet( 3 )
   ENDDO
   oQry:Destroy()
   
   // 5. Delecao 
   oDB:Execute( "DELETE FROM clientes WHERE id = 1" )
   ? "- Registro ID 1 deletado."
   
   // 6. Validacao da Delecao
   ? "- Lendo registros apos delecao:"
   oQry := oDB:Query( "SELECT * FROM clientes ORDER BY id" )
   DO WHILE oQry:Fetch()
      ? "  ->", oQry:FieldGet( 1 ), oQry:FieldGet( 2 ), oQry:FieldGet( 3 )
   ENDDO
   oQry:Destroy()
   
   oDB:Close()
   ? "- Conexao da classe encerrada."
RETURN

// ------------------------------------------------------------------
// TESTE 2: Usando Navegacao Nativa (DuckDBRDD)
// ------------------------------------------------------------------
PROCEDURE TesteRDD()
   LOCAL nConn, aStru
   
   ? ">>> TESTE 2: DuckDBRDD (Via Comandos Harbour/xBase) <<<"
   
   // 1. Criacao do Banco (Em memoria)  nConn := DBDUCKDBCONNECTION( "" )
   nConn := DBDUCKDBCONNECTION( "teste2.db" )
   IF nConn == 0
      ? "Erro ao iniciar conexao no RDD."
      RETURN
   ENDIF
   ? "- Conexao RDD iniciada!"
   
   // 2. Criacao da Tabela DBF Virtual
   aStru := { ;
      { "ID",     "N",  9, 0 }, ;
      { "NOME",   "C", 50, 0 }, ;
      { "LIMITE", "N", 15, 2 }  ;
   }
   
   // 2. Criacao da Tabela DBF Virtual (Sem abrir)
   dbCreate( "clientes_rdd", aStru, "DUCKDBRDD" )
   
   // Abre a tabela explicitamente com o Alias "CLI"
   dbUseArea( .T., "DUCKDBRDD", "clientes_rdd", "CLI", .F. )
   
   // OBRIGATORIO: Informar a Chave Primaria para permitir UPDATE/DELETE no RDD
   DUCKDB_SETPK( "CLI", "ID" )
   ? "- Tabela 'clientes_rdd' criada e PK configurada."
   
   // 3. Insercao de Registros (APPEND BLANK)
  // CLI->( dbAppend() )
  dbAppend()
   CLI->ID     := 100
   CLI->NOME   := "Carlos Roberto"
   CLI->LIMITE := 5000.00
   dbcommit()
   
  // CLI->( dbAppend() )
  dbAppend()
   CLI->ID     := 101
   CLI->NOME   := "Ana Paula"
   CLI->LIMITE := 8750.50
   
   dbCommit() // Forca o envio do RowBuf para o SGBD
   ? "- 2 registros inseridos via dbAppend()."
   
   // 4. Leitura (Navegacao Skip)
   ? "- Lendo registros:"
   CLI->( dbGoTop() )
   DO WHILE !CLI->( EOF() )
      ? "  ->", CLI->ID, CLI->NOME, CLI->LIMITE
      CLI->( dbSkip() )
   ENDDO
   
   // 5. Delecao 
   CLI->( dbGoTop() )
   IF CLI->ID == 100
      CLI->( dbDelete() )
   ENDIF
   ? "- Registro ID 100 deletado via dbDelete()."
   
   // 6. Validacao da Delecao
   ? "- Lendo registros apos delecao:"
   CLI->( dbGoTop() )
   DO WHILE !CLI->( EOF() )
      ? "  ->", CLI->ID, CLI->NOME, CLI->LIMITE
      CLI->( dbSkip() )
   ENDDO
   
   CLOSE ALL
   DBDUCKDBCLEARCONNECTION( nConn )
   ? "- Conexao RDD encerrada."
RETURN