/*
 * DuckDB DBMS low-level (client API) interface code for Harbour
 * Adapted for Harbour Project (Mirror of firebird.c)
 */

#include "hbapi.h"
#include "hbapierr.h"
#include "hbapiitm.h"

#include "duckdb.h"

/* Estruturas de controle de Conexão e Resultados */

typedef struct
{
   duckdb_database db;
   duckdb_connection conn;
   char * last_error;
} HB_DUCKDB;

typedef struct
{
   duckdb_result result;
   idx_t current_row;
   idx_t total_rows;
   idx_t total_cols;
} HB_DUCKDB_RESULT;

/* Garbage Collector Handlers para a Conexão */

static HB_GARBAGE_FUNC( HB_DUCKDB_release )
{
   HB_DUCKDB ** pp = ( HB_DUCKDB ** ) Cargo;

   if( pp && *pp )
   {
      HB_DUCKDB * p = *pp;

      if( p->conn )
      {
         duckdb_disconnect( &( p->conn ) );
         p->conn = NULL;
      }
      if( p->db )
      {
         duckdb_close( &( p->db ) );
         p->db = NULL;
      }
      if( p->last_error )
      {
         duckdb_free( p->last_error );
         p->last_error = NULL;
      }

      hb_xfree( p );
      *pp = NULL;
   }
}

static const HB_GC_FUNCS s_gcHB_DUCKDBFuncs =
{
   HB_DUCKDB_release,
   hb_gcDummyMark
};

static HB_DUCKDB * hb_duckdb_par( int iParam )
{
   HB_DUCKDB ** pp = ( HB_DUCKDB ** ) hb_parptrGC( &s_gcHB_DUCKDBFuncs, iParam );
   return ( pp && *pp ) ? *pp : NULL;
}

/* API Wrappers */

HB_FUNC( DUCKDBCONNECT )
{
   const char * db_path = hb_parcx( 1 );
   duckdb_database db;
   duckdb_connection conn;
   char * err_msg = NULL;

   // Se o caminho for vazio ou omitido, abre banco em memória
   if( hb_parclen( 1 ) == 0 )
      db_path = NULL;

   if( duckdb_open_ext( db_path, &db, NULL, &err_msg ) == DuckDBError )
   {
      if( err_msg )
         duckdb_free( err_msg );
      hb_retnl( -1 );
      return;
   }

   if( duckdb_connect( db, &conn ) == DuckDBError )
   {
      duckdb_close( &db );
      hb_retnl( -2 );
      return;
   }

   HB_DUCKDB * p = ( HB_DUCKDB * ) hb_xgrab( sizeof( HB_DUCKDB ) );
   p->db = db;
   p->conn = conn;
   p->last_error = NULL;

   HB_DUCKDB ** pp = ( HB_DUCKDB ** ) hb_gcAllocate( sizeof( HB_DUCKDB * ), &s_gcHB_DUCKDBFuncs );
   *pp = p;

   hb_retptrGC( pp );
}

HB_FUNC( DUCKDBCLOSE )
{
   HB_DUCKDB * p = hb_duckdb_par( 1 );

   if( p )
   {
      if( p->conn )
      {
         duckdb_disconnect( &( p->conn ) );
         p->conn = NULL;
      }
      if( p->db )
      {
         duckdb_close( &( p->db ) );
         p->db = NULL;
      }
      hb_retnl( 1 );
   }
   else
   {
      hb_retnl( 0 );
   }
}

HB_FUNC( DUCKDBERROR )
{
   HB_DUCKDB * p = hb_duckdb_par( 1 );

   if( p && p->last_error )
   {
      hb_retc( p->last_error );
   }
   else
   {
      hb_retc( "" );
   }
}

HB_FUNC( DUCKDBEXECUTE )
{
   HB_DUCKDB * p = hb_duckdb_par( 1 );
   const char * sql = hb_parcx( 2 );

   if( p && p->conn && sql )
   {
      duckdb_result res;

      if( duckdb_query( p->conn, sql, &res ) == DuckDBError )
      {
         if( p->last_error )
            duckdb_free( p->last_error );

         const char * err = duckdb_result_error( &res );
         p->last_error = err ? hb_strdup( err ) : NULL;

         duckdb_destroy_result( &res );
         hb_retnl( -1 );
      }
      else
      {
         duckdb_destroy_result( &res );
         hb_retnl( 1 );
      }
   }
   else
   {
      hb_retnl( -1 );
   }
}

