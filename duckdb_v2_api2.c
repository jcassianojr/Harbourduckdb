#include "hbapi.h"
#include "hbapiitm.h"
#include "hbapierr.h"

#define DUCKDB_V2_API_ALLOW_UNSTABLE 1
#include "duckdb_v2.h"

#include <stdint.h>
#include <string.h>

typedef struct {
   duckdb_v2_environment_handle env;
   duckdb_v2_instance_handle instance;
   duckdb_v2_connection_handle conn;
   char *last_error;
} HB_DUCKDB_V2;

typedef struct {
   duckdb_v2_data_chunk_handle *chunks;
   idx_t chunk_count;
   idx_t chunk_capacity;
   idx_t total_rows;
   idx_t column_count;
   idx_t *column_types;
   idx_t current_row;
} HB_DUCKDB_V2_RESULT;

static void hb_duckdb_v2_close( HB_DUCKDB_V2 *db );

static HB_GARBAGE_FUNC( hb_duckdb_v2_gc_release )
{
   HB_DUCKDB_V2 **slot = (HB_DUCKDB_V2 **) Cargo;
   if( slot && *slot ) {
      hb_duckdb_v2_close( *slot );
      hb_xfree( *slot );
      *slot = NULL;
   }
}

static const HB_GC_FUNCS s_hb_duckdb_v2_gc_funcs = {
   hb_duckdb_v2_gc_release,
   hb_gcDummyMark
};

static HB_DUCKDB_V2 *hb_duckdb_v2_param( int param )
{
   HB_DUCKDB_V2 **slot = (HB_DUCKDB_V2 **) hb_parptrGC( &s_hb_duckdb_v2_gc_funcs, param );
   return slot ? *slot : NULL;
}

static void hb_duckdb_v2_return_handle( HB_DUCKDB_V2 *db )
{
   HB_DUCKDB_V2 **slot = (HB_DUCKDB_V2 **)
      hb_gcAllocate( sizeof( HB_DUCKDB_V2 * ), &s_hb_duckdb_v2_gc_funcs );
   *slot = db;
   hb_retptrGC( slot );
}

static void hb_duckdb_v2_set_error( HB_DUCKDB_V2 *db, duckdb_v2_error_info_handle *err,
                                    const char *fallback )
{
   duckdb_v2_str text = { NULL, 0 };

   if( db && db->last_error ) {
      hb_xfree( db->last_error );
      db->last_error = NULL;
   }
   if( db && err && *err && duckdb_v2_error_info_get_text( *err, &text ) == DUCKDB_V2_ERROR_NONE &&
       text.ptr && text.len > 0 ) {
      db->last_error = (char *) hb_xgrab( (HB_SIZE) text.len + 1 );
      memcpy( db->last_error, text.ptr, (size_t) text.len );
      db->last_error[text.len] = '\0';
   } else if( db && fallback ) {
      db->last_error = hb_strdup( fallback );
   }
   if( err && *err ) {
      duckdb_v2_error_info_destroy( err );
   }
}

static void hb_duckdb_v2_clear_error( HB_DUCKDB_V2 *db )
{
   if( db && db->last_error ) {
      hb_xfree( db->last_error );
      db->last_error = NULL;
   }
}

