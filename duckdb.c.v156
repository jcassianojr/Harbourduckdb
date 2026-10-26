/*
 * DuckDB DBMS low-level (client API) interface code for Harbour
 * Adapted for Harbour Project (Mirror of firebird.c)
 * Updated to DuckDB 1.5.6+ Chunk/Vector API
 */

#include "hbapi.h"
#include "hbapierr.h"
#include "hbapiitm.h"
#include "duckdb.h"
#include <string.h>

/* Estruturas de controle de Conexão e Resultados (Agora com Cache de Chunks) */

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
   
   /* Novas propriedades para o cache da Chunk API */
   duckdb_data_chunk current_chunk;
   idx_t current_chunk_idx;
   idx_t chunk_start_row;
   idx_t chunk_end_row;
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
         hb_xfree( p->last_error );
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
   HB_DUCKDB * p;
   HB_DUCKDB ** pp;

   // Se o caminho for vazio ou omitido, abre banco em memória
   if( hb_parclen( 1 ) == 0 )
      db_path = NULL;

   if( duckdb_open_ext( db_path, &db, NULL, &err_msg ) == DuckDBError )
   {
      if( err_msg )
      {
         hb_retc( err_msg );
         duckdb_free( err_msg );
      }
      else
      {
         hb_retc( "Erro desconhecido ao abrir banco DuckDB." );
      }
      return;
   }

   if( duckdb_connect( db, &conn ) == DuckDBError )
   {
      duckdb_close( &db );
      hb_retc( "Erro ao estabelecer conexao com o banco DuckDB." );
      return;
   }

   p = ( HB_DUCKDB * ) hb_xgrab( sizeof( HB_DUCKDB ) );
   p->db = db;
   p->conn = conn;
   p->last_error = NULL;

   pp = ( HB_DUCKDB ** ) hb_gcAllocate( sizeof( HB_DUCKDB * ), &s_gcHB_DUCKDBFuncs );
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
         {
            hb_xfree( p->last_error );
            p->last_error = NULL;
         }

         const char * err = duckdb_result_error( &res );
         if( err )
         {
            p->last_error = hb_strdup( err );
         }

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
         {
            hb_xfree( p->last_error );
            p->last_error = NULL;
         }

         const char * err = duckdb_result_error( &( pRes->result ) );
         if( err )
         {
            p->last_error = hb_strdup( err );
         }

         duckdb_destroy_result( &( pRes->result ) );
         hb_xfree( pRes );
         hb_retnl( -1 );
         return;
      }

      pRes->current_row = 0;
      pRes->total_cols  = duckdb_column_count( &( pRes->result ) );

      /* Conta as linhas somando o tamanho dos Chunks */
      pRes->total_rows = 0;
      idx_t chunk_count = duckdb_result_chunk_count( pRes->result );
      idx_t i;
      
      for( i = 0; i < chunk_count; i++ )
      {
         duckdb_data_chunk temp_chunk = duckdb_result_get_chunk( pRes->result, i );
         pRes->total_rows += duckdb_data_chunk_get_size( temp_chunk );
         duckdb_destroy_data_chunk( &temp_chunk );
      }
      
      pRes->current_chunk = NULL;
      pRes->current_chunk_idx = 0;
      pRes->chunk_start_row = 0;
      pRes->chunk_end_row = 0;

      PHB_ITEM aStruct  = hb_itemArrayNew( pRes->total_cols );
      PHB_ITEM aColTemp = hb_itemNew( NULL );

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
      hb_arraySetNLL( qry_handle, 3, ( HB_MAXINT ) pRes->total_rows );
      hb_arraySetNLL( qry_handle, 4, ( HB_MAXINT ) pRes->total_cols );
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
            hb_retnl( 0 );
            return;
         }
      }
   }
   hb_retnl( -1 );
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
         idx_t target_row = ( idx_t ) ( nRow - 1 );

         if ( pRes->current_chunk == NULL || target_row < pRes->chunk_start_row || target_row >= pRes->chunk_end_row )
         {
            if ( pRes->current_chunk )
            {
               duckdb_destroy_data_chunk( &(pRes->current_chunk) );
               pRes->current_chunk = NULL;
            }
            
            idx_t chunk_count = duckdb_result_chunk_count( pRes->result );
            idx_t current_row = 0;
            idx_t i;
            
            for ( i = 0; i < chunk_count; i++ )
            {
               duckdb_data_chunk chunk = duckdb_result_get_chunk( pRes->result, i );
               idx_t size = duckdb_data_chunk_get_size( chunk );
               
               if ( target_row < current_row + size )
               {
                  pRes->current_chunk = chunk;
                  pRes->current_chunk_idx = i;
                  pRes->chunk_start_row = current_row;
                  pRes->chunk_end_row = current_row + size;
                  break;
               }
               else
               {
                  current_row += size;
                  duckdb_destroy_data_chunk( &chunk );
               }
            }
         }
         
         if ( pRes->current_chunk == NULL )
         {
            hb_ret();
            return;
         }
         
         idx_t row_in_chunk = target_row - pRes->chunk_start_row;
         duckdb_vector vector = duckdb_data_chunk_get_vector( pRes->current_chunk, col_idx );
         
         uint64_t * validity = duckdb_vector_get_validity( vector );
         if ( validity != NULL && !duckdb_validity_row_is_valid( validity, row_in_chunk ) )
         {
            hb_ret(); 
            return;
         }
         
         duckdb_type type = duckdb_column_type( &(pRes->result), col_idx );
         
         switch ( type )
         {
            case DUCKDB_TYPE_BOOLEAN: {
               bool * bool_data = (bool *) duckdb_vector_get_data( vector );
               hb_retl( bool_data[ row_in_chunk ] );
               break;
            }
            case DUCKDB_TYPE_TINYINT: {
               int8_t * int_data = (int8_t *) duckdb_vector_get_data( vector );
               hb_retni( (int) int_data[ row_in_chunk ] );
               break;
            }
            case DUCKDB_TYPE_SMALLINT: {
               int16_t * int_data = (int16_t *) duckdb_vector_get_data( vector );
               hb_retni( (int) int_data[ row_in_chunk ] );
               break;
            }
            case DUCKDB_TYPE_INTEGER: {
               int32_t * int_data = (int32_t *) duckdb_vector_get_data( vector );
               hb_retnl( (long) int_data[ row_in_chunk ] );
               break;
            }
            case DUCKDB_TYPE_BIGINT: {
               int64_t * int_data = (int64_t *) duckdb_vector_get_data( vector );
               hb_retnll( (HB_LONGLONG) int_data[ row_in_chunk ] );
               break;
            }
            case DUCKDB_TYPE_FLOAT: {
               float * float_data = (float *) duckdb_vector_get_data( vector );
               hb_retnd( (double) float_data[ row_in_chunk ] );
               break;
            }
            case DUCKDB_TYPE_DOUBLE: {
               double * double_data = (double *) duckdb_vector_get_data( vector );
               hb_retnd( double_data[ row_in_chunk ] );
               break;
            }
            case DUCKDB_TYPE_VARCHAR: {
               duckdb_string_t * string_data = (duckdb_string_t *) duckdb_vector_get_data( vector );
               duckdb_string_t str_val = string_data[ row_in_chunk ];
               
               const char * str_ptr = duckdb_string_t_data( &str_val );
               idx_t str_len = (idx_t) duckdb_string_t_length( str_val ); // Corrigido para passar por valor[cite: 13]
               
               hb_retclen( str_ptr, ( HB_SIZE ) str_len );
               break;
            }
            default: {
               char * val_str = duckdb_value_varchar( &( pRes->result ), ( idx_t ) col_idx, target_row );
               if( val_str )
               {
                  hb_retc( val_str );
                  duckdb_free( val_str );
               }
               else
               {
                  hb_ret();
               }
               break;
            }
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
         if( pRes->current_chunk )
         {
            duckdb_destroy_data_chunk( &( pRes->current_chunk ) );
         }

         duckdb_destroy_result( &( pRes->result ) );
         hb_xfree( pRes );
         hb_arraySetPtr( aParam, 1, NULL );
         hb_retnl( 1 );
         return;
      }
   }
   hb_retnl( 0 );
}