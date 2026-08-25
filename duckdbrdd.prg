// +--------------------------------------------------------------------
// +    Programa  : duckdbrdd.prg
// +    Sistema   : RDD Nativo para DuckDB (Espelho de FB5RDD)
// +    Linguagem : Harbour
// +--------------------------------------------------------------------

#include "rddsys.ch"
#include "usrrdd.ch"
#include "fileio.ch"
#include "error.ch"
#include "dbstruct.ch"
#include "dbinfo.ch"   
#include "duckdb.ch"


#define AREA_CONN         1
#define AREA_TABLE        2
#define AREA_PK           3
#define AREA_CACHE        4
#define AREA_RECNO        5
#define AREA_ROWBUF       6
#define AREA_APPEND       7
#define AREA_EOF          8
#define AREA_BOF          9
#define AREA_FIELDS       10
#define AREA_STRUCT       11
#define AREA_QUERY        12
#define AREA_FETCHED_EOF  13
#define AREA_TYPES        14
#define AREA_LEN          14

ANNOUNCE DUCKDBRDD

STATIC s_aConnections := {}

// +--------------------------------------------------------------------
// +    Funcoes de Gerenciamento de Conexao e Transacao 
// +--------------------------------------------------------------------

FUNCTION DBDUCKDBCONNECTION( cDatabase, nDialect, cAlias, cConnStr )
   LOCAL db, cDir, cName, cExt
   
   // Valores padrao para garantir compatibilidade
   IF cAlias == NIL; cAlias := "db_conn"; ENDIF
   IF cConnStr == NIL; cConnStr := ""; ENDIF

   // 1. Auto-deteccao do dialeto pela extensao do arquivo se nDialect nao for informado
   IF nDialect == NIL .OR. nDialect == 0
      hb_FNameSplit( cDatabase, @cDir, @cName, @cExt )
      cExt := Lower( cExt )
      
      DO CASE
         CASE cExt == ".duckdb" .OR. cExt == ".db"
            nDialect := 1   // DIALETO_DUCKDB
            
         CASE cExt == ".sqlite" .OR. cExt == ".sqlite3"
            nDialect := 3   // DIALETO_SQLITE
            
         CASE cExt == ".csv"
            nDialect := 4   // DIALETO_CSV
            
         CASE cExt == ".json"
            nDialect := 5   // DIALETO_JSON
            
         CASE cExt == ".parquet"
            nDialect := 6   // DIALETO_PARQUET
            
         CASE cExt == ".mdb"
            nDialect := 103 // DIALETO_ODBC_MDB
            
         CASE cExt == ".accdb"
            nDialect := 104 // DIALETO_ODBC_ACCDB
            
         CASE cExt == ".gdb" .OR. cExt == ".fdb"
            nDialect := 105 // DIALETO_ODBC_FIREBIRD
            
         OTHERWISE
            nDialect := 0   // Mantem 0 (Conexao Nativa Direta)
      ENDCASE
   ENDIF

   // 2. Definicao do Hospedeiro (Memory para SGBDs/Arquivos anexos)
   // Se for nativo (0) ou DuckDB explicitamente (1), conecta no arquivo.
   IF nDialect > 1
      db := DuckDBConnect( ":memory:" )
   ELSE
      db := DuckDBConnect( cDatabase )
   ENDIF
   
   IF HB_ISNUMERIC( db )
      Alert( "Erro ao conectar DuckDB via RDD (Cod): " + hb_ntos( db ) )
      RETURN 0
   ENDIF

   // 3. Aciona o tratamento de dialeto e carrega as extensoes (Apenas > 1)
   IF nDialect > 1
      IF !TratarDialeto_RDD( db, cDatabase, nDialect, cAlias, cConnStr )
         DuckDBClose( db )
         RETURN 0
      ENDIF
   ENDIF

   // 4. Guarda o contexto completo no array estatico
   AAdd( s_aConnections, { db, nDialect, cAlias, cConnStr } )
   RETURN Len( s_aConnections )

