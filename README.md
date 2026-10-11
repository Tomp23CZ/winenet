# WINENET

WINENET is a small helper tool for building .NET projects on Linux and running the resulting Windows executable through Wine.

It sets up a dedicated Wine prefix, installs matching Windows .NET runtimes based on the .NET runtimes available on your system, and provides a simple `winenet run` command for building and launching projects.

## Features

- Creates and manages a dedicated Wine prefix for .NET applications
- Automatically builds projects
- Runs the built Windows `.exe` through Wine
- Optional .NET project templates

## Dependencies

WINENET requires the following tools to be installed on your system:

- `bash`
- `git`
- `curl`
- `jq`
- `wine`
- `.NET SDK`

## Installation

Run the installer:
```
curl -fsSL https://raw.githubusercontent.com/Tomp23CZ/winenet/main/install.sh | bash
```
The installer will:

1. Clone the WINENET repository into a temporary directory
2. Install the `winenet` script to: `~/.local/bin/winenet`
3. Set up the WINENET Wine prefix
4. Detect installed .NET runtimes
5. Download and install matching Windows .NET runtimes into Wine
6. Optionally install WINENET .NET templates

Make sure `~/.local/bin` is in your `PATH`:
```
export PATH="$HOME/.local/bin:$PATH"
```
To make this permanent, add the line above to your shell profile, such as `~/.bashrc`, `~/.zshrc`, or equivalent.

## Usage

Show help:
```
winenet --help
```
Set up, repair, or update the Wine .NET environment:
```
winenet setup
```
Build and run a .NET project:
```
winenet run path/to/project
```
You can also run it from inside a project directory:
```
winenet run
```
Additional arguments after the project path are passed to `dotnet build`:
```
winenet run ./path/to/project -c Release
```
Even without the path argument:
```
winenet run -c Release
```
## Data Location

WINENET stores its files under:
```
~/.local/share/winenet
```
Or where your shell's `$XDG_DATA_HOME` variable points to 

Further variables can be recieved via `source winenet` command in a bash shell or equivalent.

These variables include:
- `WINENET_NAME`
- `WINENET_VERSION`
- `WINENET_PREFIX`
- `WINENET_DATA_DIR`
## Uninstall

Remove the installed script:
```
rm -f ~/.local/bin/winenet
```
Remove WINENET data and its Wine prefix:
```
rm -rf ~/.local/share/winenet
```
If you installed WINENET templates, remove them with `dotnet new uninstall` using the installed template package/path shown by:
```
dotnet new uninstall
```
