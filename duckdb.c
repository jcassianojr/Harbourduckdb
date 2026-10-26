#include "hbapi.h"
#include "hbapiitm.h"
#include "hbapierr.h"
#include "duckdb.h"

/* Helper matemático para calcular Data Juliana (Padrão nativo do Harbour/Clipper) */
static long duckdb_to_julian( int year, int month, int day )
{
    int a = ( 14 - month ) / 12;
    int y = year + 4800 - a;
    int m = month + 12 * a - 3;
    return day + ( 153 * m + 2 ) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
}

/* ESTRUTURA COM CACHE DE OTIMIZAÇÃO (ITEM 2) */
typedef struct {
    duckdb_result result;
    duckdb_data_chunk *chunks;
    idx_t chunk_count;
    idx_t chunk_capacity;
    idx_t total_rows;
    idx_t column_count;
    
    /* Variáveis de cache para otimizar leitura sequencial (O(1) vs O(N)) */
    idx_t last_chunk_idx;
    idx_t last_chunk_row_start;
} HB_DUCKDB_RESULT;

/* =========================================================================
   ABERTURA E CONEXÃO
========================================================================= */

HB_FUNC( DUCKDBOPEN )
{
    const char *db_path = hb_parc(1);
    duckdb_database *db = (duckdb_database *) hb_xgrab( sizeof(duckdb_database) );
    
    if( duckdb_open( db_path, db ) == DuckDBSuccess ) {
        hb_retptr( (void *) db );
    } else {
        hb_xfree( db );
        hb_retptr( NULL );
    }
}

HB_FUNC( DUCKDBCLOSE )
{
    duckdb_database *db = (duckdb_database *) hb_parptr(1);
    if( db ) {
        duckdb_close( db );
        hb_xfree( db );
    }
}

HB_FUNC( DUCKDBCONNECT )
{
    duckdb_database *db = (duckdb_database *) hb_parptr(1);
    duckdb_connection *conn = (duckdb_connection *) hb_xgrab( sizeof(duckdb_connection) );
    
    if( db && duckdb_connect( *db, conn ) == DuckDBSuccess ) {
        hb_retptr( (void *) conn );
    } else {
        hb_xfree( conn );
        hb_retptr( NULL );
    }
}

HB_FUNC( DUCKDBDISCONNECT )
{
    duckdb_connection *conn = (duckdb_connection *) hb_parptr(1);
    if( conn ) {
        duckdb_disconnect( conn );
        hb_xfree( conn );
    }
}

/* =========================================================================
   EXECUÇÃO DE QUERY
========================================================================= */

HB_FUNC( DUCKDBQUERY )
{
    duckdb_connection *conn = (duckdb_connection *) hb_parptr(1);
    const char *query = hb_parc(2);

    if( conn && query ) {
        HB_DUCKDB_RESULT *res = (HB_DUCKDB_RESULT *) hb_xgrab( sizeof( HB_DUCKDB_RESULT ) );
        duckdb_state state = duckdb_query( *conn, query, &(res->result) );

        if( state == DuckDBSuccess ) {
            res->chunk_count = 0;
            res->chunk_capacity = 10;
            res->chunks = (duckdb_data_chunk *) hb_xgrab( res->chunk_capacity * sizeof(duckdb_data_chunk) );
            res->total_rows = 0;
            res->column_count = duckdb_column_count( &(res->result) );
            
            /* Inicializa o cache para a leitura do RDD/Classe */
            res->last_chunk_idx = 0;
            res->last_chunk_row_start = 0;

            /* Extrai todos os chunks via API V2 */
            while( 1 ) {
                duckdb_data_chunk chunk = duckdb_fetch_chunk( res->result );
                if( !chunk ) break;

                idx_t size = duckdb_data_chunk_get_size( chunk );
                if( size == 0 ) {
                    duckdb_destroy_data_chunk( &chunk );
                    break;
                }

                if( res->chunk_count >= res->chunk_capacity ) {
                    res->chunk_capacity *= 2;
                    res->chunks = (duckdb_data_chunk *) hb_xrealloc( res->chunks, res->chunk_capacity * sizeof(duckdb_data_chunk) );
                }
                res->chunks[res->chunk_count++] = chunk;
                res->total_rows += size;
            }
            hb_retptr( (void *) res );
        } else {
            /* Query falhou */
            duckdb_destroy_result( &(res->result) );
            hb_xfree( res );
            hb_retptr( NULL );
        }
    } else {
        hb_retptr( NULL );
    }
}

/* =========================================================================
   INFORMAÇÕES DE RESULTADO
========================================================================= */

HB_FUNC( DUCKDBROWCOUNT )
{
    HB_DUCKDB_RESULT *res = (HB_DUCKDB_RESULT *) hb_parptr(1);
    if( res ) {
        hb_retnll( res->total_rows );
    } else {
        hb_retnll( 0 );
    }
}

HB_FUNC( DUCKDBCOLCOUNT )
{
    HB_DUCKDB_RESULT *res = (HB_DUCKDB_RESULT *) hb_parptr(1);
    if( res ) {
        hb_retnll( res->column_count );
    } else {
        hb_retnll( 0 );
    }
}

/* =========================================================================
   LIBERAÇÃO DE MEMÓRIA
========================================================================= */

