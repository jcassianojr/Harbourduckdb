/*
 * DuckDB RDBMS low-level interface code.
 * Adapted for Harbour Project (DuckDBClass - Espelho do Fb5class)
 */

#include "hbclass.ch"
#include "duckdb.ch"


CREATE CLASS DuckDBClass

   VAR db
   VAR trans
   VAR StartedTrans
   VAR nError
   VAR lError
   VAR dialect
   VAR charset

   METHOD New( cDatabase, cUser, cPassword, nDialect, cCharSet, cAlias ) // <-- Adicionado cAlias aqui também
   METHOD TratarDialeto( cDatabase, nDialect, cAlias )                   // <-- NOVA DECLARAÇÃO AQUI
   
   METHOD Destroy()  INLINE DuckDBClose( ::db )
   METHOD Close()    INLINE DuckDBClose( ::db )

   METHOD TableExists( cTable )
   METHOD ListTables( cSchema )
   METHOD TableStruct( cTable )

   METHOD StartTransaction()
   METHOD Commit()
   METHOD Rollback()

   METHOD Execute( cQuery )
   METHOD Query( cQuery )

   METHOD Update( oRow, cWhere )
   METHOD Delete( oRow, cWhere )
   METHOD Append( oRow )
   METHOD GetServerInfo()

   METHOD NetErr()   INLINE ::lError
   METHOD Error()    INLINE DuckDBError( ::nError )
   METHOD ErrorNo()  INLINE ::nError

ENDCLASS


METHOD New( cDatabase, cUser, cPassword, nDialect, cCharSet, cAlias ) CLASS DuckDBClass
   LOCAL cDir, cName, cExt

   hb_default( @cDatabase, "" )
   hb_default( @cCharSet, "UTF8" )

   HB_SYMBOL_UNUSED( cUser )
   HB_SYMBOL_UNUSED( cPassword )

   // 1. Extrai informações do arquivo para autodetecção e geração de alias
   IF !Empty( cDatabase )
      hb_FNameSplit( cDatabase, @cDir, @cName, @cExt )
      cExt := Lower( cExt )
   ELSE
      cName := "memoria"
      cExt  := ""
   ENDIF

   // Se o usuário não informou o alias, assume o nome do arquivo
   IF Empty( cAlias )
      cAlias := cName 
   ENDIF

   // 2. Autodetecção do Dialeto caso não seja informado
   IF Empty( nDialect )
      DO CASE
         CASE Empty( cDatabase ) .OR. cExt == ".duckdb"
            nDialect := DIALETO_DUCKDB
         CASE cExt == ".ducklake"
            nDialect := DIALETO_DUCKLAKE
         CASE cExt == ".sqlite" .OR. cExt == ".db"
            nDialect := DIALETO_SQLITE
         CASE cExt == ".csv"
            nDialect := DIALETO_CSV
         CASE cExt == ".json"
            nDialect := DIALETO_JSON
         CASE cExt == ".parquet"
            nDialect := DIALETO_PARQUET
         OTHERWISE
            nDialect := DIALETO_DUCKDB 
      ENDCASE
   ENDIF

   ::Dialect := nDialect
   ::lError := .F.
   ::nError := 0
   ::StartedTrans := .F.
   ::charset := cCharSet

   // 3. Regra do Hospedeiro (Sem usar variável intermediária):
   // Se for DUCKDB, conecta direto no arquivo. Senão, conecta em memória ("").
   IF nDialect == DIALETO_DUCKDB
      ::db := DuckDBConnect( cDatabase )
   ELSE
      ::db := DuckDBConnect( "" )
   ENDIF

   IF HB_ISNUMERIC( ::db )
      ::lError := .T.
      ::nError := ::db
      RETURN Self
   ENDIF

   // 4. Se NÃO for DuckDB nativo, invoca a rotina de dialetos
   IF nDialect != DIALETO_DUCKDB .AND. !Empty( cDatabase )
      ::TratarDialeto( cDatabase, nDialect, cAlias )
   ENDIF

   RETURN Self

