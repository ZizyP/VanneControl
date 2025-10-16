# Daily Use Scripts

These are your primary tools for working with the IoT system.

## Quick Reference

### Monitor & Debug
```bash
./monitor.sh                      # Interactive menu
python3 mqtt_message_decoder.py  # Decode MQTT messages
python3 binary_device_client.py  # Simulate IoT device
```

### Database
```bash
./query-db.sh devices    # List all devices
./query-db.sh pistons    # List all pistons
./query-db.sh telemetry  # Recent telemetry
./query-db.sh active     # Active pistons only
```

### Troubleshooting
```bash
./diagnose-and-fix.sh    # Auto-diagnose and fix issues
```

## Files

- `mqtt_message_decoder.py` - **Most important** - Decode binary MQTT messages
- `binary_device_client.py` - Simulate IoT device with binary protocol
- `query-db.sh` - Quick database queries
- `diagnose-and-fix.sh` - System diagnostics and auto-fix
- `monitor.sh` - Interactive monitoring menu
- `watch_db.sh` - Continuous database monitoring (optional)
