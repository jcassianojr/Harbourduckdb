#include "hbapi.h"
#include "hbapiitm.h"
#include "hbapierr.h"
#include "duckdb.h"

#include <string.h>

typedef struct {
   duckdb_database db;
   duckdb_connection conn;
   char *last_error;
} HB_DUCKDB;

typedef struct {
   duckdb_result result;
   duckdb_data_chunk *chunks;
   idx_t chunk_count;
   idx_t chunk_capacity;
   idx_t total_rows;
   idx_t column_count;
   idx_t current_row;
} HB_DUCKDB_RESULT;

static void hb_duckdb_close_handles( HB_DUCKDB *db )
{
   if( !db ) {
      return;
   }
   if( db->conn ) {
      duckdb_disconnect( &db->conn );
      db->conn = NULL;
   }
   if( db->db ) {
      duckdb_close( &db->db );
      db->db = NULL;
   }
}

static HB_GARBAGE_FUNC( hb_duckdb_gc_release )
{
   HB_DUCKDB **slot = (HB_DUCKDB **) Cargo;
   if( slot && *slot ) {
      hb_duckdb_close_handles( *slot );
      if( (*slot)->last_error ) {
         hb_xfree( (*slot)->last_error );
      }
      hb_xfree( *slot );
      *slot = NULL;
   }
}

static const HB_GC_FUNCS s_hb_duckdb_gc_funcs = {
   hb_duckdb_gc_release,
   hb_gcDummyMark
};

static HB_DUCKDB *hb_duckdb_param( int param )
{
   HB_DUCKDB **slot = (HB_DUCKDB **) hb_parptrGC( &s_hb_duckdb_gc_funcs, param );
   return slot ? *slot : NULL;
}

static void hb_duckdb_clear_error( HB_DUCKDB *db )
{
   if( db && db->last_error ) {
      hb_xfree( db->last_error );
      db->last_error = NULL;
   }
}

static void hb_duckdb_set_error( HB_DUCKDB *db, const char *message )
{
   if( !db ) {
      return;
   }
   hb_duckdb_clear_error( db );
   if( message ) {
      db->last_error = hb_strdup( message );
   }
}

static HB_DUCKDB *hb_duckdb_new_handle( void )
{
   HB_DUCKDB *db = (HB_DUCKDB *) hb_xgrab( sizeof( HB_DUCKDB ) );
   memset( db, 0, sizeof( HB_DUCKDB ) );
   return db;
}

static void hb_duckdb_return_handle( HB_DUCKDB *db )
{
   HB_DUCKDB **slot;
   if( !db ) {
      hb_retni( -1 );
      return;
   }
   slot = (HB_DUCKDB **) hb_gcAllocate( sizeof( HB_DUCKDB * ), &s_hb_duckdb_gc_funcs );
   *slot = db;
   hb_retptrGC( slot );
}

static int hb_duckdb_open( HB_DUCKDB *db, const char *path )
{
   char *error = NULL;
   const char *db_path = path && path[0] ? path : NULL;
   if( duckdb_open_ext( db_path, &db->db, NULL, &error ) == DuckDBError ) {
      hb_duckdb_set_error( db, error ? error : "Falha ao abrir banco DuckDB." );
      if( error ) {
         duckdb_free( error );
      }
      return 0;
   }
   if( error ) {
      duckdb_free( error );
   }
   return 1;
}

static int hb_duckdb_connect( HB_DUCKDB *db )
{
   if( !db || !db->db ) {
      return 0;
   }
   if( db->conn ) {
      return 1;
   }
   if( duckdb_connect( db->db, &db->conn ) == DuckDBError ) {
      hb_duckdb_set_error( db, "Falha ao estabelecer conexao com DuckDB." );
      return 0;
   }
   hb_duckdb_clear_error( db );
   return 1;
}

static void hb_duckdb_destroy_result( HB_DUCKDB_RESULT *result )
{
   idx_t i;
   if( !result ) {
      return;
   }
   for( i = 0; i < result->chunk_count; ++i ) {
      duckdb_destroy_data_chunk( &result->chunks[i] );
   }
   if( result->chunks ) {
      hb_xfree( result->chunks );
   }
   duckdb_destroy_result( &result->result );
   hb_xfree( result );
}