HB_FUNC( DUCKDBQUERY )
{
   HB_DUCKDB * p = hb_duckdb_par( 1 );
   const char * sql = hb_parcx( 2 );

   if( p && p->conn && sql )
   {
      HB_DUCKDB_RESULT * pRes = ( HB_DUCKDB_RESULT * ) hb_xgrab( sizeof( HB_DUCKDB_RESULT ) );

      if( duckdb_query( p->conn, sql, &( pRes->result ) ) == DuckDBError )
      {
         if( p->last_error )
            duckdb_free( p->last_error );

         const char * err = duckdb_result_error( &( pRes->result ) );
         p->last_error = err ? hb_strdup( err ) : NULL;

         duckdb_destroy_result( &( pRes->result ) );
         hb_xfree( pRes );
         hb_retnl( -1 );
         return;
      }

      pRes->current_row = 0;
      pRes->total_rows  = duckdb_row_count( &( pRes->result ) );
      pRes->total_cols  = duckdb_column_count( &( pRes->result ) );

      PHB_ITEM aStruct  = hb_itemArrayNew( pRes->total_cols );
      PHB_ITEM aColTemp = hb_itemNew( NULL );

      idx_t i;
      for( i = 0; i < pRes->total_cols; i++ )
      {
         const char * col_name = duckdb_column_name( &( pRes->result ), i );
         duckdb_type col_type  = duckdb_column_type( &( pRes->result ), i );

         const char * type_str = "VARCHAR";
         long nSize = 255;
         long nDec  = 0;

         switch( col_type )
         {
            case DUCKDB_TYPE_BOOLEAN:
               type_str = "BOOLEAN";
               nSize = 1;
               break;
            case DUCKDB_TYPE_TINYINT:
            case DUCKDB_TYPE_SMALLINT:
               type_str = "SMALLINT";
               nSize = 5;
               break;
            case DUCKDB_TYPE_INTEGER:
               type_str = "INTEGER";
               nSize = 9;
               break;
            case DUCKDB_TYPE_BIGINT:
            case DUCKDB_TYPE_HUGEINT:
               type_str = "BIGINT";
               nSize = 19;
               break;
            case DUCKDB_TYPE_FLOAT:
            case DUCKDB_TYPE_DOUBLE:
            case DUCKDB_TYPE_DECIMAL:
               type_str = "DOUBLE";
               nSize = 15;
               nDec = 4;
               break;
            case DUCKDB_TYPE_DATE:
               type_str = "DATE";
               nSize = 8;
               break;
            case DUCKDB_TYPE_TIME:
               type_str = "TIME";
               nSize = 10;
               break;
            case DUCKDB_TYPE_TIMESTAMP:
               type_str = "TIMESTAMP";
               nSize = 19;
               break;
            case DUCKDB_TYPE_BLOB:
               type_str = "BLOB";
               nSize = 10;
               break;
            default:
               type_str = "VARCHAR";
               nSize = 255;
               break;
         }

         hb_arrayNew( aColTemp, 7 );
         hb_arraySetC(  aColTemp, 1, col_name ? col_name : "" );
         hb_arraySetC(  aColTemp, 2, type_str );
         hb_arraySetNL( aColTemp, 3, nSize );
         hb_arraySetNL( aColTemp, 4, nDec );
         hb_arraySetC(  aColTemp, 5, "" );
         hb_arraySetNL( aColTemp, 6, 0 );
         hb_arraySetC(  aColTemp, 7, col_name ? col_name : "" );

         hb_arraySetForward( aStruct, ( HB_SIZE ) ( i + 1 ), aColTemp );
      }

      hb_itemRelease( aColTemp );

      PHB_ITEM qry_handle = hb_itemArrayNew( 6 );
      hb_arraySetPtr( qry_handle, 1, ( void * ) pRes );
      hb_arraySetNL(  qry_handle, 2, 0 );
      hb_arraySetNL(  qry_handle, 3, ( long ) pRes->total_rows );
      hb_arraySetNL(  qry_handle, 4, ( long ) pRes->total_cols );
      hb_arraySetNI(  qry_handle, 5, 3 );
      hb_arraySetForward( qry_handle, 6, aStruct );

      hb_itemReturnRelease( qry_handle );
      hb_itemRelease( aStruct );
   }
   else
   {
      hb_retnl( -1 );
   }
}

HB_FUNC( DUCKDBFETCH )
{
   PHB_ITEM aParam = hb_param( 1, HB_IT_ARRAY );

   if( aParam )
   {
      HB_DUCKDB_RESULT * pRes = ( HB_DUCKDB_RESULT * ) hb_itemGetPtr( hb_itemArrayGet( aParam, 1 ) );
      long nRow = hb_itemGetNL( hb_itemArrayGet( aParam, 2 ) );

      if( pRes )
      {
         nRow++;
         if( ( idx_t ) nRow <= pRes->total_rows && pRes->total_rows > 0 )
         {
            hb_arraySetNL( aParam, 2, nRow );
            pRes->current_row = ( idx_t ) nRow;
            hb_retnl( 0 ); // Sucesso
            return;
         }
      }
   }
   hb_retnl( -1 ); // EOF ou erro
}

HB_FUNC( DUCKDBGETDATA )
{
   PHB_ITEM aParam = hb_param( 1, HB_IT_ARRAY );
   int col_idx = hb_parni( 2 ) - 1;

   if( aParam && col_idx >= 0 )
   {
      HB_DUCKDB_RESULT * pRes = ( HB_DUCKDB_RESULT * ) hb_itemGetPtr( hb_itemArrayGet( aParam, 1 ) );
      long nRow = hb_itemGetNL( hb_itemArrayGet( aParam, 2 ) );

      if( pRes && nRow > 0 && ( idx_t ) nRow <= pRes->total_rows && col_idx < ( int ) pRes->total_cols )
      {
         idx_t row_idx = ( idx_t ) ( nRow - 1 );

         char * val_str = duckdb_value_varchar( &( pRes->result ), ( idx_t ) col_idx, row_idx );
         if( ! val_str )
         {
            hb_ret(); // Retorna NIL
         }
         else
         {
            hb_retc( val_str );
            duckdb_free( val_str );
         }
         return;
      }
   }
   hb_ret();
}

HB_FUNC( DUCKDBFREE )
{
   PHB_ITEM aParam = hb_param( 1, HB_IT_ARRAY );

   if( aParam )
   {
      HB_DUCKDB_RESULT * pRes = ( HB_DUCKDB_RESULT * ) hb_itemGetPtr( hb_itemArrayGet( aParam, 1 ) );

      if( pRes )
      {
         duckdb_destroy_result( &( pRes->result ) );
         hb_xfree( pRes );
         hb_arraySetPtr( aParam, 1, NULL );
         hb_retnl( 1 );
         return;
      }
   }
   hb_retnl( 0 );
}