STATIC FUNCTION TratarDialeto_RDD( db, cDatabase, nDialect, cAlias, cConnStr )
   LOCAL cSql := ""

   DO CASE
      // =========================================================
      // BANCOS DE DADOS EM ARQUIVO (VIA ATTACH)
      // =========================================================
      CASE nDialect == 2 // DIALETO_DUCKLAKE
         DuckDBExecute( db, "INSTALL ducklake; LOAD ducklake;" )
         cSql := "ATTACH 'ducklake:" + cDatabase + "' AS " + cAlias + ";"
         
      CASE nDialect == 3 // DIALETO_SQLITE
         DuckDBExecute( db, "INSTALL sqlite; LOAD sqlite;" )
         cSql := "ATTACH '" + cDatabase + "' AS " + cAlias + " (TYPE sqlite);"
         
      // =========================================================
      // SGBDs NATIVOS (DBMS via ATTACH)
      // =========================================================
      CASE nDialect == 100 // DIALETO_MYSQL (ou MariaDB)
         DuckDBExecute( db, "INSTALL mysql; LOAD mysql;" )
         IF !Empty( cConnStr )
            cSql := "ATTACH '" + cConnStr + "' AS " + cAlias + " (TYPE mysql);"
         ELSE
            cSql := "ATTACH '" + cDatabase + "' AS " + cAlias + " (TYPE mysql);"
         ENDIF
         
      CASE nDialect == 101 // DIALETO_POSTGRES
         DuckDBExecute( db, "INSTALL postgres; LOAD postgres;" )
         IF !Empty( cConnStr )
            cSql := "ATTACH '" + cConnStr + "' AS " + cAlias + " (TYPE postgres);"
         ELSE
            cSql := "ATTACH '" + cDatabase + "' AS " + cAlias + " (TYPE postgres);"
         ENDIF
         
      // =========================================================
      // SGBDs VIA ODBC SCANNER 
      // =========================================================
      CASE nDialect >= 102 .AND. nDialect <= 108
         DuckDBExecute( db, "INSTALL odbc; LOAD odbc;" )
         cSql := "SET VARIABLE " + cAlias + " = odbc_connect('" + cConnStr + "');"
   ENDCASE

   IF !Empty( cSql )
      DuckDBExecute( db, cSql )
   ENDIF

   RETURN .T.
   
FUNCTION DBDUCKDBGETHANDLE( nConn )
   IF nConn > 0 .AND. nConn <= Len( s_aConnections )
      RETURN s_aConnections[ nConn ]
   ENDIF
   RETURN NIL   

FUNCTION DBDUCKDBCLEARCONNECTION( nConn )
   LOCAL db
   IF nConn > 0 .AND. nConn <= Len( s_aConnections )
      db := s_aConnections[ nConn ][ 1 ]
      IF !Empty( db )
         DuckDBClose( db ) 
         s_aConnections[ nConn ] := NIL
      ENDIF
   ENDIF
   RETURN SUCCESS

FUNCTION DBDUCKDBCOMMIT( nConn )
   LOCAL db := s_aConnections[ nConn ][ 1 ]
   RETURN DuckDBExecute( db, "COMMIT" )

FUNCTION DBDUCKDBROLLBACK( nConn )
   LOCAL db := s_aConnections[ nConn ][ 1 ]
   RETURN DuckDBExecute( db, "ROLLBACK" )

// +--------------------------------------------------------------------
// +    Configuração de Chave Primária
// +--------------------------------------------------------------------

FUNCTION DUCKDB_SETPK( cAlias, cFields )
   LOCAL nWA, aWAData
   
   IF PCount() == 1
      cFields := cAlias
      nWA := Select()
   ELSE
      nWA := Select( cAlias )
      IF nWA == 0; nWA := Select(); ENDIF
   ENDIF
   
   IF nWA > 0
      aWAData := USRRDD_AREADATA( nWA )
      IF aWAData != NIL
         aWAData[ AREA_PK ] := hb_ATokens( StrTran( cFields, " ", "" ), "," )
         RETURN .T.
      ENDIF
   ENDIF
   RETURN .F.

STATIC FUNCTION DUCKDB_INIT( nRDD )
 USRRDD_RDDDATA( nRDD )
  RETURN SUCCESS

STATIC FUNCTION DUCKDB_NEW( pWA )
   LOCAL aWAData := Array( AREA_LEN )
   
   // INICIALIZAÇÃO BLINDADA: Previne o erro "Called from LEN(0)" no dbAppend()
   aWAData[ AREA_CONN ]        := NIL
   aWAData[ AREA_TABLE ]       := ""
   aWAData[ AREA_PK ]          := {}
   aWAData[ AREA_CACHE ]       := {}
   aWAData[ AREA_RECNO ]       := 0
   aWAData[ AREA_ROWBUF ]      := NIL
   aWAData[ AREA_APPEND ]      := .F.
   aWAData[ AREA_EOF ]         := .T.
   aWAData[ AREA_BOF ]         := .T.
   aWAData[ AREA_FIELDS ]      := {}
   aWAData[ AREA_STRUCT ]      := {}
   aWAData[ AREA_QUERY ]       := NIL
   aWAData[ AREA_FETCHED_EOF ] := .T.
   aWAData[ AREA_TYPES ]       := {}
   
   USRRDD_AREADATA( pWA, aWAData )
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_ADDFIELD( nWA, aField )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   IF aWAData != NIL
      IF !HB_ISARRAY( aWAData[ AREA_STRUCT ] )
         aWAData[ AREA_STRUCT ] := {}
      ENDIF
      AAdd( aWAData[ AREA_STRUCT ], aField )
   ENDIF
   RETURN UR_SUPER_ADDFIELD( nWA, aField )