METHOD TratarDialeto( cDatabase, nDialect, cAlias ) CLASS DuckDBClass
   LOCAL cSql := ""

   DO CASE
      // =========================================================
      // BANCOS DE DADOS ANEXÁVEIS (ATTACH)
      // =========================================================
      CASE nDialect == DIALETO_SQLITE
         // Requer carga da extensão sqlite
         ::Execute( "INSTALL sqlite; LOAD sqlite;" )
         cSql := "ATTACH '" + cDatabase + "' AS " + cAlias + " (TYPE sqlite);"
         
      CASE nDialect == DIALETO_DUCKLAKE
         // Requer carga da extensão ducklake
         ::Execute( "INSTALL ducklake; LOAD ducklake;" )
         cSql := "ATTACH 'ducklake:" + cDatabase + "' AS " + cAlias + ";"

      // =========================================================
      // ARQUIVOS TABULARES (Criação de VIEWs para simular alias)
      // =========================================================
      CASE nDialect == DIALETO_CSV
         cSql := "CREATE VIEW " + cAlias + " AS SELECT * FROM read_csv('" + cDatabase + "', auto_detect=true);"
         
      CASE nDialect == DIALETO_JSON
         cSql := "CREATE VIEW " + cAlias + " AS SELECT * FROM read_json('" + cDatabase + "', auto_detect=true);"
         
      CASE nDialect == DIALETO_PARQUET
         cSql := "CREATE VIEW " + cAlias + " AS SELECT * FROM read_parquet('" + cDatabase + "');"

      // =========================================================
      // SGBDs (DBMS) - Espaço reservado a partir de 100
      // =========================================================
      CASE nDialect == DIALETO_MYSQL
         // ::Execute( "INSTALL mysql; LOAD mysql;" )
         // cSql := "ATTACH '" + cDatabase + "' AS " + cAlias + " (TYPE mysql);"
         
      CASE nDialect == DIALETO_POSTGRES
         // ::Execute( "INSTALL postgres; LOAD postgres;" )
         // cSql := "ATTACH '" + cDatabase + "' AS " + cAlias + " (TYPE postgres);"
         
      CASE nDialect == DIALETO_ODBC
         // Implementação futura ODBC
         
   ENDCASE

   // Executa a instrução correspondente ao dialeto
   IF !Empty( cSql )
      IF !::Execute( cSql )
         // lError e nError já serão preenchidos internamente pelo método ::Execute
         // Opcional: Você pode colocar um Alert() ou Log aqui caso queira visibilidade imediata
      ENDIF
   ENDIF
   
RETURN .T.

METHOD StartTransaction() CLASS DuckDBClass
   LOCAL result := .F.
   LOCAL n := DuckDBExecute( ::db, "BEGIN TRANSACTION" )

   IF n < 0
      ::lError := .T.
      ::nError := n
   ELSE
      result := .T.
      ::lError := .F.
      ::nError := 0
      ::StartedTrans := .T.
   ENDIF

   RETURN result

METHOD Rollback() CLASS DuckDBClass
   LOCAL result := .F.
   LOCAL n

   IF ::StartedTrans
      IF ( n := DuckDBExecute( ::db, "ROLLBACK" ) ) < 0
         ::lError := .T.
         ::nError := n
      ELSE
         ::lError := .F.
         ::nError := 0
         result := .T.
         ::StartedTrans := .F.
      ENDIF
   ENDIF

   RETURN result

METHOD Commit() CLASS DuckDBClass
   LOCAL result := .F.
   LOCAL n

   IF ::StartedTrans
      IF ( n := DuckDBExecute( ::db, "COMMIT" ) ) < 0
         ::lError := .T.
         ::nError := n
      ELSE
         ::lError := .F.
         ::nError := 0
         result := .T.
         ::StartedTrans := .F.
      ENDIF
   ENDIF

   RETURN result

METHOD Execute( cQuery ) CLASS DuckDBClass
   LOCAL result
   LOCAL n

   cQuery := RemoveSpaces( cQuery )
   n := DuckDBExecute( ::db, cQuery )

   IF n < 0
      ::lError := .T.
      ::nError := n
      result := .F.
   ELSE
      ::lError := .F.
      ::nError := 0
      result := .T.
   ENDIF

   RETURN result

METHOD Query( cQuery ) CLASS DuckDBClass
   RETURN TDuckDBQuery():New( ::db, cQuery, ::dialect )

METHOD TableExists( cTable ) CLASS DuckDBClass
   LOCAL cQuery
   LOCAL result := .F.
   LOCAL qry

   cQuery := "SELECT table_name FROM information_schema.tables WHERE table_name = '" + Upper( AllTrim( cTable ) ) + "'"
   qry := DuckDBQuery( ::db, cQuery )

   IF HB_ISARRAY( qry )
      result := ( DuckDBFetch( qry ) == 0 )
      DuckDBFree( qry )
   ENDIF

   RETURN result

   
