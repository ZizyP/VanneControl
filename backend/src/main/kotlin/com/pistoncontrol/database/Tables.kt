package com.pistoncontrol.database

import org.jetbrains.exposed.sql.Table
import org.jetbrains.exposed.sql.javatime.timestamp

object Users : Table("users") {
    val id = uuid("id").autoGenerate()
    val email = text("email")
    val passwordHash = text("password_hash")
    val role = text("role")
    val createdAt = timestamp("created_at")
    val updatedAt = timestamp("updated_at")
    
    override val primaryKey = PrimaryKey(id)
}

object Devices : Table("devices") {
    val id = uuid("id")
    val name = text("name")
    val ownerId = uuid("owner_id")
    val mqttClientId = text("mqtt_client_id")
    val status = text("status")
    val createdAt = timestamp("created_at")
    val updatedAt = timestamp("updated_at")
    
    override val primaryKey = PrimaryKey(id)
}

object Pistons : Table("pistons") {
    val id = uuid("id")
    val deviceId = uuid("device_id")
    val pistonNumber = integer("piston_number")
    val state = text("state")
    val lastTriggered = timestamp("last_triggered").nullable()
    
    override val primaryKey = PrimaryKey(id)
}

object Telemetry : Table("telemetry") {
    val id = long("id")
    val deviceId = uuid("device_id")
    val pistonId = uuid("piston_id").nullable()
    val eventType = text("event_type")
    
    // ✅ SOLUTION: Use our custom jsonb() function
    // This properly casts to JSONB in PostgreSQL
    val payload = jsonb("payload").nullable()
    
    val createdAt = timestamp("created_at")
    
    override val primaryKey = PrimaryKey(id)
}

object AuthTokens : Table("auth_tokens") {
    val id = uuid("id")
    val userId = uuid("user_id")
    val refreshToken = text("refresh_token")
    val expiresAt = timestamp("expires_at")
    val createdAt = timestamp("created_at")
    
    override val primaryKey = PrimaryKey(id)
}
