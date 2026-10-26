# 📘 Documentacao Tecnica do Projeto
> Gerado em: 26/10/2026 15:53:04

## 🏗️ Estrutura de Modulos (PRGs)

### 📄 Arquivo: `duckdbclass`
- Method New()
- Method TratarDialeto()
- Method StartTransaction()
- Method Rollback()
- Method Commit()
- Method Execute()
- Method Query()
- Method TableExists()
- Method ListTables()
- Method TableStruct()
- Method Delete()
- Method Append()
- Method Update()
- Method GetServerInfo()
- Method New()
- Method LastRec()
- Method Refresh()
- Method Destroy()
- Method Fetch()
- Method Struct()
- Method FieldPos()
- Method FieldName()
- Method FieldType()
- Method FieldLen()
- Method FieldDec()
- Method FieldGet()
- Method Getrow()
- Method GetBlankRow()
- Method GetKeyField()
- Method new()
- Method Changed()
- Method FieldGet()
- Method FieldPut()
- Method FieldName()
- Method FieldPos()
- Method FieldType()
- Method FieldLen()
- Method FieldDec()
- Method GetKeyField()
- Static Function KeyField()
- Static Function DataToSql()
- Static Function StructConvert()
- Static Function QuoteIdent()
- Static Function NumericValue()
- Static Function StrDateClass()
- Static Function UniversalDateTime()

### 📄 Arquivo: `duckdbrdd`
- Function DBDUCKDBCONNECTION()
- Static Function TratarDialeto_RDD()
- Function DBDUCKDBGETHANDLE()
- Function DBDUCKDBCLEARCONNECTION()
- Function DBDUCKDBCOMMIT()
- Function DBDUCKDBROLLBACK()
- Static Function DUCKDB_QuoteIdent()
- Function DUCKDB_SETPK()
- Static Function DUCKDB_INIT()
- Static Function DUCKDB_NEW()
- Static Function DUCKDB_ADDFIELD()
- Static Function DUCKDB_OPEN()
- Static Function DUCKDB_FETCH_NEXT()
- Static Function DUCKDB_CLOSE()
- Static Function DUCKDB_GETVALUE()
- Static Function DUCKDB_PUTVALUE()
- Static Function DUCKDB_SKIP()
- Static Function DUCKDB_GOTOP()
- Static Function DUCKDB_GOBOTTOM()
- Static Function DUCKDB_GOTOID()
- Static Function DUCKDB_GOTO()
- Static Function DUCKDB_RECCOUNT()
- Static Function DUCKDB_BOF()
- Static Function DUCKDB_EOF()
- Static Function DUCKDB_RECID()
- Static Function DUCKDB_APPEND()
- Static Function DUCKDB_FLUSH()
- Static Function DUCKDB_DELETE()
- Static Function DUCKDB_ValToSql()
- Static Function DUCKDB_NumericValue()
- Static Function DUCKDB_CREATE()
- Static Function DUCKDB_RDDINFO()
- Static Function DUCKDB_INFO()
- Function DUCKDBRDD_GETFUNCTABLE()
- Init Procedure DUCKDB_INIT_REGISTER()
- Static Function StrDateRdd()
- Static Function UniversalDateTime()

## 📊 Dicionario de Dados e Acessos

