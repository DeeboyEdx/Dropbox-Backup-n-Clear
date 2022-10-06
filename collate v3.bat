@echo off

REM This batch is v2 enacted on 2018-02-28
REM Where v1 would need an argument to function as desired
REM This batch can execute w/out arguments AND take multiple arguments
REM The downside is that it's inellegent
REM in that it doesn't take into account folders that have already been created
REM I felt it acceptible as I just wanted to get past this.
REM On the plus side, now I can schedule & automate the process!

REM v3 cleans up the process by adding the "if exists" at the md line.

setlocal
if exist temp.txt del temp.txt
if exist tmp.txt del tmp.txt
set /a counter=1
goto argumentCheck

:argumentCheck
rem sets batch's variable name here before SHIFT changes it at end of IF statement
set BATCHname=%~n0%~x0

rem I intend to use this FOR loop to automate the batch...
rem without needing to feed it a file list
rem which ultimately makes my original batch irrelevant ¬_¬
if "%~sn1" == "" (
	rem creates a file with the list of media files in directory
	for %%X in (*.jpg *.gif *.png *.mp4 *.jpeg) do (echo %%X >> tmp.txt)
	
	rem creates folder and moves files into corresponding folder
	for /f "tokens=1,2*" %%Y in (tmp.txt) do (
	if not exist %%Y md %%Y
	move "%%Y %%Z" %%Y
	)
)
echo ---------------------------------------
:again
rem this loop will go through passed files (likely drag & dropped) and...
rem sort them into folders based on their 10 char date at beginning of filename
set VRABL=%~n1%~x1
	rem grabs name of arg w/ extension
set RESULT=%VRABL:~0,10%
	rem parses out first 10 char into a variable cuz I can't just do it later
rem these variables need to be initiated outside of the IF or funky stuff happens
if NOT "%~sn1" == "" (
	rem if %1 is not blank there were arguments passed
	rem used short name ~sn because files with spaces crash the code
	echo Processing file %~n1%~x1
	rem ----------variable checks---------------
	rem echo        VRABL is %VRABL%
	rem echo Will use this part... %RESULT%
	rem -----------------/----------------------
	
	rem ----attempt to clean up code by checking count----
	rem echo Instances of this date:
	rem type temp.txt | find /c "%RESULT%" && echo.
	rem XXX echo Found + type temp.txt | find /c "%RESULT%" + echo instances || echo shiet!
	rem set /a counter=type temp.txt | find /c "%RESULT%"
	rem previous TWO lines never worked.
	
	echo %RESULT% >> temp.txt
	if not exist %RESULT% md %RESULT%  > NUL
	move %RESULT:~0,10%* %RESULT%
	
	shift
	rem - shift the arguments and examine %1 again
	set /a "counter = counter + 1"
	rem echo Count at end of IF statement is %counter%.
	rem Just printing count to verify it finally worked.
	rem not sure count is necessary anymore since I've decided to just go w dirty code
	echo. 
	goto again
)
if exist temp.txt del temp.txt
if exist tmp.txt del tmp.txt

goto end

:testing
			REM testing what each command displays
                              @echo off
                              echo.
                              echo fully qualified name %~f1
                              echo drive %~d1
                              echo path %~p1
                              echo filename %~n1
                              echo file extension %~x1
                              echo short filename %~sn1
                              echo short file extension %~sx1
                              echo drive and directory %~dp1
                              echo filename and extension %~nx1
                              echo.
goto :end

:parseTest
REM testing code to parse out what I want. ex: "2018-01-01"
	echo %1 %2
	echo.
	set VRABL=%~n1
	set RESULT=%VRABL:~0,10%
	echo %RESULT%
	
	echo.
goto :pauseClearEnd


:Create-n-Move2Folder
REM OLD CODE retired 2018-02-28
REM actual code for what I want to do
REM which is to make a folder with the date
REM (first 10 char) in the filename and move all files
REM with the same date into the folder
	set VRABL=%~n1
	echo %VRABL%
	set RESULT=%VRABL:~0,10%
	echo %RESULT%
	md %RESULT%
	move %RESULT:~0,10%* %RESULT%
goto :end

:pauseClearEnd
pause
:clearEnd
cls
:end
endlocal