static HB_DUCKDB_V2 *hb_duckdb_v2_open( const char *path )
{
   HB_DUCKDB_V2 *db = (HB_DUCKDB_V2 *) hb_xgrab( sizeof( HB_DUCKDB_V2 ) );
   duckdb_v2_error_info_handle err = NULL;
   duckdb_v2_str db_path;
   duckdb_v2_identifier_t db_name;

   memset( db, 0, sizeof( *db ) );
   db_path.ptr = path && path[0] ? path : ":memory:";
   db_path.len = (idx_t) strlen( db_path.ptr );
   db_name.ptr = "main";
   db_name.len = 4;

   if( duckdb_v2_environment_create( &db->env, &err ) != DUCKDB_V2_ERROR_NONE ||
       duckdb_v2_instance_create( db->env, &db->instance, &err ) != DUCKDB_V2_ERROR_NONE ||
       duckdb_v2_instance_attach( db->instance, &db_name, &db_path, NULL, true, &err ) != DUCKDB_V2_ERROR_NONE ||
       duckdb_v2_connection_create( db->instance, &db->conn, &err ) != DUCKDB_V2_ERROR_NONE ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao abrir ou conectar ao DuckDB v2." );
      if( db->conn ) {
         duckdb_v2_connection_destroy( &db->conn );
      }
      if( db->instance ) {
         duckdb_v2_instance_destroy( &db->instance );
      }
      if( db->env ) {
         duckdb_v2_environment_destroy( &db->env );
      }
      if( db->last_error ) {
         hb_xfree( db->last_error );
      }
      hb_xfree( db );
      return NULL;
   }
   hb_duckdb_v2_clear_error( db );
   return db;
}

static void hb_duckdb_v2_close( HB_DUCKDB_V2 *db )
{
   if( !db ) {
      return;
   }
   if( db->conn ) {
      duckdb_v2_connection_destroy( &db->conn );
   }
   if( db->instance ) {
      duckdb_v2_instance_destroy( &db->instance );
   }
   if( db->env ) {
      duckdb_v2_environment_destroy( &db->env );
   }
   hb_duckdb_v2_clear_error( db );
}

static int hb_duckdb_v2_drain_result( HB_DUCKDB_V2 *db, duckdb_v2_result_handle *result )
{
   duckdb_v2_data_chunk_handle chunk = NULL;
   duckdb_v2_error_info_handle err = NULL;
   DUCKDB_V2_ERROR status;

   while( ( status = duckdb_v2_result_fetch_chunk( *result, &chunk, &err ) ) == DUCKDB_V2_ERROR_NONE &&
          chunk ) {
      duckdb_v2_data_chunk_destroy( &chunk );
   }
   if( status != DUCKDB_V2_ERROR_NONE ) {
      hb_duckdb_v2_set_error( db, &err, "Falha durante a execucao da consulta DuckDB v2." );
      duckdb_v2_result_destroy( result );
      return 0;
   }
   return 1;
}

static void hb_duckdb_v2_destroy_result( HB_DUCKDB_V2_RESULT *result )
{
   idx_t i;
   if( !result ) {
      return;
   }
   for( i = 0; i < result->chunk_count; ++i ) {
      duckdb_v2_data_chunk_destroy( &result->chunks[i] );
   }
   if( result->chunks ) {
      hb_xfree( result->chunks );
   }
   if( result->column_types ) {
      hb_xfree( result->column_types );
   }
   hb_xfree( result );
}

static int hb_duckdb_v2_append_chunk( HB_DUCKDB_V2_RESULT *result, duckdb_v2_data_chunk_handle chunk )
{
   idx_t size = 0;
   if( duckdb_v2_data_chunk_get_size( chunk, &size, NULL ) != DUCKDB_V2_ERROR_NONE ) {
      duckdb_v2_data_chunk_destroy( &chunk );
      return 0;
   }
   if( result->chunk_count == result->chunk_capacity ) {
      idx_t capacity = result->chunk_capacity ? result->chunk_capacity * 2 : 8;
      duckdb_v2_data_chunk_handle *chunks = (duckdb_v2_data_chunk_handle *)
         hb_xrealloc( result->chunks, (HB_SIZE) capacity * sizeof( duckdb_v2_data_chunk_handle ) );
      result->chunks = chunks;
      result->chunk_capacity = capacity;
   }
   result->chunks[result->chunk_count++] = chunk;
   result->total_rows += size;
   return 1;
}

