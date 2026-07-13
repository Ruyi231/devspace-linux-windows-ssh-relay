# Windows ngrok SSH Relay

This folder runs on the local Windows computer. It forwards a local port to
Linux over SSH and exposes that forwarded port with ngrok.

```cmd
.\install.cmd
.\setup_ngrok.cmd
.\set_relay.cmd <user_name>@<server_ip>
.\start.cmd
```

The Linux server must already be running `start_relay_target.sh` with the same
ngrok public URL. Keep the Windows relay running while ChatGPT uses the MCP
connector. This relay needs direct ngrok Internet access; it does not support
an HTTP or SOCKS proxy on the current legacy free account.
