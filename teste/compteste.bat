DEL *.EXE
call d:\devprg\hb64\hb64msys.bat
call c:\devprg\hb64\hb64msys_c.bat

hbmk2.exe DuckDBClass.prg duckdbrdd.prg duckdb.c testes.prg xhb.hbc -Ic:\harbour\hb3rd\duckdb-x64\ c:\harbour\hb3rd\duckdb-x64\duckdb.dll -oTestadorDuck