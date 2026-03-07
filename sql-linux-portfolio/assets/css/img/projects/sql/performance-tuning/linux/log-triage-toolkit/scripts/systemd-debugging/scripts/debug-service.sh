#!/bin/bash

echo "Checking service status"
systemctl status myapp.service

echo "Showing recent logs"
journalctl -u myapp.service --since "1 hour ago"
