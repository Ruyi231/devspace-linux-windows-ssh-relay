# Linux DevSpace Relay Target

This folder runs DevSpace on Linux only. The matching Windows folder owns SSH forwarding and ngrok.

```bash
chmod +x *.sh
./install.sh
./set_project.sh /path/to/project
./set_relay_public_url.sh https://your-domain.ngrok-free.dev
./start_relay_target.sh
```