## 🕸️ Diagrama de Relacionamento (Mermaid)
```mermaid
graph TD
    getserverinfo --> __destroy["::destroy     <externa>"]
    append --> __execute["::execute     <externa>"]
    getserverinfo --> __fetch["::fetch       <externa>"]
    getrow --> __fieldget["::fieldget    <externa>"]
    getserverinfo --> __getblankrow["::getblankrow <externa>"]
    getserverinfo --> __query["::query       <externa>"]
    new --> __refresh["::refresh     <externa>"]
    new --> __refresh["::refresh     <externa>"]
    getblankrow --> _new[":new          <externa>"]
    getserverinfo --> blank["blank         <externa>"]
    getkeyfield --> changed["changed       in duckdbclass.prg"]
    append --> datatosql["datatosql     in duckdbclass.prg"]
    new --> duckdbconnect["duckdbconnect <externa>"]
    commit --> duckdbexecute["duckdbexecute <externa>"]
    append --> duckdbfetch["duckdbfetch   <externa>"]
    append --> duckdbfree["duckdbfree    <externa>"]
    destroy --> duckdbfree["duckdbfree    <externa>"]
    append --> duckdbgetdata["duckdbgetdata <externa>"]
    append --> duckdbquery["duckdbquery   <externa>"]
    duckdbrdd_getfunctable --> duckdbquery["duckdbquery   <externa>"]
    duckdbrdd_getfunctable --> duckdb_append["duckdb_append in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_bof["duckdb_bof    in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_close["duckdb_close  in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_create["duckdb_create in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_delete["duckdb_delete in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_eof["duckdb_eof    in duckdbrdd.prg"]
    static duckdb_append --> duckdb_eof["duckdb_eof    in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_flush["duckdb_flush  in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_flush["duckdb_flush  in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_flush["duckdb_flush  in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_goto["duckdb_goto   in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_gotoid["duckdb_gotoid in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_gotop["duckdb_gotop  in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_info["duckdb_info   in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_init["duckdb_init   in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_new["duckdb_new    in duckdbrdd.prg"]
    static duckdb_flush --> duckdb_new["duckdb_new    in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_open["duckdb_open   in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_open["duckdb_open   in duckdbrdd.prg"]
    static duckdb_create --> duckdb_open["duckdb_open   in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_rddinfo["duckdb_rddinfo in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_rddinfo["duckdb_rddinfo in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_recid["duckdb_recid  in duckdbrdd.prg"]
    duckdbrdd_getfunctable --> duckdb_skip["duckdb_skip   in duckdbrdd.prg"]
    static duckdb_delete --> duckdb_skip["duckdb_skip   in duckdbrdd.prg"]
    static duckdb_create --> errornew["errornew      <externa>"]
    getserverinfo --> fetch["fetch         in duckdbclass.prg"]
    getkeyfield --> fielddec["fielddec      in duckdbclass.prg"]
    getkeyfield --> fieldlen["fieldlen      in duckdbclass.prg"]
    getkeyfield --> fieldtype["fieldtype     in duckdbclass.prg"]
    getserverinfo --> getblankrow["getblankrow   in duckdbclass.prg"]
    getkeyfield --> getkeyfield["getkeyfield   in duckdbclass.prg"]
    getserverinfo --> getrow["getrow        in duckdbclass.prg"]
    getkeyfield --> gettables["gettables     <externa>"]
    refresh --> hb_ascan["hb_ascan      in harbour.lib"]
    static strdateclass --> hb_atokens["hb_atokens    in harbour.lib"]
    static universaldatetime --> hb_datetime["hb_datetime   in harbour.lib"]
    new --> hb_default["hb_default    in harbour.lib"]
    new --> hb_fnamesplit["hb_fnamesplit in harbour.lib"]
    append --> hb_isarray["hb_isarray    in harbour.lib"]
    fieldget --> hb_islogical["hb_islogical  in harbour.lib"]
    append --> hb_isnumeric["hb_isnumeric  in harbour.lib"]
    fieldget --> hb_isstring["hb_isstring   in harbour.lib"]
    static duckdb_create --> hb_langerrmsg["hb_langerrmsg in harbour.lib"]
    dbduckdbconnection --> hb_ntos["hb_ntos       in harbour.lib"]
    fieldget --> hb_stod["hb_stod       in harbour.lib"]
    fieldget --> hb_stot["hb_stot       in harbour.lib"]
    new --> hb_stot["hb_stot       in harbour.lib"]
    static datatosql --> hb_ttos["hb_ttos       in harbour.lib"]
    getkeyfield --> keyfield["keyfield      in duckdbclass.prg"]
    append --> numericvalue["numericvalue  in duckdbclass.prg"]
    lastrec --> numericvalue["numericvalue  in duckdbclass.prg"]
    lastrec --> numericvalue["numericvalue  in duckdbclass.prg"]
    getserverinfo --> oquery_destroy["oquery:destroy <externa>"]
    getserverinfo --> oquery_eof["oquery:eof    <externa>"]
    getserverinfo --> oquery_fetch["oquery:fetch  <externa>"]
    getserverinfo --> oquery_fetch["oquery:fetch  <externa>"]
    append --> orow_changed["orow:changed  <externa>"]
    append --> orow_fcount["orow:fcount   <externa>"]
    append --> orow_fieldget["orow:fieldget <externa>"]
    append --> orow_fieldname["orow:fieldname <externa>"]
    append --> orow_fieldpos["orow:fieldpos <externa>"]
    append --> orow_fieldput["orow:fieldput <externa>"]
    append --> orow_fieldput["orow:fieldput <externa>"]
    append --> orow_gettables["orow:gettables <externa>"]
    append --> quoteident["quoteident    in duckdbclass.prg"]
    getserverinfo --> refresh["refresh       in duckdbclass.prg"]
    getserverinfo --> skip["skip          <externa>"]
    static strdateclass --> stod["stod          in harbour.lib"]
    fieldget --> strdateclass["strdateclass  in duckdbclass.prg"]
    static duckdb_fetch_next --> strdaterdd["strdaterdd    in duckdbrdd.prg"]
    getserverinfo --> struct["struct        in duckdbclass.prg"]
    refresh --> structconvert["structconvert in duckdbclass.prg"]
    lastrec --> tduckdbquery["tduckdbquery  <externa>"]
    getblankrow --> tduckdbrow["tduckdbrow    <externa>"]
    dbduckdbconnection --> tratardialeto["tratardialeto in duckdbclass.prg"]
    fieldget --> tratardialeto["tratardialeto in duckdbclass.prg"]
    static duckdb_addfield --> update["update        in duckdbclass.prg"]
    static duckdb_close --> ur_super_close["ur_super_close in hbusrrdd.lib"]
    static duckdb_create --> ur_super_error["ur_super_error in hbusrrdd.lib"]
    static duckdb_info --> ur_super_info["ur_super_info in hbusrrdd.lib"]
    static duckdb_open --> ur_super_open["ur_super_open in hbusrrdd.lib"]
    static duckdb_rddinfo --> ur_super_open["ur_super_open in hbusrrdd.lib"]
    static duckdb_open --> ur_super_open["ur_super_open in hbusrrdd.lib"]
    duckdb_setpk --> ur_super_open["ur_super_open in hbusrrdd.lib"]
    duckdbrdd_getfunctable --> ur_super_open["ur_super_open in hbusrrdd.lib"]
    static duckdb_init --> usrrdd_rdddata["usrrdd_rdddata in hbusrrdd.lib"]
```
