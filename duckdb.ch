/*
 * DuckDB RDBMS low-level (client API) interface definitions for Harbour.
 * Adapted as a mirror of Firebird/InterBase header macros.
 */

#ifndef DUCKDB_CH
#define DUCKDB_CH

/* duckdb.ch - Mapeamento de Tipos Atualizado para DuckDB v1.5.6+ */

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
#define DUCKDB_TYPE_VARCHAR      17
#define DUCKDB_TYPE_BLOB         18
#define DUCKDB_TYPE_DECIMAL      19
#define DUCKDB_TYPE_TIMESTAMP_S  20
#define DUCKDB_TYPE_TIMESTAMP_MS 21
#define DUCKDB_TYPE_TIMESTAMP_NS 22
#define DUCKDB_TYPE_ENUM         23
#define DUCKDB_TYPE_LIST         24
#define DUCKDB_TYPE_STRUCT       25
#define DUCKDB_TYPE_MAP          26
#define DUCKDB_TYPE_UUID         27
#define DUCKDB_TYPE_UNION        28
#define DUCKDB_TYPE_BIT          29
#define DUCKDB_TYPE_TIME_TZ      30
#define DUCKDB_TYPE_TIMESTAMP_TZ 31
#define DUCKDB_TYPE_UHUGEINT     32
#define DUCKDB_TYPE_ARRAY        33
#define DUCKDB_TYPE_ANY          34
#define DUCKDB_TYPE_BIGNUM       35
#define DUCKDB_TYPE_SQLNULL      36
#define DUCKDB_TYPE_STRING_LITERAL 37
#define DUCKDB_TYPE_INTEGER_LITERAL 38
#define DUCKDB_TYPE_TIME_NS      39
#define DUCKDB_TYPE_GEOMETRY     40
#define DUCKDB_TYPE_VARIANT      41

/* Notas da Atualização:
   Certifique-se de que o DUCKDB_TYPE_VARCHAR e outros tipos que você utiliza
   coincidem com este mapeamento, que inclui as inserções recentes da v1.5.6.
*/
/* Estados de retorno das funções da C-API do DuckDB */
#define DUCKDB_SUCCESS           0
#define DUCKDB_ERROR            -1

/* Modos de transação e comportamento */
#define DUCKDB_DIALECT_CURRENT   3

/* -------------------------------------------------------------------- */
/* MODOS DE OPERAÇÃO DO RDD (CURSOR VS CACHE)                           */
/* -------------------------------------------------------------------- */
#define DUCKDBRDD_MODE_CURSOR    1
#define DUCKDBRDD_MODE_CACHE     2

/* -------------------------------------------------------------------- */
/* DIALETOS E FORMATOS DE ARQUIVOS SUPORTADOS PELA DUCKDBCLASS          */
/* -------------------------------------------------------------------- */

// Dialetos baseados em arquivo
#define DIALETO_DUCKDB    1
#define DIALETO_DUCKLAKE  2
#define DIALETO_SQLITE    3
#define DIALETO_CSV       4
#define DIALETO_JSON      5
#define DIALETO_PARQUET   6

// Dialetos de SGBDs / Conexões de Rede (iniciando em 100)
#define DIALETO_MYSQL     100
#define DIALETO_POSTGRES  101
#define DIALETO_ODBC      102
#define DIALETO_ODBC_MDB       103
#define DIALETO_ODBC_ACCDB     104
#define DIALETO_ODBC_FIREBIRD  105
#define DIALETO_ODBC_MSSQL     106
#define DIALETO_ODBC_ORACLE    107
#define DIALETO_ODBC_DSN       108

#endif /* DUCKDB_CH */