static HB_DUCKDB_RESULT *hb_duckdb_result_from_item( PHB_ITEM item )
{
   if( item && HB_IS_ARRAY( item ) ) {
      return (HB_DUCKDB_RESULT *) hb_arrayGetPtr( item, 1 );
   }
   return NULL;
}

static const char *hb_duckdb_type_name( duckdb_type type, HB_SIZE *size, HB_SIZE *decimals )
{
   *size = 255;
   *decimals = 0;
   switch( type ) {
      case DUCKDB_TYPE_BOOLEAN: *size = 1; return "BOOLEAN";
      case DUCKDB_TYPE_TINYINT: *size = 4; return "TINYINT";
      case DUCKDB_TYPE_SMALLINT: *size = 6; return "SMALLINT";
      case DUCKDB_TYPE_INTEGER: *size = 11; return "INTEGER";
      case DUCKDB_TYPE_BIGINT: *size = 20; return "BIGINT";
      case DUCKDB_TYPE_UTINYINT: *size = 3; return "UTINYINT";
      case DUCKDB_TYPE_USMALLINT: *size = 5; return "USMALLINT";
      case DUCKDB_TYPE_UINTEGER: *size = 10; return "UINTEGER";
      case DUCKDB_TYPE_UBIGINT: *size = 20; return "UBIGINT";
      case DUCKDB_TYPE_HUGEINT: *size = 39; return "HUGEINT";
      case DUCKDB_TYPE_UHUGEINT: *size = 39; return "UHUGEINT";
      case DUCKDB_TYPE_FLOAT: *size = 15; *decimals = 4; return "FLOAT";
      case DUCKDB_TYPE_DOUBLE: *size = 24; *decimals = 8; return "DOUBLE";
      case DUCKDB_TYPE_DECIMAL: *size = 38; *decimals = 4; return "DECIMAL";
      case DUCKDB_TYPE_DATE: *size = 8; return "DATE";
      case DUCKDB_TYPE_TIME:
      case DUCKDB_TYPE_TIME_NS:
      case DUCKDB_TYPE_TIME_TZ: *size = 15; return "TIME";
      case DUCKDB_TYPE_TIMESTAMP:
      case DUCKDB_TYPE_TIMESTAMP_S:
      case DUCKDB_TYPE_TIMESTAMP_MS:
      case DUCKDB_TYPE_TIMESTAMP_NS:
      case DUCKDB_TYPE_TIMESTAMP_TZ:
      case DUCKDB_TYPE_TIMESTAMP_TZ_NS: *size = 23; return "TIMESTAMP";
      case DUCKDB_TYPE_BLOB: *size = 10; return "BLOB";
      case DUCKDB_TYPE_VARCHAR: return "VARCHAR";
      default: return "VARCHAR";
   }
}

static void hb_duckdb_make_column_metadata( PHB_ITEM structure, duckdb_result *result, idx_t index )
{
   const char *name = duckdb_column_name( result, index );
   duckdb_type type = duckdb_column_type( result, index );
   HB_SIZE size, decimals;
   const char *type_name = hb_duckdb_type_name( type, &size, &decimals );
   PHB_ITEM column = hb_itemArrayNew( 7 );

   if( type == DUCKDB_TYPE_DECIMAL ) {
      duckdb_logical_type logical_type = duckdb_column_logical_type( result, index );
      if( logical_type ) {
         size = (HB_SIZE) duckdb_decimal_width( logical_type );
         decimals = (HB_SIZE) duckdb_decimal_scale( logical_type );
         duckdb_destroy_logical_type( &logical_type );
      }
   }

   hb_arraySetC( column, 1, name ? name : "" );
   hb_arraySetC( column, 2, type_name );
   hb_arraySetNInt( column, 3, (HB_MAXINT) size );
   hb_arraySetNInt( column, 4, (HB_MAXINT) decimals );
   hb_arraySetC( column, 5, "" );
   hb_arraySetNL( column, 6, 0 );
   hb_arraySetC( column, 7, name ? name : "" );
   hb_arraySetForward( structure, (HB_SIZE) index + 1, column );
   hb_itemRelease( column );
}

static void hb_duckdb_ret_timestamp( duckdb_timestamp timestamp )
{
   duckdb_timestamp_struct parts = duckdb_from_timestamp( timestamp );
   long julian = 0;
   long millis;
   int a = ( 14 - parts.date.month ) / 12;
   int y = parts.date.year + 4800 - a;
   int m = parts.date.month + 12 * a - 3;
   julian = parts.date.day + ( 153 * m + 2 ) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
   millis = ( parts.time.hour * 3600000L ) + ( parts.time.min * 60000L ) +
            ( parts.time.sec * 1000L ) + ( parts.time.micros / 1000L );
   hb_rettdt( julian, millis );
}