METHOD ListTables( cSchema ) CLASS DuckDBClass
   LOCAL result := {}
   LOCAL cQuery
   LOCAL qry

   // Se não passar nada, assume o padrão 'main' do DuckDB
   IF Empty( cSchema )
      cSchema := "main"
   ENDIF

   // Filtra as tabelas pelo schema correto
   cQuery := "SELECT table_name FROM information_schema.tables WHERE table_schema = '" + Lower(AllTrim( cSchema )) + "' ORDER BY table_name"
   
   qry := DuckDBQuery( ::db, RemoveSpaces( cQuery ) )

   IF HB_ISARRAY( qry )
      DO WHILE DuckDBFetch( qry ) == 0
         AAdd( result, DuckDBGetData( qry, 1 ) )
      ENDDO
      DuckDBFree( qry )
   ENDIF

   RETURN result   

METHOD TableStruct( cTable ) CLASS DuckDBClass
   LOCAL result := {}
   LOCAL cQuery, cType, nSize, cField, nType, nDec
   LOCAL qry

   cQuery := "SELECT column_name, data_type, character_maximum_length, numeric_scale "
   cQuery += "FROM information_schema.columns "
   cQuery += "WHERE table_name = '" + Upper( AllTrim( cTable ) ) + "' "
   cQuery += "ORDER BY ordinal_position"

   qry := DuckDBQuery( ::db, RemoveSpaces( cQuery ) )

   IF HB_ISARRAY( qry )
      DO WHILE DuckDBFetch( qry ) == 0
         cField  := RTrim( iif( DuckDBGetData( qry, 1 ) == NIL, "", DuckDBGetData( qry, 1 ) ) )
         nType   := iif( DuckDBGetData( qry, 2 ) == NIL, "", DuckDBGetData( qry, 2 ) )
         nSize   := Val( iif( DuckDBGetData( qry, 3 ) == NIL, "0", DuckDBGetData( qry, 3 ) ) )
         nDec    := Val( iif( DuckDBGetData( qry, 4 ) == NIL, "0", DuckDBGetData( qry, 4 ) ) )
         
         DO CASE
            CASE "BOOLEAN" $ nType
               cType := "L"; nSize := 1; nDec  := 0
            CASE "TINYINT" $ nType .OR. "SMALLINT" $ nType
               cType := "N"; nSize := 5
            CASE "INTEGER" $ nType .OR. "BIGINT" $ nType .OR. "HUGEINT" $ nType
               cType := "N"; nSize := 9
            CASE "FLOAT" $ nType .OR. "DOUBLE" $ nType .OR. "DECIMAL" $ nType
               cType := "N"; nSize := 15
            CASE "DATE" $ nType .OR. "TIMESTAMP" $ nType
               cType := "D"; nSize := 8; nDec := 0
            CASE "TIME" $ nType
               cType := "C"; nSize := 10; nDec := 0
            CASE "BLOB" $ nType
               cType := "M"; nSize := 10; nDec := 0
            OTHERWISE
               cType := "C"; nDec  := 0
               IF nSize == 0; nSize := 255; ENDIF
         ENDCASE

         AAdd( result, { cField, cType, nSize, nDec } )
      ENDDO
      DuckDBFree( qry )
   ENDIF

   RETURN result

METHOD Delete( oRow, cWhere ) CLASS DuckDBClass
   LOCAL result := .F.
   LOCAL aKeys, i, nField, xField, cQuery, aTables

   aTables := oRow:GetTables()

   IF ! HB_ISNUMERIC( ::db ) .AND. Len( aTables ) == 1
      IF cWhere == NIL
         aKeys := oRow:GetKeyField()

         cWhere := ""
         FOR i := 1 TO Len( aKeys )
            nField := oRow:FieldPos( aKeys[ i ] )
            xField := oRow:FieldGet( nField )

            cWhere += aKeys[ i ] + "=" + DataToSql( xField )

            IF i != Len( aKeys )
               cWhere += ","
            ENDIF
         NEXT
      ENDIF

      IF !( cWhere == "" )
         cQuery := 'DELETE FROM ' + aTables[ 1 ] + ' WHERE ' + cWhere
         result := ::Execute( cQuery )
      ENDIF
   ENDIF

   RETURN result

