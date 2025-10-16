#!/bin/bash
set -e

echo "🔐 Generating SSL/TLS Certificates..."

mkdir -p certs

# Certificate Authority (CA)
echo "📜 Creating CA certificate..."
openssl genrsa -out certs/ca.key 4096
openssl req -new -x509 -days 3650 -key certs/ca.key -out certs/ca.crt \
    -subj "/C=US/ST=State/L=City/O=PistonControl/OU=CA/CN=PistonControl-CA"

# Mosquitto Server Certificate
echo "📜 Creating Mosquitto server certificate..."
openssl genrsa -out certs/server.key 2048
openssl req -new -key certs/server.key -out certs/server.csr \
    -subj "/C=US/ST=State/L=City/O=PistonControl/OU=MQTT/CN=mosquitto"
openssl x509 -req -in certs/server.csr -CA certs/ca.crt -CAkey certs/ca.key \
    -CAcreateserial -out certs/server.crt -days 3650

# Device Certificates (create multiple for different Raspberry Pis)
for i in {1..5}; do
    echo "📜 Creating device $i certificate..."
    openssl genrsa -out certs/device${i}.key 2048
    openssl req -new -key certs/device${i}.key -out certs/device${i}.csr \
        -subj "/C=US/ST=State/L=City/O=PistonControl/OU=Devices/CN=raspberry-pi-00${i}"
    openssl x509 -req -in certs/device${i}.csr -CA certs/ca.crt -CAkey certs/ca.key \
        -CAcreateserial -out certs/device${i}.crt -days 3650
done

# Nginx SSL Certificate (self-signed for development)
echo "📜 Creating Nginx SSL certificate..."
mkdir -p nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout nginx/ssl/key.pem -out nginx/ssl/cert.pem \
    -subj "/C=US/ST=State/L=City/O=PistonControl/CN=localhost"

# Set proper permissions
chmod 600 certs/*.key nginx/ssl/*.pem
chmod 644 certs/*.crt

echo "✅ Certificates generated successfully!"
echo "📦 Device certificates are in certs/device[1-5].{crt,key}"