STATIC FUNCTION DUCKDB_OPEN( nWA, aOpenInfo )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   LOCAL db, qry, oError
   LOCAL i, nCols, aStru, aField
   LOCAL cName, nType, nSize, nDec, cType
   LOCAL cDir, cTableName, cExt, cTableRef
   LOCAL nDialect, cAlias

   hb_FNameSplit( aOpenInfo[ UR_OI_NAME ], @cDir, @cTableName, @cExt )
   cTableName := AllTrim( cTableName )

   IF !Empty( aOpenInfo[ UR_OI_CONNECT ] ) .AND. aOpenInfo[ UR_OI_CONNECT ] <= Len( s_aConnections )
      // Modificado para recuperar o array inteiro da conexao selecionada
      aWAData[ AREA_CONN ] := s_aConnections[ aOpenInfo[ UR_OI_CONNECT ] ]
   ELSEIF Len( s_aConnections ) > 0
      aWAData[ AREA_CONN ] := s_aConnections[ Len( s_aConnections ) ]
   ENDIF
   
   db       := aWAData[ AREA_CONN ][ 1 ]
   nDialect := aWAData[ AREA_CONN ][ 2 ] // Resgata o Dialeto salvo
   cAlias   := aWAData[ AREA_CONN ][ 3 ] // Resgata o Alias do ATTACH

   IF Empty( db )
      oError := ErrorNew(); oError:GenCode := EG_OPEN; oError:Description := "Nenhuma conexao DuckDB ativa."
      UR_SUPER_ERROR( nWA, oError ); RETURN FAILURE
   ENDIF

// Resolve o nome correto da tabela baseado no dialeto utilizado
   DO CASE
      CASE nDialect == 4 // DIALETO_CSV
         cTableRef := "read_csv_auto('" + aOpenInfo[ UR_OI_NAME ] + "')"
         
      CASE nDialect == 5 // DIALETO_JSON
         cTableRef := "read_json_auto('" + aOpenInfo[ UR_OI_NAME ] + "')"
         
      CASE nDialect == 6 // DIALETO_PARQUET
         cTableRef := "read_parquet('" + aOpenInfo[ UR_OI_NAME ] + "')"
         
      CASE nDialect >= 102 .AND. nDialect <= 108 // SGBDs via ODBC Scanner
         cTableRef := "odbc_scan(GETVARIABLE('" + cAlias + "'), '" + cTableName + "')"
         
      CASE ( nDialect >= 2 .AND. nDialect <= 3 ) .OR. ( nDialect == 100 .OR. nDialect == 101 )
         // DuckLake, SQLite, MySQL e Postgres possuem ATTACH, acessamos pelo prefixo
         cTableRef := cAlias + "." + cTableName
         
      OTHERWISE // Padrao (0) ou DuckDB Nativo (1) - Nao precisa de alias
         cTableRef := cTableName
   ENDCASE



   // Salva a referencia final no aWAData. Isso fara com que DUCKDB_FLUSH e DELETE funcionem sozinhos
   aWAData[ AREA_TABLE ] := cTableRef

   aWAData[ AREA_FIELDS ] := {}
   aWAData[ AREA_TYPES ]  := {}

   // Usa o cTableRef para ler a estrutura corretamente
   qry := DuckDBQuery( db, "SELECT * FROM " + cTableRef + " LIMIT 0" )
   
   // ... [MANTENHA O RESTANTE DA DUCKDB_OPEN INALTERADO] ...
   
   IF !HB_ISARRAY( qry ) .OR. Len( qry ) < 6
      oError := ErrorNew(); oError:GenCode := EG_OPEN; oError:Description := "Falha ao ler estrutura da tabela no DuckDB."
      UR_SUPER_ERROR( nWA, oError ); RETURN FAILURE
   ENDIF

   nCols := qry[ 4 ] 
   aStru := qry[ 6 ] 

   UR_SUPER_SETFIELDEXTENT( nWA, nCols )

   FOR i := 1 TO nCols
      cName := Upper( AllTrim( aStru[ i ][ 1 ] ) )
      nType := aStru[ i ][ 2 ] 
      
      nSize := iif( aStru[ i ][ 3 ] == NIL, 0, aStru[ i ][ 3 ] )
      nDec  := iif( aStru[ i ][ 4 ] == NIL, 0, aStru[ i ][ 4 ] )

      SWITCH nType
         CASE "BOOLEAN"; cType := HB_FT_LOGICAL; nSize := 1; nDec := 0; EXIT
         CASE "VARCHAR"; CASE "CHAR"; cType := HB_FT_STRING; EXIT
         CASE "INTEGER"; CASE "TINYINT"; CASE "SMALLINT"; cType := HB_FT_INTEGER; EXIT
         CASE "BIGINT"; cType := HB_FT_LONG; EXIT
         CASE "DOUBLE"; CASE "FLOAT"; CASE "DECIMAL"; CASE "NUMERIC"; cType := HB_FT_DOUBLE; EXIT
         CASE "DATE"; CASE "TIMESTAMP"; cType := HB_FT_DATE; nSize := 8; nDec := 0; EXIT
         CASE "BLOB"; cType := HB_FT_MEMO; nSize := 10; nDec := 0; EXIT
         OTHERWISE; cType := HB_FT_STRING; nDec := 0
      ENDSWITCH

      aField := Array( UR_FI_SIZE )
      aField[ UR_FI_NAME ] := cName
      aField[ UR_FI_TYPE ] := cType
      
      IF nSize <= 0
         DO CASE
            CASE cType == HB_FT_STRING;  nSize := 250
            CASE cType == HB_FT_DOUBLE;  nSize := 18; nDec := 4
            CASE cType == HB_FT_INTEGER; nSize := 10
            CASE cType == HB_FT_LONG;    nSize := 15
         ENDCASE
      ENDIF
      
      aField[ UR_FI_LEN ]  := nSize
      aField[ UR_FI_DEC ]  := nDec
      
      AAdd( aWAData[ AREA_FIELDS ], cName )
      AAdd( aWAData[ AREA_TYPES ],  cType )
      UR_SUPER_ADDFIELD( nWA, aField )
   NEXT

   aWAData[ AREA_FETCHED_EOF ] := .T.
   aWAData[ AREA_RECNO ]       := 0
   aWAData[ AREA_BOF ]         := .T.
   aWAData[ AREA_EOF ]         := .T.
   
   UR_SUPER_OPEN( nWA, aOpenInfo )
   RETURN SUCCESS

   
