# Security Checklist

## ✅ Pre-Production Security Steps

### 1. Passwords & Secrets
- [ ] Change default admin password
- [ ] Generate strong JWT secret
- [ ] Use strong database password
- [ ] Rotate MQTT certificates regularly

### 2. TLS/SSL
- [ ] Use valid SSL certificates (Let's Encrypt)
- [ ] Enable HTTPS only (disable HTTP)
- [ ] Verify certificate paths in Nginx
- [ ] Test TLS configuration

### 3. Firewall
- [ ] Close unnecessary ports
- [ ] Allow only: 80, 443, 8883
- [ ] Setup fail2ban
- [ ] Enable UFW/iptables

### 4. Database
- [ ] Restrict PostgreSQL to localhost only
- [ ] Regular backups (automated)
- [ ] Test restore procedure
- [ ] Enable connection limits

### 5. MQTT
- [ ] Require client certificates
- [ ] Disable anonymous access
- [ ] Use strong authentication
- [ ] Monitor connection logs

### 6. Docker
- [ ] Use non-root users in containers
- [ ] Limit container resources
- [ ] Keep images updated
- [ ] Scan for vulnerabilities

### 7. Monitoring
- [ ] Setup log aggregation
- [ ] Configure alerts
- [ ] Monitor disk space
- [ ] Track failed login attempts

### 8. Updates
- [ ] Keep system packages updated
- [ ] Update Docker images regularly
- [ ] Subscribe to security advisories
- [ ] Test updates in staging first
