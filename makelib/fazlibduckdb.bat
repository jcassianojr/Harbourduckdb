call d:\devprg\hb64\hb64msys.bat
call c:\devprg\hb64\hb64msys_c.bat

rem Gere o arquivo .def:
rem gendef duckdb.dll 
rem entrou em loop usando def basica manual

rem Crie a .a:
dlltool -d duckdb.def -l libduckdb.a -k

rem link simbolico
rem ln -s libduckdb.dll.a libduckdb.a

rem opcao copia
