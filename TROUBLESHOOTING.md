# Troubleshooting Guide

## Common Issues

### 1. Backend won't start
**Symptom**: Backend container exits immediately

**Solutions**:
```bash
# Check logs
docker-compose logs backend

# Verify database connection
docker-compose exec postgres psql -U piston_user -d piston_control

# Rebuild image
docker-compose build --no-cache backend
docker-compose up -d backend