STATIC FUNCTION DUCKDB_FETCH_NEXT( nWA )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   LOCAL qry := aWAData[ AREA_QUERY ]
   LOCAL aRow, i, nCols, xVal, cType

   IF aWAData[ AREA_FETCHED_EOF ]; RETURN .F.; ENDIF

   IF DuckDBFetch( qry ) == 0
      nCols := qry[ 4 ]
      aRow  := Array( nCols )
      
      FOR i := 1 TO nCols
         xVal  := DuckDBGetData( qry, i )
         cType := aWAData[ AREA_TYPES ][ i ]

         IF xVal == NIL
            DO CASE
               CASE cType == HB_FT_STRING .OR. cType == HB_FT_MEMO; xVal := ""
               CASE cType == HB_FT_DOUBLE .OR. cType == HB_FT_LONG .OR. cType == HB_FT_INTEGER; xVal := 0
               CASE cType == HB_FT_LOGICAL; xVal := .F.
               CASE cType == HB_FT_DATE; xVal := CToD("")
            ENDCASE
         ELSE
            IF cType == HB_FT_LOGICAL
               xVal := ( Val( xVal ) == 1 .OR. Upper( AllTrim( xVal ) ) == "T" .OR. xVal == .T. )
            ELSEIF cType == HB_FT_DATE
               xVal := hb_SToD( Left( xVal, 4 ) + SubStr( xVal, 5, 2 ) + SubStr( xVal, 7, 2 ) )
            ELSEIF cType == HB_FT_DOUBLE .OR. cType == HB_FT_LONG .OR. cType == HB_FT_INTEGER
               xVal := Val( xVal )
            ENDIF
         ENDIF
         aRow[ i ] := xVal
      NEXT
      AAdd( aWAData[ AREA_CACHE ], aRow )
      RETURN .T.
   ENDIF
   
   aWAData[ AREA_FETCHED_EOF ] := .T.
   RETURN .F.

STATIC FUNCTION DUCKDB_CLOSE( nWA )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   IF !Empty( aWAData[ AREA_QUERY ] )
      DuckDBFree( aWAData[ AREA_QUERY ] )
      aWAData[ AREA_QUERY ] := NIL
   ENDIF
   aWAData[ AREA_CACHE ]  := {}; aWAData[ AREA_ROWBUF ] := NIL
   RETURN UR_SUPER_CLOSE( nWA )

