-- Insert test device for binary protocol testing
INSERT INTO devices (id, name, owner_id, mqtt_client_id, status, created_at, updated_at)
VALUES (
    '550e8400-e29b-41d4-a716-446655440000',
    'Binary Protocol Test Device',
    (SELECT id FROM users LIMIT 1),
    'test-binary-device',
    'offline',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
) ON CONFLICT (id) DO NOTHING;

-- Create 8 pistons for the test device
DO $$
BEGIN
    FOR i IN 1..8 LOOP
        INSERT INTO pistons (id, device_id, piston_number, state, last_triggered)
        VALUES (
            gen_random_uuid(),
            '550e8400-e29b-41d4-a716-446655440000',
            i,
            'inactive',
            NULL
        ) ON CONFLICT (device_id, piston_number) DO NOTHING;
    END LOOP;
END $$;
