# run_codegen.ps1
Set-Location -Path "app"
dart run build_runner build --delete-conflicting-outputs
Set-Location -Path ".."