STATIC FUNCTION DUCKDB_GETVALUE( nWA, nField, xValue )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   IF aWAData[ AREA_APPEND ] .AND. !Empty( aWAData[ AREA_ROWBUF ] )
      xValue := aWAData[ AREA_ROWBUF ][ nField ]
   ELSEIF aWAData[ AREA_RECNO ] > 0 .AND. aWAData[ AREA_RECNO ] <= Len( aWAData[ AREA_CACHE ] )
      xValue := aWAData[ AREA_CACHE ][ aWAData[ AREA_RECNO ], nField ]
   ENDIF
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_PUTVALUE( nWA, nField, xValue )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   IF Empty( aWAData[ AREA_ROWBUF ] )
      IF aWAData[ AREA_RECNO ] > 0 .AND. aWAData[ AREA_RECNO ] <= Len( aWAData[ AREA_CACHE ] )
         aWAData[ AREA_ROWBUF ] := AClone( aWAData[ AREA_CACHE ][ aWAData[ AREA_RECNO ] ] )
      ELSE
         aWAData[ AREA_ROWBUF ] := Array( Len( aWAData[ AREA_FIELDS ] ) )
      ENDIF
   ENDIF
   aWAData[ AREA_ROWBUF ][ nField ] := xValue
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_SKIP( nWA, nRecords )
   LOCAL aWAData := USRRDD_AREADATA( nWA ), nNewRec
   IF !Empty( aWAData[ AREA_ROWBUF ] ); DUCKDB_FLUSH( nWA ); ENDIF

   nNewRec := aWAData[ AREA_RECNO ] + nRecords
   WHILE nNewRec > Len( aWAData[ AREA_CACHE ] ) .AND. !aWAData[ AREA_FETCHED_EOF ]
      DUCKDB_FETCH_NEXT( nWA )
   ENDDO

   IF Len( aWAData[ AREA_CACHE ] ) == 0
      aWAData[ AREA_BOF ] := .T.; aWAData[ AREA_EOF ] := .T.
   ELSEIF nNewRec > Len( aWAData[ AREA_CACHE ] )
      aWAData[ AREA_RECNO ] := Len( aWAData[ AREA_CACHE ] ) + 1
      aWAData[ AREA_EOF ] := .T.; aWAData[ AREA_BOF ] := .F.
   ELSEIF nNewRec < 1
      aWAData[ AREA_RECNO ] := 1
      aWAData[ AREA_BOF ] := .T.; aWAData[ AREA_EOF ] := .F.
   ELSE
      aWAData[ AREA_RECNO ] := nNewRec
      aWAData[ AREA_BOF ] := .F.; aWAData[ AREA_EOF ] := .F.
   ENDIF
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_GOTOP( nWA ); RETURN DUCKDB_GOTO( nWA, 1 )
STATIC FUNCTION DUCKDB_GOBOTTOM( nWA )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   WHILE !aWAData[ AREA_FETCHED_EOF ]; DUCKDB_FETCH_NEXT( nWA ); ENDDO
   RETURN DUCKDB_GOTO( nWA, Len( aWAData[ AREA_CACHE ] ) )

STATIC FUNCTION DUCKDB_GOTOID( nWA, nRecord ); RETURN DUCKDB_GOTO( nWA, nRecord )
STATIC FUNCTION DUCKDB_GOTO( nWA, nRecord )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   IF !Empty( aWAData[ AREA_ROWBUF ] ); DUCKDB_FLUSH( nWA ); ENDIF
   WHILE nRecord > Len( aWAData[ AREA_CACHE ] ) .AND. !aWAData[ AREA_FETCHED_EOF ]
      DUCKDB_FETCH_NEXT( nWA )
   ENDDO
   IF nRecord >= 1 .AND. nRecord <= Len( aWAData[ AREA_CACHE ] )
      aWAData[ AREA_RECNO ] := nRecord
      aWAData[ AREA_EOF ] := .F.; aWAData[ AREA_BOF ] := .F.
   ENDIF
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_RECCOUNT( nWA, nRecords )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   nRecords := Len( aWAData[ AREA_CACHE ] )
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_BOF( nWA, lBof ); lBof := USRRDD_AREADATA( nWA )[ AREA_BOF ]; RETURN SUCCESS
STATIC FUNCTION DUCKDB_EOF( nWA, lEof ); lEof := USRRDD_AREADATA( nWA )[ AREA_EOF ]; RETURN SUCCESS
STATIC FUNCTION DUCKDB_RECID( nWA, nRecNo ); nRecNo := USRRDD_AREADATA( nWA )[ AREA_RECNO ]; RETURN SUCCESS

