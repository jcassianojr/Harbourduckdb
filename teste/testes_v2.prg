REQUEST DUCKDBRDD // Obriga o Harbour a linkar o RDD v2

PROCEDURE Main()
   SetMode( 25, 80 )
   CLS

   ? "=================================================="
   ? "   INICIANDO TESTES DE INTEGRACAO DUCKDB V2       "
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
// TESTE 1: DuckDBClass v2 usando comandos SQL
// ------------------------------------------------------------------
PROCEDURE TesteClasse()
   LOCAL oDB, oQry

   ? ">>> TESTE 1: DuckDBClass v2 <<<"

   // Banco em memoria para permitir execucoes repetidas.
   oDB := DuckDBClass():New( "" )
   IF oDB:NetErr()
      ? "Erro ao conectar:", oDB:Error()
      RETURN
   ENDIF
   ? "- Conectado ao banco em memoria."

   IF !oDB:Execute( "CREATE TABLE clientes (id INTEGER, nome VARCHAR, limite DOUBLE)" )
      ? "Erro ao criar tabela:", oDB:Error()
      oDB:Close()
      RETURN
   ENDIF
   IF !oDB:Execute( "INSERT INTO clientes VALUES (1, 'Joao Silva', 1500.50)" ) .OR. ;
      !oDB:Execute( "INSERT INTO clientes VALUES (2, 'Maria Souza', 3200.00)" )
      ? "Erro ao inserir registros:", oDB:Error()
      oDB:Close()
      RETURN
   ENDIF

   ? "- Lendo registros:"
   oQry := oDB:Query( "SELECT * FROM clientes ORDER BY id" )
   IF oQry:NetErr()
      ? "Erro na consulta:", oQry:Error()
      oQry:Destroy()
      oDB:Close()
      RETURN
   ENDIF
   DO WHILE oQry:Fetch()
      ? "  ->", oQry:FieldGet( 1 ), oQry:FieldGet( 2 ), oQry:FieldGet( 3 )
   ENDDO
   oQry:Destroy()

   IF !oDB:Execute( "DELETE FROM clientes WHERE id = 1" )
      ? "Erro ao excluir registro:", oDB:Error()
      oDB:Close()
      RETURN
   ENDIF
   ? "- Registro ID 1 deletado."

   ? "- Lendo registros apos delecao:"
   oQry := oDB:Query( "SELECT * FROM clientes ORDER BY id" )
   IF oQry:NetErr()
      ? "Erro na consulta:", oQry:Error()
      oQry:Destroy()
      oDB:Close()
      RETURN
   ENDIF
   DO WHILE oQry:Fetch()
      ? "  ->", oQry:FieldGet( 1 ), oQry:FieldGet( 2 ), oQry:FieldGet( 3 )
   ENDDO
   oQry:Destroy()

   oDB:Close()
   ? "- Conexao da classe encerrada."
RETURN

// ------------------------------------------------------------------
// TESTE 2: DuckDBRDD v2 usando navegacao Harbour/xBase
// ------------------------------------------------------------------
PROCEDURE TesteRDD()
   LOCAL nConn, aStru

   ? ">>> TESTE 2: DuckDBRDD v2 <<<"

   // Banco em memoria para permitir execucoes repetidas.
   nConn := DBDUCKDBCONNECTION( "" )
   IF nConn == 0
      ? "Erro ao iniciar conexao no RDD."
      RETURN
   ENDIF
   ? "- Conexao RDD iniciada."

   aStru := { ;
      { "ID",     "N",  9, 0 }, ;
      { "NOME",   "C", 50, 0 }, ;
      { "LIMITE", "N", 15, 2 }  ;
   }

   dbCreate( "clientes_rdd", aStru, "DUCKDBRDD" )
   dbUseArea( .T., "DUCKDBRDD", "clientes_rdd", "CLI", .F. )
   IF Select( "CLI" ) == 0
      ? "Erro ao abrir a tabela clientes_rdd."
      DBDUCKDBCLEARCONNECTION( nConn )
      RETURN
   ENDIF

   DUCKDB_SETPK( "CLI", "ID" )
   ? "- Tabela 'clientes_rdd' criada e PK configurada."

   dbAppend()
   CLI->ID     := 100
   CLI->NOME   := "Carlos Roberto"
   CLI->LIMITE := 5000.00
   dbCommit()

   dbAppend()
   CLI->ID     := 101
   CLI->NOME   := "Ana Paula"
   CLI->LIMITE := 8750.50
   dbCommit()
   ? "- 2 registros inseridos via dbAppend()."

   ? "- Lendo registros:"
   CLI->( dbGoTop() )
   DO WHILE !CLI->( EOF() )
      ? "  ->", CLI->ID, CLI->NOME, CLI->LIMITE
      CLI->( dbSkip() )
   ENDDO

   CLI->( dbGoTop() )
   IF CLI->ID == 100
      CLI->( dbDelete() )
   ENDIF
   ? "- Registro ID 100 deletado via dbDelete()."

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