METHOD Append( oRow ) CLASS DuckDBClass
   LOCAL result := .F.
   LOCAL cQuery, i, aTables, aKeys, qryIns, nPosPK

   aTables := oRow:GetTables()

   IF ! HB_ISNUMERIC( ::db ) .AND. Len( aTables ) == 1
      cQuery := 'INSERT INTO ' + aTables[ 1 ] + '('
      FOR i := 1 TO oRow:FCount()
         IF oRow:Changed( i )
            cQuery += oRow:FieldName( i ) + ","
         ENDIF
      NEXT

      cQuery := Left( cQuery, Len( cQuery ) - 1 ) +  ") VALUES ("

      FOR i := 1 TO oRow:FCount()
         IF oRow:Changed( i )
            cQuery += DataToSql( oRow:FieldGet( i ) ) + ","
         ENDIF
      NEXT

      cQuery := Left( cQuery, Len( cQuery ) - 1  ) + ")"

      aKeys := oRow:GetKeyField()
      IF Len( aKeys ) == 1
         cQuery += " RETURNING " + aKeys[ 1 ]
         qryIns := DuckDBQuery( ::db, cQuery )
         IF HB_ISARRAY( qryIns )
            IF DuckDBFetch( qryIns ) == 0
               nPosPK := oRow:FieldPos( aKeys[ 1 ] )
               IF nPosPK > 0
                  oRow:FieldPut( nPosPK, Val( DuckDBGetData( qryIns, 1 ) ) )
               ENDIF
            ENDIF
            DuckDBFree( qryIns )
            result := .T.
         ENDIF
      ELSE
         result := ::Execute( cQuery )
      ENDIF
   ENDIF

   RETURN result

METHOD Update( oRow, cWhere ) CLASS DuckDBClass
   LOCAL result := .F.
   LOCAL aKeys, cQuery, i, nField, xField, aTables

   aTables := oRow:GetTables()

   IF ! HB_ISNUMERIC( ::db ) .AND. Len( aTables ) == 1
      IF cWhere == NIL
         aKeys := oRow:GetKeyField()

         cWhere := ""
         FOR i := 1 TO Len( aKeys )
            nField := oRow:FieldPos( aKeys[ i ] )
            xField := oRow:FieldGet( nField )

            cWhere += aKeys[ i ] + "=" + DataToSql( xField )

            IF i != Len( aKeys )
               cWhere += ", "
            ENDIF
         NEXT
      ENDIF

      cQuery := "UPDATE " + aTables[ 1 ] + " SET "
      FOR i := 1 TO oRow:FCount()
         IF oRow:Changed( i )
            cQuery += oRow:FieldName( i ) + " = " + DataToSql( oRow:FieldGet( i ) ) + ","
         ENDIF
      NEXT

      IF !( cWhere == "" )
         cQuery := Left( cQuery, Len( cQuery ) - 1 ) + " WHERE " + cWhere
         result := ::Execute( cQuery )
      ENDIF
   ENDIF

   RETURN result

METHOD GetServerInfo() CLASS DuckDBClass
   LOCAL oQuery, cVersion := ""

   oQuery := ::Query("SELECT version() AS VER")
   
   IF oQuery != NIL
      oQuery:Fetch() 
      IF !oQuery:Eof()
         cVersion := oQuery:FieldGet( 1 )
      ENDIF
      oQuery:Destroy()
   ENDIF

   RETURN AllTrim( cVersion )


CREATE CLASS TDuckDBQuery
   VAR      nError
   VAR      lError
   VAR      Dialect
   VAR      lBof
   VAR      lEof
   VAR      nRecno
   VAR      qry
   VAR      aStruct
   VAR      numcols
   VAR      closed
   VAR      db
   VAR      query
   VAR      aKeys
   VAR      aTables

   METHOD   New( nDB, cQuery, nDialect )
   METHOD   Destroy()
   METHOD   Close()            INLINE ::Destroy()
   METHOD   Refresh()
   METHOD   Fetch()
   METHOD   Skip()             INLINE ::Fetch()

   METHOD   Bof()              INLINE ::lBof
   METHOD   Eof()              INLINE ::lEof
   METHOD   RecNo()            INLINE ::nRecno

   METHOD   NetErr()           INLINE ::lError
   METHOD   Error()            INLINE DuckDBError( ::nError )
   METHOD   ErrorNo()          INLINE ::nError

   METHOD   FCount()           INLINE ::numcols
   METHOD   Struct()
   METHOD   FieldName( nField )
   METHOD   FieldPos( cField )
   METHOD   FieldLen( nField )
   METHOD   FieldDec( nField )
   METHOD   FieldType( nField )
   METHOD   LastRec()
   METHOD   FieldGet( nField )
   METHOD   GetRow()
   METHOD   GetBlankRow()
   METHOD   Blank()            INLINE ::GetBlankRow()
   METHOD   GetKeyField()