STATIC FUNCTION DUCKDB_APPEND( nWA, nRecords )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   HB_SYMBOL_UNUSED( nRecords )
   aWAData[ AREA_ROWBUF ] := Array( Len( aWAData[ AREA_FIELDS ] ) )
   aWAData[ AREA_APPEND ] := .T.; aWAData[ AREA_EOF ] := .T.
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_FLUSH( nWA )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   LOCAL db      := aWAData[ AREA_CONN ][ 1 ]
   LOCAL cSql, cFields, cValues, cWhere, i, nPosPK, oError, qryIns

   IF !Empty( aWAData[ AREA_ROWBUF ] )
      IF aWAData[ AREA_APPEND ]
         cFields := ""; cValues := ""
         FOR i := 1 TO Len( aWAData[ AREA_FIELDS ] )
            IF aWAData[ AREA_ROWBUF ][ i ] != NIL
               IF !( cFields == "" )
                  cFields += ", "; cValues += ", "
               ENDIF
               cFields += aWAData[ AREA_FIELDS ][ i ]
               cValues += DUCKDB_ValToSql( aWAData[ AREA_ROWBUF ][ i ] )
            ENDIF
         NEXT
         
         cSql := "INSERT INTO " + aWAData[ AREA_TABLE ] + " (" + cFields + ") VALUES (" + cValues + ")"
         IF !Empty( aWAData[ AREA_PK ] )
            cSql += " RETURNING " + aWAData[ AREA_PK ][ 1 ]
         ENDIF
         
         IF "RETURNING" $ cSql
             qryIns := DuckDBQuery( db, cSql )
             IF HB_ISARRAY( qryIns )
                IF DuckDBFetch( qryIns ) == 0
                   nPosPK := AScan( aWAData[ AREA_FIELDS ], aWAData[ AREA_PK ][ 1 ] )
                   aWAData[ AREA_ROWBUF ][ nPosPK ] := Val( DuckDBGetData( qryIns, 1 ) )
                ENDIF
                DuckDBFree( qryIns )
             ENDIF
         ELSE
             DuckDBExecute( db, cSql )
         ENDIF
      ELSE
         IF Empty( aWAData[ AREA_PK ] )
            oError := ErrorNew(); oError:Description := "DUCKDBRDD: UPDATE abortado sem Primary Key."
            UR_SUPER_ERROR( nWA, oError ); RETURN FAILURE
         ENDIF
         
         cSql := "UPDATE " + aWAData[ AREA_TABLE ] + " SET "
         FOR i := 1 TO Len( aWAData[ AREA_FIELDS ] )
            IF aWAData[ AREA_ROWBUF ][ i ] != NIL
               IF i > 1; cSql += ", "; ENDIF
               cSql += aWAData[ AREA_FIELDS ][ i ] + " = " + DUCKDB_ValToSql( aWAData[ AREA_ROWBUF ][ i ] )
            ENDIF
         NEXT
         
         cWhere := ""
         FOR i := 1 TO Len( aWAData[ AREA_PK ] )
            nPosPK := AScan( aWAData[ AREA_FIELDS ], aWAData[ AREA_PK ][ i ] )
            IF nPosPK > 0
               IF i > 1; cWhere += " AND "; ENDIF
               cWhere += aWAData[ AREA_PK ][ i ] + " = " + DUCKDB_ValToSql( aWAData[ AREA_CACHE ][ aWAData[ AREA_RECNO ], nPosPK ] )
            ENDIF
         NEXT
         cSql += " WHERE " + cWhere
         DuckDBExecute( db, cSql )
      ENDIF

      IF aWAData[ AREA_APPEND ]
         AAdd( aWAData[ AREA_CACHE ], AClone( aWAData[ AREA_ROWBUF ] ) )
         aWAData[ AREA_APPEND ] := .F.; aWAData[ AREA_RECNO ]  := Len( aWAData[ AREA_CACHE ] )
      ELSE
         aWAData[ AREA_CACHE ][ aWAData[ AREA_RECNO ] ] := AClone( aWAData[ AREA_ROWBUF ] )
      ENDIF
      aWAData[ AREA_ROWBUF ] := NIL
   ENDIF
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_DELETE( nWA )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   LOCAL db      := aWAData[ AREA_CONN ][ 1 ]
   LOCAL cSql, cWhere := "", i, nPosPK, oError 

   IF Empty( aWAData[ AREA_PK ] )
      oError := ErrorNew(); oError:Description := "DUCKDBRDD: DELETE abortado sem Primary Key."
      UR_SUPER_ERROR( nWA, oError ); RETURN FAILURE
   ENDIF

   IF aWAData[ AREA_RECNO ] > 0 .AND. aWAData[ AREA_RECNO ] <= Len( aWAData[ AREA_CACHE ] )
      FOR i := 1 TO Len( aWAData[ AREA_PK ] )
         nPosPK := AScan( aWAData[ AREA_FIELDS ], aWAData[ AREA_PK ][ i ] )
         IF nPosPK > 0
            IF i > 1; cWhere += " AND "; ENDIF
            cWhere += aWAData[ AREA_PK ][ i ] + " = " + DUCKDB_ValToSql( aWAData[ AREA_CACHE ][ aWAData[ AREA_RECNO ], nPosPK ] )
         ENDIF
      NEXT
      
      cSql := "DELETE FROM " + aWAData[ AREA_TABLE ] + " WHERE " + cWhere
      DuckDBExecute( db, cSql )
      
      ADel( aWAData[ AREA_CACHE ], aWAData[ AREA_RECNO ] )
      ASize( aWAData[ AREA_CACHE ], Len( aWAData[ AREA_CACHE ] ) - 1 )
      IF aWAData[ AREA_RECNO ] > Len( aWAData[ AREA_CACHE ] ); aWAData[ AREA_EOF ] := .T.; ENDIF
   ENDIF
   RETURN SUCCESS

