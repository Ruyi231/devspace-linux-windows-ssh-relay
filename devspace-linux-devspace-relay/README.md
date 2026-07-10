# Linux DevSpace Relay Target

This folder runs on the Linux server. It runs DevSpace only; it does **not**
install, configure, or start ngrok. The matching Windows relay folder owns the
fixed ngrok domain and forwards traffic here over SSH.

## Traffic path

```text
ChatGPT -> https://your-domain.ngrok-free.dev/mcp
        -> Windows ngrok -> Windows SSH local forward
        -> Linux 127.0.0.1:7676 -> DevSpace
```

Keep both sides running while ChatGPT uses the MCP app.

## First-time Linux setup

```bash
chmod +x *.sh
./install.sh
./set_project.sh /home/your-user/your-project
./set_relay_public_url.sh https://your-domain.ngrok-free.dev
./start_relay_target.sh
```

`your-domain.ngrok-free.dev` must be the fixed Dev Domain configured in the
Windows relay. It is used by DevSpace for OAuth redirects and host validation;
do not append `/mcp` here.

The final command prints the Owner password. Keep it private. Enter this value
when ChatGPT opens the DevSpace authorization page.

## Everyday use

Start Linux DevSpace first:

```bash
./start_relay_target.sh
```

Then start the Windows relay with `start.cmd`. To stop the Linux half:

```bash
./stop.sh
```

Useful checks:

```bash
./status.sh
./doctor.sh
tail -f logs/devspace.log
```

To change allowed project roots and restart:

```bash
./switch_project.sh /path/to/project [another/project]
```

## Included files

`install.sh` installs only Linux prerequisites, a local Node.js runtime, and
DevSpace. `set_project.sh`, `set_relay_public_url.sh`,
`start_relay_target.sh`, `stop.sh`, `status.sh`, and `doctor.sh` are the only
operational commands. There is intentionally no `setup_ngrok.sh` or `start.sh`
in this folder: running ngrok on Linux would bypass the relay and fails on the
restricted Linux network.
