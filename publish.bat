@echo off
setlocal enabledelayedexpansion

:: Prompt the user for the commit message
set /p "user_input=Enter your commit message: "

:: Check if the input is empty
if "%user_input%"=="" (
    echo Error: Commit message cannot be blank. Exiting gracefully...
    pause
    goto :eof
)

:: Run the Git workflow chain
:: If any command fails, the chain breaks and executes the code after "||"
git add . && git commit -m "%user_input%" && git push || (
    echo.
    echo [ERROR] Something went wrong in the Git workflow.
    pause
    goto :eof
)

echo.
echo Workflow completed successfully!
pause