STATIC FUNCTION DUCKDB_ValToSql( xField )
   SWITCH ValType( xField )
   CASE "C"; CASE "M"; RETURN "'" + StrTran( xField, "'", "''" ) + "'"
   CASE "D"
      IF Empty( xField ); RETURN "NULL"; ENDIF
      RETURN "'" + StrZero( Year( xField ), 4 ) + "-" + StrZero( Month( xField ), 2 ) + "-" + StrZero( Day( xField ), 2 ) + "'"
   CASE "N"; RETURN Str( xField )
   CASE "L"; RETURN iif( xField, "TRUE", "FALSE" )
   ENDSWITCH
   RETURN "NULL"


STATIC FUNCTION DUCKDB_CREATE( nWA, aOpenInfo )
   LOCAL aWAData := USRRDD_AREADATA( nWA )
   LOCAL db, oError, cSql, n
   LOCAL cDir, cName, cExt, cTableName
   LOCAL aStruct    := aWAData[ AREA_STRUCT ]
   LOCAL mFldNm, mFldType, mFldLen, mFldDec

   // Extrai estritamente o nome da tabela (remove caminhos e a extensao .duckdb)
   hb_FNameSplit( aOpenInfo[ UR_OI_NAME ], @cDir, @cName, @cExt )
   cTableName := AllTrim( cName )

   IF !Empty( aOpenInfo[ UR_OI_CONNECT ] ) .AND. aOpenInfo[ UR_OI_CONNECT ] <= Len( s_aConnections )
      db := s_aConnections[ aOpenInfo[ UR_OI_CONNECT ] ][ 1 ]
   ELSEIF Len( s_aConnections ) > 0
      db := s_aConnections[ Len( s_aConnections ) ][ 1 ]
   ENDIF

   IF Empty( db )
      oError := ErrorNew()
      oError:GenCode     := EG_OPEN
      oError:Description := hb_langErrMsg( EG_OPEN ) + ", Nenhuma conexao DuckDB ativa para dbCreate()."
      oError:FileName    := cTableName
      UR_SUPER_ERROR( nWA, oError )
      RETURN FAILURE
   ENDIF

   cSql := "CREATE TABLE " + cTableName + " ( "

   FOR n := 1 TO Len( aStruct )
      mFldNm   := aStruct[ n, UR_FI_NAME ]
      mFldType := aStruct[ n, UR_FI_TYPE ]
      mFldLen  := aStruct[ n, UR_FI_LEN ]
      mFldDec  := aStruct[ n, UR_FI_DEC ]

      IF n > 1
         cSql += ", "
      ENDIF

      cSql += AllTrim( mFldNm ) + " "

      DO CASE
         CASE mFldType == HB_FT_AUTOINC .OR. mFldNm == "SR_RECNO"
            cSql += "INTEGER PRIMARY KEY"
            
         CASE mFldType == HB_FT_STRING .OR. mFldType == HB_FT_ANY
            cSql += "VARCHAR"
            
         CASE mFldType == HB_FT_DATE
            cSql += "DATE"
            
         CASE mFldType == HB_FT_DOUBLE .OR. mFldType == HB_FT_INTEGER .OR. mFldType == HB_FT_LONG
            IF mFldDec > 0
               cSql += "DECIMAL(" + hb_ntos( mFldLen ) + "," + hb_ntos( mFldDec ) + ")"
            ELSE
               IF mFldLen <= 4
                  cSql += "SMALLINT"
               ELSEIF mFldLen <= 9
                  cSql += "INTEGER"
               ELSE
                  cSql += "BIGINT"
               ENDIF
            ENDIF
            
         CASE mFldType == HB_FT_LOGICAL
            cSql += "BOOLEAN DEFAULT FALSE"
            
         CASE mFldType == HB_FT_MEMO .OR. mFldType == HB_FT_BLOB
            cSql += "BLOB"
            
         OTHERWISE
            cSql += "VARCHAR"
      ENDCASE
   NEXT
   
   cSql += " )"

   DuckDBExecute( db, cSql )

   RETURN SUCCESS
      
