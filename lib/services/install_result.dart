/// A package-manager failure may quote arbitrary text, including "Success".
bool isSuccessfulInstallResult(String output) =>
    output.split('\n').any((line) => line.trim() == 'Success');