ENDCLASS

METHOD New( nDB, cQuery, nDialect ) CLASS TDuckDBQuery
   ::db := nDb
   ::query := RemoveSpaces( cQuery )
   ::dialect := nDialect
   ::closed := .T.
   ::aKeys := NIL
   ::Refresh()
   RETURN Self

METHOD LastRec() CLASS TDuckDBQuery
   LOCAL nTotal := 0
   LOCAL oQCount := TDuckDBQuery():New( ::db, "SELECT COUNT(*) FROM (" + ::query + ")", ::dialect )
   IF oQCount != NIL
      nTotal := Val( oQCount:FieldGet( 1 ) )
      oQCount:Destroy()
   ENDIF
   RETURN nTotal

METHOD Refresh() CLASS TDuckDBQuery
   LOCAL qry, result, i, aTable := {}

   IF ! ::closed
      ::Destroy()
   ENDIF

   ::lBof := .T.
   ::lEof := .F.
   ::nRecno := 0
   ::closed := .F.
   ::numcols := 0
   ::aStruct := {}
   ::nError := 0
   ::lError := .F.

   result := .T.

   qry := DuckDBQuery( ::db, ::query )

   IF HB_ISARRAY( qry )
      ::numcols := qry[ 4 ]
      ::aStruct := StructConvert( qry[ 6 ], ::db )

      ::lError := .F.
      ::nError := 0
      ::qry := qry

      FOR i := 1 TO Len( ::aStruct )
         IF hb_AScan( aTable, ::aStruct[ i ][ 5 ], , , .T. ) == 0
            AAdd( aTable, ::aStruct[ i ][ 5 ] )
         ENDIF
      NEXT
      ::aTables := aTable
   ELSE
      ::lError := .T.
      ::nError := qry
   ENDIF

   RETURN result

METHOD Destroy() CLASS TDuckDBQuery
   LOCAL result := .T.
   LOCAL n

   IF ! ::lError .AND. ( n := DuckDBFree( ::qry ) ) < 0
      ::lError := .T.
      ::nError := n
   ENDIF

   ::closed := .T.
   RETURN result

METHOD Fetch() CLASS TDuckDBQuery
   LOCAL result := .F.
   LOCAL fetch_stat

   IF ! ::lError .AND. ! ::lEof
      IF ! ::Closed
         fetch_stat := DuckDBFetch( ::qry )
         ::nRecno++

         IF fetch_stat == 0
            ::lBof := .F.
            result := .T.
         ELSE
            ::lEof := .T.
         ENDIF
      ENDIF
   ENDIF
   RETURN result

METHOD Struct() CLASS TDuckDBQuery
   LOCAL result := {}, i
   IF ! ::lError
      FOR i := 1 TO Len( ::aStruct )
         AAdd( result, { ::aStruct[ i ][ 1 ], ::aStruct[ i ][ 2 ], ::aStruct[ i ][ 3 ], ::aStruct[ i ][ 4 ] } )
      NEXT
   ENDIF
   RETURN result

METHOD FieldPos( cField ) CLASS TDuckDBQuery
   LOCAL result := 0
   IF ! ::lError
      result := AScan( ::aStruct, {| x | x[ 1 ] == RTrim( Upper( cField ) ) } )
   ENDIF
   RETURN result

METHOD FieldName( nField ) CLASS TDuckDBQuery
   LOCAL result
   IF ! ::lError .AND. nField >= 1 .AND. nField <= Len( ::aStruct )
      result := ::aStruct[ nField ][ 1 ]
   ENDIF
   RETURN result

METHOD FieldType( nField ) CLASS TDuckDBQuery
   LOCAL result
   IF ! ::lError .AND. nField >= 1 .AND. nField <= Len( ::aStruct )
      result := ::aStruct[ nField ][ 2 ]
   ENDIF
   RETURN result