HB_FUNC( DUCKDBFREERESULT )
{
    HB_DUCKDB_RESULT *res = (HB_DUCKDB_RESULT *) hb_parptr(1);
    if( res ) {
        /* Destrói todos os chunks alocados na memória */
        for( idx_t i = 0; i < res->chunk_count; i++ ) {
            duckdb_destroy_data_chunk( &(res->chunks[i]) );
        }
        
        /* Libera a matriz de ponteiros e o result base */
        if( res->chunks ) {
            hb_xfree( res->chunks );
        }
        duckdb_destroy_result( &(res->result) );
        
        /* Libera a estrutura principal alocada no Harbour */
        hb_xfree( res );
    }
    hb_ret();
}

/* =========================================================================
   EXTRAÇÃO DE DADOS POR CÉLULA COM CACHE
========================================================================= */

HB_FUNC( DUCKDBGETDATA )
{
    HB_DUCKDB_RESULT *res = (HB_DUCKDB_RESULT *) hb_parptr(1);
    
    /* Subtrai 1 pois o Harbour manda índice Base-1, mas em C é Base-0 */
    idx_t target_row = (idx_t) hb_parnl(2) - 1; 
    idx_t col = (idx_t) hb_parnl(3) - 1; 

    if( !res || target_row >= res->total_rows || col >= res->column_count ) {
        hb_ret();
        return;
    }

    idx_t current_row = 0;
    idx_t start_chunk = 0;
    duckdb_data_chunk target_chunk = NULL;
    idx_t row_in_chunk = 0;

    /* APLICAÇÃO DO CACHE: Lê sequencialmente muito mais rápido */
    if( target_row >= res->last_chunk_row_start ) {
        start_chunk = res->last_chunk_idx;
        current_row = res->last_chunk_row_start;
    }

    for( idx_t i = start_chunk; i < res->chunk_count; i++ ) {
        idx_t chunk_size = duckdb_data_chunk_get_size( res->chunks[i] );
        if( target_row < current_row + chunk_size ) {
            target_chunk = res->chunks[i];
            row_in_chunk = target_row - current_row;
            
            /* Atualiza o cache para a próxima chamada */
            res->last_chunk_idx = i;
            res->last_chunk_row_start = current_row;
            break;
        }
        current_row += chunk_size;
    }

    if( !target_chunk ) {
        hb_ret(); /* Segurança, nunca deve chegar aqui se o target_row for válido */
        return;
    }

    /* Extração do vetor e validação de Nulos */
    duckdb_vector vector = duckdb_data_chunk_get_vector( target_chunk, col );
    void *data = duckdb_vector_get_data( vector );
    uint64_t *validity = duckdb_vector_get_validity( vector );

    if( !duckdb_validity_row_is_valid( validity, row_in_chunk ) ) {
        hb_ret(); /* Retorna NIL em Harbour para banco de dados NULL */
        return;
    }

    /* Identificação de Tipos */
    duckdb_logical_type type = duckdb_vector_get_column_type( vector );
    duckdb_type type_id = duckdb_get_type_id( type );
    duckdb_destroy_logical_type( &type );

    /* CONVERSÃO NATIVA DE TIPOS */
    switch( type_id ) {
        case DUCKDB_TYPE_BOOLEAN:
            hb_retl( ((bool *)data)[row_in_chunk] );
            break;
        case DUCKDB_TYPE_TINYINT:
            hb_retni( ((int8_t *)data)[row_in_chunk] );
            break;
        case DUCKDB_TYPE_SMALLINT:
            hb_retni( ((int16_t *)data)[row_in_chunk] );
            break;
        case DUCKDB_TYPE_INTEGER:
            hb_retni( ((int32_t *)data)[row_in_chunk] );
            break;
        case DUCKDB_TYPE_BIGINT:
            hb_retnll( ((int64_t *)data)[row_in_chunk] );
            break;
        case DUCKDB_TYPE_FLOAT:
            hb_retnd( (double) ((float *)data)[row_in_chunk] );
            break;
        case DUCKDB_TYPE_DOUBLE:
            hb_retnd( ((double *)data)[row_in_chunk] );
            break;

        case DUCKDB_TYPE_DECIMAL:
        {
            duckdb_decimal dec_val = ((duckdb_decimal *)data)[row_in_chunk];
            hb_retnd( duckdb_decimal_to_double( dec_val ) );
            break;
        }

        case DUCKDB_TYPE_DATE:
        {
            duckdb_date date_val = ((duckdb_date *)data)[row_in_chunk];
            duckdb_date_struct d = duckdb_from_date( date_val );
            hb_retd( d.year, d.month, d.day );
            break;
        }

        case DUCKDB_TYPE_TIMESTAMP:
        {
            duckdb_timestamp ts_val = ((duckdb_timestamp *)data)[row_in_chunk];
            duckdb_timestamp_struct ts = duckdb_from_timestamp( ts_val );
            
            /* Utilização da nossa função local e matemática direta para não depender dos headers do Harbour */
            long lJulian   = duckdb_to_julian( ts.date.year, ts.date.month, ts.date.day );
            long lMilliSec = ( ts.time.hour * 3600000 ) + ( ts.time.min * 60000 ) + 
                             ( ts.time.sec * 1000 ) + ( ts.time.micros / 1000 );
            
            hb_rettdt( lJulian, lMilliSec );
            break;
        }

        case DUCKDB_TYPE_VARCHAR:
        {
            duckdb_string_t str_val = ((duckdb_string_t *)data)[row_in_chunk];
            uint32_t len = str_val.value.inlined.length;
            
            if( len <= 12 ) { 
                hb_retclen( (const char *) str_val.value.inlined.inlined, len );
            } else {
                hb_retclen( (const char *) str_val.value.pointer.ptr, len );
            }
            break;
        }

        default:
            /* Tipos não mapeados retornam NIL */
            hb_ret();
            break;
    }
}