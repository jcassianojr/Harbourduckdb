del *.dll
del *.a
copy c:\harbour\hb3rd\duckdb-x64\duckdb.dll
call d:\devprg\hb64\hb64msys.bat
call c:\devprg\hb64\hb64msys_c.bat

rem Gere o arquivo .def:
rem gendef duckdb.dll 
rem entrou em loop usando def basica manual

rem Crie a .a:
dlltool -d duckdb_v2_api1.def -l libduckdb.a -k

rem link simbolico
rem ln -s libduckdb.dll.a libduckdb.a

rem opcao copia
del *.dll