static void hb_duckdb_ret_timestamp_micros( int64_t micros )
{
   duckdb_timestamp timestamp;
   timestamp.micros = micros;
   hb_duckdb_ret_timestamp( timestamp );
}

static void hb_duckdb_ret_text( HB_DUCKDB_RESULT *result, idx_t row, idx_t col )
{
   char *value = duckdb_value_varchar( &result->result, col, row );
   if( value ) {
      hb_retc( value );
      duckdb_free( value );
   } else {
      hb_ret();
   }
}

static void hb_duckdb_ret_cell( HB_DUCKDB_RESULT *result, idx_t row, idx_t col )
{
   idx_t start = 0, i;
   for( i = 0; i < result->chunk_count; ++i ) {
      duckdb_data_chunk chunk = result->chunks[i];
      idx_t size = duckdb_data_chunk_get_size( chunk );
      if( row < start + size ) {
         idx_t row_in_chunk = row - start;
         duckdb_vector vector = duckdb_data_chunk_get_vector( chunk, col );
         uint64_t *validity = duckdb_vector_get_validity( vector );
         void *data;
         duckdb_type type;

         if( validity && !duckdb_validity_row_is_valid( validity, row_in_chunk ) ) {
            hb_ret();
            return;
         }
         data = duckdb_vector_get_data( vector );
         type = duckdb_column_type( &result->result, col );
         switch( type ) {
            case DUCKDB_TYPE_BOOLEAN: hb_retl( ((bool *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_TINYINT: hb_retni( ((int8_t *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_SMALLINT: hb_retni( ((int16_t *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_INTEGER: hb_retnl( ((int32_t *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_BIGINT: hb_retnll( ((int64_t *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_UTINYINT: hb_retnl( ((uint8_t *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_USMALLINT: hb_retnl( ((uint16_t *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_UINTEGER: hb_retnll( ((uint32_t *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_UBIGINT: {
               uint64_t value = ((uint64_t *) data)[row_in_chunk];
               if( value <= (uint64_t) INT64_MAX ) {
                  hb_retnll( (HB_LONGLONG) value );
               } else {
                  hb_retnd( (double) value );
               }
               return;
            }
            case DUCKDB_TYPE_FLOAT: hb_retnd( ((float *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_DOUBLE: hb_retnd( ((double *) data)[row_in_chunk] ); return;
            case DUCKDB_TYPE_DECIMAL:
               hb_retnd( duckdb_decimal_to_double( ((duckdb_decimal *) data)[row_in_chunk] ) );
               return;
            case DUCKDB_TYPE_DATE: {
               duckdb_date_struct date = duckdb_from_date( ((duckdb_date *) data)[row_in_chunk] );
               hb_retd( date.year, date.month, date.day );
               return;
            }
            case DUCKDB_TYPE_TIMESTAMP:
            case DUCKDB_TYPE_TIMESTAMP_TZ:
               hb_duckdb_ret_timestamp( ((duckdb_timestamp *) data)[row_in_chunk] );
               return;
            case DUCKDB_TYPE_TIMESTAMP_S: {
               int64_t seconds = ((duckdb_timestamp_s *) data)[row_in_chunk].seconds;
               if( seconds > INT64_MAX / 1000000 || seconds < INT64_MIN / 1000000 ) {
                  hb_duckdb_ret_text( result, row, col );
                  return;
               }
               hb_duckdb_ret_timestamp_micros( seconds * 1000000 );
               return;
            }
            case DUCKDB_TYPE_TIMESTAMP_MS: {
               int64_t millis = ((duckdb_timestamp_ms *) data)[row_in_chunk].millis;
               if( millis > INT64_MAX / 1000 || millis < INT64_MIN / 1000 ) {
                  hb_duckdb_ret_text( result, row, col );
                  return;
               }
               hb_duckdb_ret_timestamp_micros( millis * 1000 );
               return;
            }
            case DUCKDB_TYPE_TIMESTAMP_NS:
               hb_duckdb_ret_timestamp_micros( ((duckdb_timestamp_ns *) data)[row_in_chunk].nanos / 1000 );
               return;
            case DUCKDB_TYPE_TIMESTAMP_TZ_NS:
               hb_duckdb_ret_timestamp_micros( ((duckdb_timestamp_ns *) data)[row_in_chunk].nanos / 1000 );
               return;
            case DUCKDB_TYPE_VARCHAR:
            case DUCKDB_TYPE_BLOB: {
               duckdb_string_t value = ((duckdb_string_t *) data)[row_in_chunk];
               hb_retclen( duckdb_string_t_data( &value ), (HB_SIZE) duckdb_string_t_length( value ) );
               return;
            }
            default: {
               hb_duckdb_ret_text( result, row, col );
               return;
            }
         }
      }
      start += size;
   }
   hb_ret();
}

HB_FUNC( DUCKDBOPEN )
{
   HB_DUCKDB *db = hb_duckdb_new_handle();
   if( hb_duckdb_open( db, hb_parc( 1 ) ) ) {
      hb_duckdb_return_handle( db );
   } else {
      if( db->last_error ) {
         hb_xfree( db->last_error );
      }
      hb_xfree( db );
      hb_retni( -1 );
   }
}

HB_FUNC( DUCKDBCONNECT )
{
   HB_DUCKDB **slot = (HB_DUCKDB **) hb_parptrGC( &s_hb_duckdb_gc_funcs, 1 );
   HB_DUCKDB *db = slot ? *slot : NULL;
   if( db ) {
      if( hb_duckdb_connect( db ) ) {
         hb_retptrGC( slot );
      } else {
         hb_retni( -1 );
      }
      return;
   }

   db = hb_duckdb_new_handle();
   if( hb_duckdb_open( db, hb_parc( 1 ) ) && hb_duckdb_connect( db ) ) {
      hb_duckdb_return_handle( db );
   } else {
      hb_duckdb_close_handles( db );
      if( db->last_error ) {
         hb_xfree( db->last_error );
      }
      hb_xfree( db );
      hb_retni( -1 );
   }
}

HB_FUNC( DUCKDBCLOSE )
{
   HB_DUCKDB *db = hb_duckdb_param( 1 );
   if( db ) {
      hb_duckdb_close_handles( db );
      hb_retni( 1 );
   } else {
      hb_retni( 0 );
   }
}

HB_FUNC( DUCKDBDISCONNECT )
{
   HB_DUCKDB *db = hb_duckdb_param( 1 );
   if( db && db->conn ) {
      duckdb_disconnect( &db->conn );
      db->conn = NULL;
      hb_retni( 1 );
   } else {
      hb_retni( 0 );
   }
}

HB_FUNC( DUCKDBERROR )
{
   HB_DUCKDB *db = hb_duckdb_param( 1 );
   hb_retc( db && db->last_error ? db->last_error : "" );
}

HB_FUNC( DUCKDBQUERY )
{
   HB_DUCKDB *db = hb_duckdb_param( 1 );
   const char *sql = hb_parc( 2 );
   HB_DUCKDB_RESULT *result;
   PHB_ITEM query, structure;
   idx_t i;

   if( !db || !db->conn || !sql ) {
      hb_retni( -1 );
      return;
   }
   result = (HB_DUCKDB_RESULT *) hb_xgrab( sizeof( HB_DUCKDB_RESULT ) );
   memset( result, 0, sizeof( *result ) );
   if( duckdb_query( db->conn, sql, &result->result ) == DuckDBError ) {
      hb_duckdb_set_error( db, duckdb_result_error( &result->result ) );
      duckdb_destroy_result( &result->result );
      hb_xfree( result );
      hb_retni( -1 );
      return;
   }

   result->column_count = duckdb_column_count( &result->result );
   result->chunk_capacity = 8;
   result->chunks = (duckdb_data_chunk *) hb_xgrab( (HB_SIZE) result->chunk_capacity * sizeof( duckdb_data_chunk ) );
   while( 1 ) {
      duckdb_data_chunk chunk = duckdb_fetch_chunk( result->result );
      idx_t rows;
      if( !chunk ) {
         break;
      }
      rows = duckdb_data_chunk_get_size( chunk );
      if( rows == 0 ) {
         duckdb_destroy_data_chunk( &chunk );
         break;
      }
      if( result->chunk_count == result->chunk_capacity ) {
         result->chunk_capacity *= 2;
         result->chunks = (duckdb_data_chunk *) hb_xrealloc(
            result->chunks, (HB_SIZE) result->chunk_capacity * sizeof( duckdb_data_chunk ) );
      }
      result->chunks[result->chunk_count++] = chunk;
      result->total_rows += rows;
   }

   structure = hb_itemArrayNew( (HB_SIZE) result->column_count );
   for( i = 0; i < result->column_count; ++i ) {
      hb_duckdb_make_column_metadata( structure, &result->result, i );
   }
   query = hb_itemArrayNew( 6 );
   hb_arraySetPtr( query, 1, result );
   hb_arraySetNL( query, 2, 0 );
   hb_arraySetNLL( query, 3, (HB_LONGLONG) result->total_rows );
   hb_arraySetNLL( query, 4, (HB_LONGLONG) result->column_count );
   hb_arraySetNI( query, 5, 3 );
   hb_arraySetForward( query, 6, structure );
   hb_itemReturnRelease( query );
   hb_itemRelease( structure );
   hb_duckdb_clear_error( db );
}

HB_FUNC( DUCKDBFETCH )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   HB_DUCKDB_RESULT *result = hb_duckdb_result_from_item( query );
   HB_LONGLONG row;
   if( !result || hb_arrayLen( query ) < 2 ) {
      hb_retnl( -1 );
      return;
   }
   row = hb_arrayGetNLL( query, 2 );
   if( row < 0 || (uint64_t) row >= result->total_rows ) {
      hb_retnl( -1 );
      return;
   }
   result->current_row = (idx_t) row + 1;
   hb_arraySetNLL( query, 2, (HB_LONGLONG) result->current_row );
   hb_retnl( 0 );
}

HB_FUNC( DUCKDBGETDATA )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   HB_DUCKDB_RESULT *result = hb_duckdb_result_from_item( query );
   HB_LONGLONG col = hb_parnll( 2 );
   HB_LONGLONG row;
   if( !result || col < 1 || (uint64_t) col > result->column_count || hb_arrayLen( query ) < 2 ) {
      hb_ret();
      return;
   }
   row = hb_arrayGetNLL( query, 2 );
   if( row < 1 || (uint64_t) row > result->total_rows ) {
      hb_ret();
      return;
   }
   hb_duckdb_ret_cell( result, (idx_t) row - 1, (idx_t) col - 1 );
}

HB_FUNC( DUCKDBROWCOUNT )
{
   HB_DUCKDB_RESULT *result = hb_duckdb_result_from_item( hb_param( 1, HB_IT_ARRAY ) );
   hb_retnll( result ? (HB_LONGLONG) result->total_rows : 0 );
}

HB_FUNC( DUCKDBCOLCOUNT )
{
   HB_DUCKDB_RESULT *result = hb_duckdb_result_from_item( hb_param( 1, HB_IT_ARRAY ) );
   hb_retnll( result ? (HB_LONGLONG) result->column_count : 0 );
}

HB_FUNC( DUCKDBFREERESULT )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   if( query ) {
      HB_DUCKDB_RESULT *result = hb_duckdb_result_from_item( query );
      hb_duckdb_destroy_result( result );
      hb_arraySetPtr( query, 1, NULL );
   } else {
      hb_duckdb_destroy_result( (HB_DUCKDB_RESULT *) hb_parptr( 1 ) );
   }
   hb_ret();
}

HB_FUNC( DUCKDBFREE )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   if( query ) {
      HB_DUCKDB_RESULT *result = hb_duckdb_result_from_item( query );
      hb_duckdb_destroy_result( result );
      hb_arraySetPtr( query, 1, NULL );
   } else {
      hb_duckdb_destroy_result( (HB_DUCKDB_RESULT *) hb_parptr( 1 ) );
   }
   hb_ret();
}

HB_FUNC( DUCKDBEXECUTE )
{
   HB_DUCKDB *db = hb_duckdb_param( 1 );
   const char *sql = hb_parc( 2 );
   duckdb_result result;

   if( !db || !db->conn || !sql ) {
      hb_retnl( -1 );
      return;
   }
   if( duckdb_query( db->conn, sql, &result ) == DuckDBError ) {
      hb_duckdb_set_error( db, duckdb_result_error( &result ) );
      duckdb_destroy_result( &result );
      hb_retnl( -1 );
      return;
   }
   duckdb_destroy_result( &result );
   hb_duckdb_clear_error( db );
   hb_retnl( 0 );
}
