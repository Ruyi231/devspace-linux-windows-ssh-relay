# DevSpace Linux Kit ngrok Edition

This kit exposes a Linux DevSpace MCP server through a fixed ngrok Dev Domain.
The Connector URL stays the same after a restart.

## Quick Start

```bash
chmod +x *.sh
./install.sh
./setup_ngrok.sh
./set_project.sh /home/your-user/your-project
./start.sh
```

`install.sh` downloads local copies of Node.js 24, DevSpace, and ngrok into
this directory. It does not require nvm or a global npm installation.

## ngrok Setup

Sign in to [ngrok Dashboard](https://dashboard.ngrok.com/), get an authtoken,
and find the Dev Domain assigned to your account. Free accounts receive one
fixed Dev Domain such as `example.ngrok-free.dev`; its name is assigned by
ngrok and cannot be customized.

Run the interactive setup and paste the authtoken when prompted:

```bash
./setup_ngrok.sh
```

The authtoken is handed to the official ngrok CLI only. It is not written to
this kit's `config.env`, README, or log files.

If you know the assigned Dev Domain, configure it explicitly:

```bash
./setup_ngrok.sh --public-url https://example.ngrok-free.dev
```

Do not append `/mcp` to `NGROK_PUBLIC_URL` in `config.env`.

## Connect ChatGPT

After `./start.sh`, copy the displayed MCP URL into the ChatGPT custom MCP
connector:

```text
https://example.ngrok-free.dev/mcp
```

Complete the OAuth flow and enter the Owner password displayed by `start.sh`.
The password is also stored in `config.env`; keep that file private.

## Commands

```bash
./install.sh                         # Install local dependencies
./setup_ngrok.sh                     # Save authtoken and fixed Dev Domain
./set_project.sh /path/to/project    # Set one or more allowed project roots
./switch_project.sh /path/to/project # Change root and restart
./start.sh                           # Start DevSpace and ngrok
./stop.sh                            # Stop only this kit's PID-file processes
./status.sh                          # Inspect URL consistency and local health
./doctor.sh                          # Check prerequisites and configuration
```

Multiple project roots are supported:

```bash
./set_project.sh /srv/project-a /srv/project-b
```

## Fixed URL Behavior

The kit starts ngrok with the configured Dev Domain:

```text
ngrok http 127.0.0.1:7676 --url https://example.ngrok-free.dev
```

If ngrok reports any URL other than `NGROK_PUBLIC_URL`, `start.sh` stops the
new processes and exits with an error. It never silently replaces the saved
Connector URL.

## Common Problems

`ngrok URL mismatch`: verify that `NGROK_PUBLIC_URL` is the Dev Domain
assigned to the same ngrok account as the configured authtoken.

`ERR_NGROK_9009`: this kit clears `HTTP_PROXY`, `HTTPS_PROXY`, and related
variables for ngrok because free ngrok agents cannot use an HTTP/S proxy.

`401` from `curl http://127.0.0.1:7676/mcp`: this is normal when DevSpace is
running without an OAuth access token.

`No bash shell found`: install `bash` with your distribution package manager,
then run `./doctor.sh` and restart the kit.

## Security

The MCP server can access the project roots in `DEVSPACE_ALLOWED_ROOTS`.
Choose only directories you intend to expose to the Connector. Do not share
`config.env`, the Owner password, or your ngrok authtoken.
