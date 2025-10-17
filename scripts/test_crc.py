#!/usr/bin/env python3
"""
Test CRC16 calculation independently
This will help us verify if Python and Kotlin match
"""

import struct

def calculate_crc16(data: bytes) -> int:
    """CRC16 - should match Kotlin"""
    crc = 0xFFFF
    
    for byte_val in data:
        crc ^= byte_val
        for _ in range(8):
            if crc & 0x0001:
                crc = (crc >> 1) ^ 0x8005
            else:
                crc >>= 1
    
    return crc & 0xFFFF

# Test with known data from your error message
# Raw hex from your output: 03550e8400e29b41d4a716446655440000015c4b
print("Testing CRC16 calculation")
print("="*60)

# Parse the hex string (remove spaces if any)
hex_str = "03550e8400e29b41d4a716446655440000015c4b"
data = bytes.fromhex(hex_str)

print(f"Input data: {hex_str}")
print(f"Length: {len(data)} bytes")
print()

# Calculate CRC
crc = calculate_crc16(data)
print(f"Calculated CRC: 0x{crc:04x}")

# The error showed: Received 0xF72F, Expected 0xEA70
print(f"Your error said:")
print(f"  Received:  0xF72F")
print(f"  Expected:  0xEA70")
print()

# Let's also test what happens if we pack it little-endian
crc_bytes_le = struct.pack('<H', crc)
print(f"CRC as little-endian bytes: {crc_bytes_le.hex()}")

crc_bytes_be = struct.pack('>H', crc)
print(f"CRC as big-endian bytes: {crc_bytes_be.hex()}")
print()

# Full message with CRC
full_message = data + crc_bytes_le
print(f"Full message with CRC (LE): {full_message.hex()}")
print()

# Try to understand the mismatch
print("Analysis:")
print(f"  If we sent 0x{crc:04x} = {crc_bytes_le.hex()} (LE)")
print(f"  And they expect something different...")
print()

# Test another possibility: maybe UUID byte order is wrong
print("Testing UUID byte order possibilities:")
uuid_str = "550e8400-e29b-41d4-a716-446655440000"
import uuid
u = uuid.UUID(uuid_str)
print(f"UUID: {uuid_str}")
print(f"  .bytes (standard):     {u.bytes.hex()}")
print(f"  .bytes_le (LE):        {u.bytes_le.hex()}")
print(f"  .int as bytes:         {u.int.to_bytes(16, 'big').hex()}")
print()

# Recalculate with different UUID byte orders
test_cases = [
    ("Standard UUID.bytes", u.bytes),
    ("UUID.bytes_le", u.bytes_le),
]

for name, uuid_bytes in test_cases:
    test_data = b'\x03' + uuid_bytes + b'\x00\x01\x5c\x4b'
    test_crc = calculate_crc16(test_data)
    print(f"{name:25} -> CRC: 0x{test_crc:04x}")

print("\n" + "="*60)
print("Compare these CRCs with what the backend expects!")