STATIC FUNCTION DUCKDB_RDDINFO( nIndex, cargo )
   LOCAL xRet := NIL
   DO CASE
      CASE nIndex == RDDI_TABLEEXT; xRet := ".duckdb" 
      CASE nIndex == RDDI_MEMOEXT; xRet := "" 
      CASE nIndex == RDDI_ORDBAGEXT; xRet := "" 
      OTHERWISE; xRet := UR_SUPER_RDDINFO( nIndex, cargo )
   ENDCASE
RETURN xRet



STATIC FUNCTION DUCKDB_INFO( nWA, nIndex, cargo )
   LOCAL xRet := NIL
   DO CASE
      CASE nIndex == DBI_ISDBF; xRet := .F.
      CASE nIndex == DBI_CANPUTREC; xRet := .T.
      OTHERWISE; xRet := UR_SUPER_INFO( nWA, nIndex, cargo )
   ENDCASE
RETURN xRet   


FUNCTION DUCKDBRDD_GETFUNCTABLE( pFuncCount, pFuncTable, pSuperTable, nRddID )
   LOCAL cSuperRDD := NIL
   LOCAL aMyFunc[ UR_METHODCOUNT ]

   aMyFunc[ UR_INIT ]     := ( @DUCKDB_INIT() )
   aMyFunc[ UR_NEW ]      := ( @DUCKDB_NEW() )
   aMyFunc[ UR_ADDFIELD ] := ( @DUCKDB_ADDFIELD() ) 
   aMyFunc[ UR_OPEN ]     := ( @DUCKDB_OPEN() )
   aMyFunc[ UR_CLOSE ]    := ( @DUCKDB_CLOSE() )
   aMyFunc[ UR_GETVALUE ] := ( @DUCKDB_GETVALUE() )
   aMyFunc[ UR_PUTVALUE ] := ( @DUCKDB_PUTVALUE() )
   aMyFunc[ UR_SKIP ]     := ( @DUCKDB_SKIP() )
   aMyFunc[ UR_GOTO ]     := ( @DUCKDB_GOTO() )
   aMyFunc[ UR_GOTOID ]   := ( @DUCKDB_GOTOID() )
   aMyFunc[ UR_GOTOP ]    := ( @DUCKDB_GOTOP() )
   aMyFunc[ UR_GOBOTTOM ] := ( @DUCKDB_GOBOTTOM() )
   aMyFunc[ UR_RECCOUNT ] := ( @DUCKDB_RECCOUNT() )
   aMyFunc[ UR_RECID ]    := ( @DUCKDB_RECID() )
   aMyFunc[ UR_BOF ]      := ( @DUCKDB_BOF() )
   aMyFunc[ UR_EOF ]      := ( @DUCKDB_EOF() )
   aMyFunc[ UR_FLUSH ]    := ( @DUCKDB_FLUSH() )
   aMyFunc[ UR_APPEND ]   := ( @DUCKDB_APPEND() )
   aMyFunc[ UR_DELETE ]   := ( @DUCKDB_DELETE() )
   aMyFunc[ UR_RDDINFO ]  := ( @DUCKDB_RDDINFO() )
   aMyFunc[ UR_INFO ]     := ( @DUCKDB_INFO() )
   aMyFunc[ UR_CREATE ]   := ( @DUCKDB_CREATE() )

   RETURN USRRDD_GETFUNCTABLE( pFuncCount, pFuncTable, pSuperTable, nRddID, cSuperRDD, aMyFunc )

INIT PROC DUCKDB_INIT_REGISTER()
   rddRegister( "DUCKDBRDD", RDT_FULL )
   RETURN