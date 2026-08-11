/*
 * DuckDB RDBMS low-level (client API) interface definitions for Harbour.
 * Adapted as a mirror of Firebird/InterBase header macros.
 */

#ifndef DUCKDB_CH
#define DUCKDB_CH

/* Tipos de dados oficiais mapeados pela C-API do DuckDB (duckdb_type) */
#define DUCKDB_TYPE_INVALID      0
#define DUCKDB_TYPE_BOOLEAN      1
#define DUCKDB_TYPE_TINYINT      2
#define DUCKDB_TYPE_SMALLINT     3
#define DUCKDB_TYPE_INTEGER      4
#define DUCKDB_TYPE_BIGINT       5
#define DUCKDB_TYPE_UTINYINT     6
#define DUCKDB_TYPE_USMALLINT    7
#define DUCKDB_TYPE_UINTEGER     8
#define DUCKDB_TYPE_UBIGINT      9
#define DUCKDB_TYPE_FLOAT        10
#define DUCKDB_TYPE_DOUBLE       11
#define DUCKDB_TYPE_TIMESTAMP    12
#define DUCKDB_TYPE_DATE         13
#define DUCKDB_TYPE_TIME         14
#define DUCKDB_TYPE_INTERVAL     15
#define DUCKDB_TYPE_HUGEINT      16
#define DUCKDB_TYPE_UHUGEINT     17
#define DUCKDB_TYPE_VARCHAR      18
#define DUCKDB_TYPE_BLOB         19
#define DUCKDB_TYPE_DECIMAL      20
#define DUCKDB_TYPE_UUID         21
#define DUCKDB_TYPE_BIT          22

/* Estados de retorno das funções da C-API do DuckDB */
#define DUCKDB_SUCCESS           0
#define DUCKDB_ERROR            -1

/* Modos de transação e comportamento */
#define DUCKDB_DIALECT_CURRENT   3

#endif /* DUCKDB_CH */