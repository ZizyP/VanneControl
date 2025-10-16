#!/bin/bash

tmux kill-session -t iot 2>/dev/null

tmux new-session -d -s iot \; \
  split-window -h \; \
  split-window -v \; \
  select-pane -t 0 \; \
  split-window -v \; \
  select-pane -t 0 \; send-keys 'source ../venv/bin/activate && python3 mqtt_message_decoder.py' C-m \; \
  select-pane -t 1 \; send-keys 'docker compose logs -f backend' C-m \; \
  select-pane -t 2 \; send-keys 'watch -n 2 "docker compose exec -T postgres psql -U piston_user -d piston_control -c \"SELECT LEFT(id::text,8) as id, name, status FROM devices;\""' C-m \; \
  select-pane -t 3 \; send-keys 'sleep 3 && source ../venv/bin/activate && python3 binary_device_client.py' C-m \; \
  attach