METHOD FieldLen( nField ) CLASS TDuckDBQuery
   LOCAL result
   IF ! ::lError .AND. nField >= 1 .AND. nField <= Len( ::aStruct )
      result := ::aStruct[ nField ][ 3 ]
   ENDIF
   RETURN result

METHOD FieldDec( nField ) CLASS TDuckDBQuery
   LOCAL result
   IF ! ::lError .AND. nField >= 1 .AND. nField <= Len( ::aStruct )
      result := ::aStruct[ nField ][ 4 ]
   ENDIF
   RETURN result

METHOD FieldGet( nField ) CLASS TDuckDBQuery
   LOCAL result, cType

   IF ! ::lError .AND. nField >= 1 .AND. nField <= Len( ::aStruct ) .AND. ! ::closed
      result := DuckDBGetData( ::qry, nField )
      cType := ::aStruct[ nField ][ 2 ]

      IF cType == "M"
         IF result == NIL
            result := ""
         ENDIF
      ELSEIF cType == "N"
         IF result != NIL
            result := Val( result )
         ELSE
            result := 0
         ENDIF
      ELSEIF cType == "D"
         IF result != NIL
            result := hb_SToD( Left( result, 4 ) + SubStr( result, 5, 2 ) + SubStr( result, 7, 2 ) )
         ELSE
            result := hb_SToD()
         ENDIF
      ELSEIF cType == "L"
         IF result != NIL
            result := ( Val( result ) == 1 .OR. Upper( AllTrim( result ) ) == "T" .OR. result == .T. )
         ELSE
            result := .F.
         ENDIF
      ENDIF
   ENDIF
   RETURN result

METHOD Getrow() CLASS TDuckDBQuery
   LOCAL result, aRow, i
   IF ! ::lError .AND. ! ::closed
      aRow := Array( ::numcols )
      FOR i := 1 TO ::numcols
         aRow[ i ] := ::FieldGet( i )
      NEXT
      result := TDuckDBRow():New( aRow, ::aStruct, ::db, ::dialect, ::aTables )
   ENDIF
   RETURN result

METHOD GetBlankRow() CLASS TDuckDBQuery
   LOCAL result, aRow, i
   IF ! ::lError
      aRow := Array( ::numcols )
      FOR i := 1 TO ::numcols
         SWITCH ::aStruct[ i ][ 2 ]
         CASE "C"
         CASE "M"; aRow[ i ] := ""; EXIT
         CASE "N"; aRow[ i ] := 0; EXIT
         CASE "L"; aRow[ i ] := .F.; EXIT
         CASE "D"; aRow[ i ] := hb_SToD(); EXIT
         ENDSWITCH
      NEXT
      result := TDuckDBRow():New( aRow, ::aStruct, ::db, ::dialect, ::aTables )
   ENDIF
   RETURN result

METHOD GetKeyField() CLASS TDuckDBQuery
   IF ::aKeys == NIL
      ::aKeys := KeyField( ::aTables, ::db )
   ENDIF
   RETURN ::aKeys

CREATE CLASS TDuckDBRow
   VAR      aRow
   VAR      aStruct
   VAR      aChanged
   VAR      aKeys
   VAR      db
   VAR      dialect
   VAR      aTables

   METHOD   New( row, struct, nDB, nDialect, aTable )
   METHOD   Changed( nField )
   METHOD   GetTables()        INLINE ::aTables
   METHOD   FCount()           INLINE Len( ::aRow )
   METHOD   FieldGet( nField )
   METHOD   FieldPut( nField, Value )
   METHOD   FieldName( nField )
   METHOD   FieldPos( cField )
   METHOD   FieldLen( nField )
   METHOD   FieldDec( nField )
   METHOD   FieldType( nField )
   METHOD   GetKeyField()
ENDCLASS

METHOD new( row, struct, nDb, nDialect, aTable ) CLASS TDuckDBRow
   ::aRow := row
   ::aStruct := struct
   ::db := nDB
   ::dialect := nDialect
   ::aTables := aTable
   ::aChanged := Array( Len( row ) )
   RETURN Self

METHOD Changed( nField ) CLASS TDuckDBRow
   LOCAL result
   IF nField >= 1 .AND. Len( ::aChanged ) >= nField .AND. ::aChanged != NIL
      result := ( ::aChanged[ nField ] != NIL )
   ENDIF
   RETURN result

