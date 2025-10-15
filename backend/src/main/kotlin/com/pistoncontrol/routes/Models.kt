package com.pistoncontrol.routes

import kotlinx.serialization.Serializable

@Serializable
data class LoginRequest(
    val email: String,
    val password: String
)

@Serializable
data class RegisterRequest(
    val email: String,
    val password: String
)

@Serializable
data class LoginResponse(
    val token: String,
    val userId: String
)

@Serializable
data class ErrorResponse(
    val error: String
)

@Serializable
data class PistonCommand(
    val action: String
)

@Serializable
data class CommandResponse(
    val success: Boolean,
    val message: String,
    val deviceId: String,
    val pistonNumber: Int,
    val action: String
)

@Serializable
data class CreateDeviceRequest(
    val name: String,
    val mqttClientId: String
)

@Serializable
data class DeviceResponse(
    val id: String,
    val name: String,
    val mqttClientId: String,
    val status: String
)

@Serializable
data class PistonResponse(
    val piston_number: Int,
    val state: String,
    val last_triggered: String?
)