static const char *hb_duckdb_v2_type_name( idx_t type_id, HB_SIZE *size, HB_SIZE *decimals )
{
   *size = 255;
   *decimals = 0;
   switch( type_id ) {
      case DUCKDB_V2_LOGICAL_TYPE_ID_BOOLEAN: *size = 1; return "BOOLEAN";
      case DUCKDB_V2_LOGICAL_TYPE_ID_TINYINT: *size = 4; return "TINYINT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_SMALLINT: *size = 6; return "SMALLINT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_INTEGER: *size = 11; return "INTEGER";
      case DUCKDB_V2_LOGICAL_TYPE_ID_BIGINT: *size = 20; return "BIGINT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_UTINYINT: *size = 3; return "UTINYINT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_USMALLINT: *size = 5; return "USMALLINT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_UINTEGER: *size = 10; return "UINTEGER";
      case DUCKDB_V2_LOGICAL_TYPE_ID_UBIGINT: *size = 20; return "UBIGINT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_HUGEINT: *size = 39; return "HUGEINT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_UHUGEINT: *size = 39; return "UHUGEINT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_FLOAT: *size = 15; *decimals = 4; return "FLOAT";
      case DUCKDB_V2_LOGICAL_TYPE_ID_DOUBLE: *size = 24; *decimals = 8; return "DOUBLE";
      case DUCKDB_V2_LOGICAL_TYPE_ID_DECIMAL: *size = 38; *decimals = 4; return "DECIMAL";
      case DUCKDB_V2_LOGICAL_TYPE_ID_DATE: *size = 8; return "DATE";
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIME:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIME_NS:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIME_TZ: *size = 15; return "TIME";
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_SEC:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_MS:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_NS:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_TZ:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_TZ_NS: *size = 23; return "TIMESTAMP";
      case DUCKDB_V2_LOGICAL_TYPE_ID_BLOB: *size = 10; return "BLOB";
      case DUCKDB_V2_LOGICAL_TYPE_ID_VARCHAR: return "VARCHAR";
      default: return "VARCHAR";
   }
}

static int hb_duckdb_v2_decimal_metadata( HB_DUCKDB_V2 *db, duckdb_v2_logical_type_handle type,
                                          HB_SIZE *width, HB_SIZE *scale )
{
   duckdb_v2_error_info_handle err = NULL;
   idx_t count = 0, i;
   uint8_t values[2] = { 0, 0 };

   if( duckdb_v2_logical_type_get_param_count( type, &count, &err ) != DUCKDB_V2_ERROR_NONE || count != 2 ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao obter precisao e escala do tipo DECIMAL." );
      return 0;
   }
   for( i = 0; i < 2; ++i ) {
      duckdb_v2_identifier_t name = { NULL, 0 };
      duckdb_v2_value_handle value = NULL;
      if( duckdb_v2_logical_type_get_param( type, i, &name, &value, &err ) != DUCKDB_V2_ERROR_NONE ||
          !value ||
          duckdb_v2_value_get_utinyint( value, &values[i], &err ) != DUCKDB_V2_ERROR_NONE ) {
         if( value ) {
            duckdb_v2_value_destroy( &value );
         }
         hb_duckdb_v2_set_error( db, &err, "Falha ao ler precisao e escala do tipo DECIMAL." );
         return 0;
      }
      duckdb_v2_value_destroy( &value );
   }
   *width = values[0];
   *scale = values[1];
   return 1;
}

static void hb_duckdb_v2_civil_from_days( int64_t days, int *year, int *month, int *day )
{
   int64_t z = days + 719468;
   int64_t era = ( z >= 0 ? z : z - 146096 ) / 146097;
   unsigned doe = (unsigned) ( z - era * 146097 );
   unsigned yoe = ( doe - doe / 1460 + doe / 36524 - doe / 146096 ) / 365;
   int y = (int) yoe + (int) ( era * 400 );
   unsigned doy = doe - ( 365 * yoe + yoe / 4 - yoe / 100 );
   unsigned mp = ( 5 * doy + 2 ) / 153;
   *day = (int) ( doy - ( 153 * mp + 2 ) / 5 + 1 );
   *month = (int) ( mp < 10 ? mp + 3 : mp - 9 );
   *year = y + ( *month <= 2 );
}

