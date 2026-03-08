# Systemd Service Debugging Commands

## Check service status
systemctl status myapp.service

## View recent logs
journalctl -u myapp.service --since "1 hour ago"

## Check restart count
systemctl show myapp.service -p ExecMainStatus -p NRestarts

## Reload and restart
systemctl daemon-reload
systemctl restart myapp.service