METHOD FieldGet( nField ) CLASS TDuckDBRow
   LOCAL result
   IF nField >= 1 .AND. nField <= Len( ::aRow )
      result := ::aRow[ nField ]
   ENDIF
   RETURN result

METHOD FieldPut( nField, Value ) CLASS TDuckDBRow
   LOCAL result
   IF nField >= 1 .AND. nField <= Len( ::aRow )
      ::aChanged[ nField ] := .T.
      result := ::aRow[ nField ] := Value
   ENDIF
   RETURN result

METHOD FieldName( nField ) CLASS TDuckDBRow
   LOCAL result
   IF nField >= 1 .AND. nField <= Len( ::aStruct )
      result := ::aStruct[ nField ][ 1 ]
   ENDIF
   RETURN result

METHOD FieldPos( cField ) CLASS TDuckDBRow
   RETURN AScan( ::aStruct, {| x | x[ 1 ] == RTrim( Upper( cField ) ) } )

METHOD FieldType( nField ) CLASS TDuckDBRow
   LOCAL result
   IF nField >= 1 .AND. nField <= Len( ::aStruct )
      result := ::aStruct[ nField ][ 2 ]
   ENDIF
   RETURN result

METHOD FieldLen( nField ) CLASS TDuckDBRow
   LOCAL result
   IF nField >= 1 .AND. nField <= Len( ::aStruct )
      result := ::aStruct[ nField ][ 3 ]
   ENDIF
   RETURN result

METHOD FieldDec( nField ) CLASS TDuckDBRow
   LOCAL result
   IF nField >= 1 .AND. nField <= Len( ::aStruct )
      result := ::aStruct[ nField ][ 4 ]
   ENDIF
   RETURN result

METHOD GetKeyField() CLASS TDuckDBRow
   IF ::aKeys == NIL
      ::aKeys := KeyField( ::aTables, ::db )
   ENDIF
   RETURN ::aKeys

STATIC FUNCTION KeyField( aTables, db )
   LOCAL cTable, cQuery, qry, aKeys := {}

   IF Len( aTables ) == 1
      cTable := aTables[ 1 ]
      cQuery := "SELECT constraint_column_names FROM duckdb_constraints() WHERE table_name = " + DataToSql( cTable ) + " AND constraint_type = 'PRIMARY KEY'"
      qry := DuckDBQuery( db, cQuery )

      IF HB_ISARRAY( qry )
         DO WHILE DuckDBFetch( qry ) == 0
            AAdd( aKeys, RTrim( DuckDBGetData( qry, 1 ) ) )
         ENDDO
         DuckDBFree( qry )
      ENDIF
   ENDIF
   RETURN aKeys

STATIC FUNCTION DataToSql( xField )
   SWITCH ValType( xField )
   CASE "C"; CASE "M"; RETURN "'" + StrTran( xField, "'", "''" ) + "'"
   CASE "D"
      IF Empty( xField ); RETURN "NULL"; ENDIF
      RETURN "'" + StrZero( Year( xField ), 4 ) + "-" + StrZero( Month( xField ), 2 ) + "-" + StrZero( Day( xField ), 2 ) + "'"
   CASE "N"; RETURN Str( xField )
   CASE "L"; RETURN iif( xField, "TRUE", "FALSE" )
   ENDSWITCH
   RETURN "NULL"

STATIC FUNCTION StructConvert( aStru, db )
   LOCAL aNew := {}
   LOCAL cField
   LOCAL cType
   LOCAL nSize
   LOCAL nDec
   LOCAL cTable
   LOCAL cDomain := ""
   LOCAL i
   
   HB_SYMBOL_UNUSED( db )
   
   FOR i := 1 TO Len( aStru )
      cField  := RTrim( aStru[ i ][ 7 ] )
      cType   := aStru[ i ][ 2 ] 
      nSize   := aStru[ i ][ 3 ]
      nDec    := aStru[ i ][ 4 ]
      cTable  := RTrim( aStru[ i ][ 5 ] )

      AAdd( aNew, { cField, cType, nSize, nDec, cTable, cDomain } )
   NEXT
   
   RETURN aNew

STATIC FUNCTION RemoveSpaces( cQuery )
   DO WHILE At( "  ", cQuery ) != 0
      cQuery := StrTran( cQuery, "  ", " " )
   ENDDO
   RETURN cQuery