static void hb_duckdb_v2_ret_timestamp( int64_t micros )
{
   const int64_t micros_per_day = 86400000000LL;
   int64_t days = micros / micros_per_day;
   int64_t time = micros % micros_per_day;
   if( time < 0 ) {
      time += micros_per_day;
      --days;
   }
   hb_rettdt( (long) ( days + 2440588 ), (long) ( time / 1000 ) );
}

static DUCKDB_V2_ERROR hb_duckdb_v2_ret_value_text( duckdb_v2_value_handle value,
                                                    duckdb_v2_error_info_handle *err )
{
   idx_t length = 0;
   char *text;
   DUCKDB_V2_ERROR status = duckdb_v2_value_to_string( value, NULL, 0, &length, err );
   if( status != DUCKDB_V2_ERROR_NONE ) {
      return status;
   }
   text = (char *) hb_xgrab( (HB_SIZE) length + 1 );
   status = duckdb_v2_value_to_string( value, text, length + 1, &length, err );
   if( status == DUCKDB_V2_ERROR_NONE ) {
      hb_retclen( text, (HB_SIZE) length );
   }
   hb_xfree( text );
   return status;
}

static void hb_duckdb_v2_ret_value( HB_DUCKDB_V2 *db, duckdb_v2_value_handle value, idx_t type_id )
{
   duckdb_v2_error_info_handle err = NULL;
   bool is_null = false;
   DUCKDB_V2_ERROR status;

   status = duckdb_v2_value_is_null( value, &is_null, &err );
   if( status != DUCKDB_V2_ERROR_NONE ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao verificar valor NULL do resultado." );
      hb_ret();
      return;
   }
   if( is_null ) {
      hb_ret();
      return;
   }

   switch( type_id ) {
      case DUCKDB_V2_LOGICAL_TYPE_ID_BOOLEAN: {
         bool v = false;
         status = duckdb_v2_value_get_bool( value, &v, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) hb_retl( v );
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_TINYINT: {
         int8_t v = 0;
         status = duckdb_v2_value_get_tinyint( value, &v, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) hb_retni( v );
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_SMALLINT: {
         int16_t v = 0;
         status = duckdb_v2_value_get_smallint( value, &v, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) hb_retni( v );
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_INTEGER: {
         int32_t v = 0;
         status = duckdb_v2_value_get_int( value, &v, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) hb_retnl( v );
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_BIGINT: {
         int64_t v = 0;
         status = duckdb_v2_value_get_bigint( value, &v, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) hb_retnll( v );
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_UTINYINT:
      case DUCKDB_V2_LOGICAL_TYPE_ID_USMALLINT:
      case DUCKDB_V2_LOGICAL_TYPE_ID_UINTEGER:
      case DUCKDB_V2_LOGICAL_TYPE_ID_UBIGINT: {
         uint64_t v = 0;
         status = duckdb_v2_value_get_ubigint( value, &v, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) {
            if( v <= (uint64_t) INT64_MAX ) hb_retnll( (HB_LONGLONG) v );
            else hb_retnd( (double) v );
         }
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_FLOAT: {
         float v = 0;
         status = duckdb_v2_value_get_float( value, &v, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) hb_retnd( v );
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_DOUBLE:
      case DUCKDB_V2_LOGICAL_TYPE_ID_DECIMAL: {
         double v = 0;
         status = duckdb_v2_value_get_double( value, &v, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) hb_retnd( v );
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_DATE: {
         int32_t days = 0;
         int year, month, day;
         status = duckdb_v2_value_get_date( value, &days, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) {
            hb_duckdb_v2_civil_from_days( days, &year, &month, &day );
            hb_retd( year, month, day );
         } else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_TZ: {
         int64_t micros = 0;
         status = type_id == DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_TZ
            ? duckdb_v2_value_get_timestamp_tz( value, &micros, &err )
            : duckdb_v2_value_get_timestamp( value, &micros, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) hb_duckdb_v2_ret_timestamp( micros );
         else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_SEC:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_MS:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_NS:
      case DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_TZ_NS: {
         int64_t timestamp = 0;
         if( type_id == DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_SEC )
            status = duckdb_v2_value_get_timestamp_sec( value, &timestamp, &err );
         else if( type_id == DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_MS )
            status = duckdb_v2_value_get_timestamp_ms( value, &timestamp, &err );
         else if( type_id == DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_TZ_NS )
            status = duckdb_v2_value_get_timestamp_tz_ns( value, &timestamp, &err );
         else
            status = duckdb_v2_value_get_timestamp_ns( value, &timestamp, &err );
         if( status == DUCKDB_V2_ERROR_NONE ) {
            int64_t multiplier = type_id == DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_SEC ? 1000000 :
                                 type_id == DUCKDB_V2_LOGICAL_TYPE_ID_TIMESTAMP_MS ? 1000 : 1;
            if( multiplier == 1 ) {
               timestamp /= 1000;
               hb_duckdb_v2_ret_timestamp( timestamp );
            } else if( timestamp > INT64_MAX / multiplier || timestamp < INT64_MIN / multiplier ) {
               status = hb_duckdb_v2_ret_value_text( value, &err );
               if( status != DUCKDB_V2_ERROR_NONE ) hb_ret();
            } else {
               hb_duckdb_v2_ret_timestamp( timestamp * multiplier );
            }
         } else hb_ret();
         break;
      }
      case DUCKDB_V2_LOGICAL_TYPE_ID_VARCHAR:
      case DUCKDB_V2_LOGICAL_TYPE_ID_BLOB: {
         duckdb_v2_str text = { NULL, 0 };
         status = type_id == DUCKDB_V2_LOGICAL_TYPE_ID_BLOB
            ? duckdb_v2_value_get_blob( value, &text, &err )
            : duckdb_v2_value_get_varchar( value, &text, &err );
         if( status == DUCKDB_V2_ERROR_NONE )
            hb_retclen( text.ptr ? text.ptr : "", (HB_SIZE) text.len );
         else hb_ret();
         break;
      }
      default: {
         status = hb_duckdb_v2_ret_value_text( value, &err );
         if( status != DUCKDB_V2_ERROR_NONE ) hb_ret();
         break;
      }
   }
   if( status != DUCKDB_V2_ERROR_NONE ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao converter valor do resultado DuckDB v2." );
   }
   if( err ) {
      duckdb_v2_error_info_destroy( &err );
   }
}

HB_FUNC( DUCKDBOPEN )
{
   HB_DUCKDB_V2 *db = hb_duckdb_v2_open( hb_parc( 1 ) );
   if( db ) hb_duckdb_v2_return_handle( db );
   else hb_retni( 0 );
}

HB_FUNC( DUCKDBCONNECT )
{
   HB_DUCKDB_V2 *db = hb_duckdb_v2_open( hb_parc( 1 ) );
   if( db ) hb_duckdb_v2_return_handle( db );
   else hb_retni( 0 );
}

HB_FUNC( DUCKDBCLOSE )
{
   HB_DUCKDB_V2 *db = hb_duckdb_v2_param( 1 );
   if( db ) {
      hb_duckdb_v2_close( db );
      hb_retni( 1 );
   } else {
      hb_retni( 0 );
   }
}

HB_FUNC( DUCKDBDISCONNECT )
{
   HB_DUCKDB_V2 *db = hb_duckdb_v2_param( 1 );
   if( db ) {
      hb_duckdb_v2_close( db );
      hb_retni( 1 );
   } else {
      hb_retni( 0 );
   }
}

HB_FUNC( DUCKDBERROR )
{
   HB_DUCKDB_V2 *db = hb_duckdb_v2_param( 1 );
   hb_retc( db && db->last_error ? db->last_error : "" );
}

HB_FUNC( DUCKDBEXECUTE )
{
   HB_DUCKDB_V2 *db = hb_duckdb_v2_param( 1 );
   const char *sql = hb_parc( 2 );
   duckdb_v2_statement_iterator_handle iterator = NULL;
   duckdb_v2_error_info_handle err = NULL;
   int ok = 1;

   if( !db || !db->conn || !sql ||
       duckdb_v2_parse_sql( db->conn, sql, &iterator, &err ) != DUCKDB_V2_ERROR_NONE ) {
      if( db ) hb_duckdb_v2_set_error( db, &err, "Falha ao analisar SQL no DuckDB v2." );
      hb_retni( -1 );
      return;
   }
   while( ok ) {
      duckdb_v2_sql_statement_handle statement = NULL;
      duckdb_v2_result_handle result = NULL;
      DUCKDB_V2_ERROR status = duckdb_v2_statement_iterator_next( iterator, &statement, &err );
      if( status != DUCKDB_V2_ERROR_NONE ) {
         hb_duckdb_v2_set_error( db, &err, "Falha ao ler a proxima instrucao SQL." );
         ok = 0;
         break;
      }
      if( !statement ) {
         break;
      }
      status = duckdb_v2_statement_execute( db->conn, statement, NULL, NULL, 0, &result, &err );
      duckdb_v2_sql_statement_destroy( &statement );
      if( status != DUCKDB_V2_ERROR_NONE || !result ) {
         hb_duckdb_v2_set_error( db, &err, "Falha ao executar SQL no DuckDB v2." );
         ok = 0;
         break;
      }
      ok = hb_duckdb_v2_drain_result( db, &result );
      duckdb_v2_result_destroy( &result );
   }
   if( iterator ) duckdb_v2_statement_iterator_destroy( &iterator );
   if( ok ) hb_duckdb_v2_clear_error( db );
   hb_retni( ok ? 1 : -1 );
}

HB_FUNC( DUCKDBQUERY )
{
   HB_DUCKDB_V2 *db = hb_duckdb_v2_param( 1 );
   const char *sql = hb_parc( 2 );
   duckdb_v2_statement_iterator_handle iterator = NULL;
   duckdb_v2_sql_statement_handle statement = NULL;
   duckdb_v2_sql_statement_handle extra_statement = NULL;
   duckdb_v2_result_handle result_handle = NULL;
   duckdb_v2_schema_handle schema = NULL;
   duckdb_v2_error_info_handle err = NULL;
   HB_DUCKDB_V2_RESULT *result = NULL;
   PHB_ITEM query = NULL, structure = NULL, column = NULL;
   idx_t i, count = 0;
   int ok = 1;

   if( !db || !db->conn || !sql ||
       duckdb_v2_parse_sql( db->conn, sql, &iterator, &err ) != DUCKDB_V2_ERROR_NONE ) {
      if( db ) hb_duckdb_v2_set_error( db, &err, "Falha ao analisar SQL no DuckDB v2." );
      hb_retni( -1 );
      return;
   }
   if( duckdb_v2_statement_iterator_next( iterator, &statement, &err ) != DUCKDB_V2_ERROR_NONE ||
       !statement ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao preparar consulta no DuckDB v2." );
      ok = 0;
   }
   if( ok && duckdb_v2_statement_iterator_next( iterator, &extra_statement, &err ) != DUCKDB_V2_ERROR_NONE ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao verificar instrucoes SQL adicionais." );
      ok = 0;
   } else if( ok && extra_statement ) {
      duckdb_v2_sql_statement_destroy( &extra_statement );
      hb_duckdb_v2_set_error( db, &err, "DuckDBQuery aceita apenas uma instrucao SQL por chamada." );
      ok = 0;
   }
   if( ok && ( duckdb_v2_statement_execute( db->conn, statement, NULL, NULL, 0, &result_handle, &err ) != DUCKDB_V2_ERROR_NONE ||
               !result_handle ) ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao executar consulta no DuckDB v2." );
      ok = 0;
   }
   if( statement ) duckdb_v2_sql_statement_destroy( &statement );
   if( ok && duckdb_v2_result_get_schema( result_handle, &schema, &err ) != DUCKDB_V2_ERROR_NONE ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao obter o esquema do resultado." );
      ok = 0;
   }
   if( ok && duckdb_v2_schema_get_count( schema, &count, &err ) != DUCKDB_V2_ERROR_NONE ) {
      hb_duckdb_v2_set_error( db, &err, "Falha ao obter a quantidade de colunas." );
      ok = 0;
   }
   if( ok ) {
      result = (HB_DUCKDB_V2_RESULT *) hb_xgrab( sizeof( HB_DUCKDB_V2_RESULT ) );
      memset( result, 0, sizeof( *result ) );
      result->column_count = count;
      if( count ) {
         result->column_types = (idx_t *) hb_xgrab( (HB_SIZE) count * sizeof( idx_t ) );
      }
      structure = hb_itemArrayNew( (HB_SIZE) count );
      for( i = 0; i < count; ++i ) {
         duckdb_v2_identifier_t name = { NULL, 0 };
         duckdb_v2_logical_type_handle type = NULL;
         DUCKDB_V2_LOGICAL_TYPE_ID type_id;
         HB_SIZE field_size, decimals;
         const char *type_name;
         if( duckdb_v2_schema_get_field( schema, i, &name, &type, &err ) != DUCKDB_V2_ERROR_NONE ||
             duckdb_v2_logical_type_get_id( type, &type_id, &err ) != DUCKDB_V2_ERROR_NONE ) {
            hb_duckdb_v2_set_error( db, &err, "Falha ao obter metadados de coluna." );
            ok = 0;
            break;
         }
         result->column_types[i] = (idx_t) type_id;
         type_name = hb_duckdb_v2_type_name( (idx_t) type_id, &field_size, &decimals );
         if( type_id == DUCKDB_V2_LOGICAL_TYPE_ID_DECIMAL &&
             !hb_duckdb_v2_decimal_metadata( db, type, &field_size, &decimals ) ) {
            ok = 0;
            break;
         }
         column = hb_itemArrayNew( 7 );
         hb_arraySetCL( column, 1, name.ptr ? name.ptr : "", (HB_SIZE) name.len );
         hb_arraySetC( column, 2, type_name );
         hb_arraySetNL( column, 3, (long) field_size );
         hb_arraySetNL( column, 4, (long) decimals );
         hb_arraySetC( column, 5, "" );
         hb_arraySetNL( column, 6, 0 );
         hb_arraySetCL( column, 7, name.ptr ? name.ptr : "", (HB_SIZE) name.len );
         hb_arraySetForward( structure, (HB_SIZE) i + 1, column );
         hb_itemRelease( column );
         column = NULL;
      }
   }
   if( schema ) duckdb_v2_schema_destroy( &schema );
   if( ok ) {
      duckdb_v2_data_chunk_handle chunk = NULL;
      DUCKDB_V2_ERROR status;
      while( ( status = duckdb_v2_result_fetch_chunk( result_handle, &chunk, &err ) ) == DUCKDB_V2_ERROR_NONE &&
             chunk ) {
         if( !hb_duckdb_v2_append_chunk( result, chunk ) ) {
            hb_duckdb_v2_set_error( db, &err, "Falha ao ler um bloco do resultado." );
            ok = 0;
            break;
         }
      }
      if( status != DUCKDB_V2_ERROR_NONE ) {
         hb_duckdb_v2_set_error( db, &err, "Falha durante a execucao da consulta DuckDB v2." );
         ok = 0;
      }
   }
   if( result_handle ) duckdb_v2_result_destroy( &result_handle );
   if( iterator ) duckdb_v2_statement_iterator_destroy( &iterator );
   if( !ok ) {
      if( column ) hb_itemRelease( column );
      if( structure ) hb_itemRelease( structure );
      hb_duckdb_v2_destroy_result( result );
      hb_retni( -1 );
      return;
   }

   query = hb_itemArrayNew( 6 );
   hb_arraySetPtr( query, 1, result );
   hb_arraySetNL( query, 2, 0 );
   hb_arraySetNLL( query, 3, (HB_MAXINT) result->total_rows );
   hb_arraySetNLL( query, 4, (HB_MAXINT) result->column_count );
   hb_arraySetNI( query, 5, 3 );
   hb_arraySetForward( query, 6, structure );
   hb_itemReturnRelease( query );
   hb_itemRelease( structure );
   if( column ) hb_itemRelease( column );
   hb_duckdb_v2_clear_error( db );
}

HB_FUNC( DUCKDBFETCH )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   if( query ) {
      HB_DUCKDB_V2_RESULT *result = (HB_DUCKDB_V2_RESULT *) hb_itemGetPtr( hb_arrayGetItemPtr( query, 1 ) );
      idx_t row = (idx_t) hb_itemGetNLL( hb_arrayGetItemPtr( query, 2 ) );
      if( result && row < result->total_rows ) {
         hb_arraySetNLL( query, 2, (HB_MAXINT) ( row + 1 ) );
         result->current_row = row + 1;
         hb_retnl( 0 );
         return;
      }
   }
   hb_retnl( -1 );
}

HB_FUNC( DUCKDBGETDATA )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   idx_t col = hb_parnll( 2 );
   if( query && col > 0 ) {
      HB_DUCKDB_V2_RESULT *result = (HB_DUCKDB_V2_RESULT *) hb_itemGetPtr( hb_arrayGetItemPtr( query, 1 ) );
      idx_t row = (idx_t) hb_itemGetNLL( hb_arrayGetItemPtr( query, 2 ) );
      idx_t start = 0, i;
      if( result && row > 0 && row <= result->total_rows && col <= result->column_count ) {
         for( i = 0; i < result->chunk_count; ++i ) {
            idx_t size = 0;
            duckdb_v2_vector_handle vector = NULL;
            duckdb_v2_value_handle value = NULL;
            if( duckdb_v2_data_chunk_get_size( result->chunks[i], &size, NULL ) != DUCKDB_V2_ERROR_NONE ) break;
            if( row - 1 < start + size ) {
               if( duckdb_v2_data_chunk_get_vector( result->chunks[i], col - 1, &vector, NULL ) == DUCKDB_V2_ERROR_NONE &&
                   duckdb_v2_vector_get_value( vector, row - 1 - start, &value, NULL ) == DUCKDB_V2_ERROR_NONE &&
                   value ) {
                  hb_duckdb_v2_ret_value( NULL, value, result->column_types[col - 1] );
                  duckdb_v2_value_destroy( &value );
                  return;
               }
               break;
            }
            start += size;
         }
      }
   }
   hb_ret();
}

HB_FUNC( DUCKDBROWCOUNT )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   HB_DUCKDB_V2_RESULT *result = query
      ? (HB_DUCKDB_V2_RESULT *) hb_itemGetPtr( hb_arrayGetItemPtr( query, 1 ) ) : NULL;
   hb_retnll( result ? (HB_LONGLONG) result->total_rows : 0 );
}

HB_FUNC( DUCKDBCOLCOUNT )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   HB_DUCKDB_V2_RESULT *result = query
      ? (HB_DUCKDB_V2_RESULT *) hb_itemGetPtr( hb_arrayGetItemPtr( query, 1 ) ) : NULL;
   hb_retnll( result ? (HB_LONGLONG) result->column_count : 0 );
}

HB_FUNC( DUCKDBFREERESULT )
{
   PHB_ITEM query = hb_param( 1, HB_IT_ARRAY );
   if( query ) {
      HB_DUCKDB_V2_RESULT *result = (HB_DUCKDB_V2_RESULT *) hb_itemGetPtr( hb_arrayGetItemPtr( query, 1 ) );
      hb_duckdb_v2_destroy_result( result );
      hb_arraySetPtr( query, 1, NULL );
   } else {
      hb_duckdb_v2_destroy_result( (HB_DUCKDB_V2_RESULT *) hb_parptr( 1 ) );
   }
   hb_ret();
}

HB_FUNC( DUCKDBFREE )
{
   HB_FUNC_EXEC( DUCKDBFREERESULT );
}
