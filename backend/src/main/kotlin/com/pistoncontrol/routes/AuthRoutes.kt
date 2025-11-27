package com.pistoncontrol.routes

import com.pistoncontrol.database.DatabaseFactory.dbQuery
import com.pistoncontrol.database.Users
import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import org.jetbrains.exposed.sql.*
import org.mindrot.jbcrypt.BCrypt
import java.util.UUID
import java.util.Date
import java.time.Instant

/**
 * Validate password complexity
 * Returns null if valid, error message if invalid
 */
private fun validatePassword(password: String): String? {
    if (password.length < 8) {
        return "Password must be at least 8 characters"
    }
    if (!password.any { it.isDigit() }) {
        return "Password must contain at least one digit"
    }
    if (!password.any { it.isUpperCase() }) {
        return "Password must contain at least one uppercase letter"
    }
    if (!password.any { it.isLowerCase() }) {
        return "Password must contain at least one lowercase letter"
    }
    // Optional: Add special character requirement
    // if (!password.any { !it.isLetterOrDigit() }) {
    //     return "Password must contain at least one special character"
    // }
    return null
}

fun Route.authRoutes(jwtSecret: String, jwtIssuer: String, jwtAudience: String) {
    route("/auth") {
        post("/register") {
            try {
                val request = call.receive<RegisterRequest>()

                if (!request.email.contains("@")) {
                    return@post call.respond(HttpStatusCode.BadRequest, ErrorResponse("Invalid email"))
                }

                // Validate password complexity
                val passwordError = validatePassword(request.password)
                if (passwordError != null) {
                    return@post call.respond(HttpStatusCode.BadRequest, ErrorResponse(passwordError))
                }
                
                val hashedPassword = BCrypt.hashpw(request.password, BCrypt.gensalt())
                
                val userId = dbQuery {
                    val existingUser = Users.select { Users.email eq request.email }.singleOrNull()
                    if (existingUser != null) {
                        return@dbQuery null
                    }
                    
                    Users.insert {
                        it[Users.email] = request.email
                        it[Users.passwordHash] = hashedPassword
                        it[Users.role] = "user"
                        it[Users.createdAt] = Instant.now()
                        it[Users.updatedAt] = Instant.now()
                    } get Users.id
                }
                
                if (userId == null) {
                    return@post call.respond(HttpStatusCode.Conflict, ErrorResponse("Email already registered"))
                }
                
                val token = JWT.create()
                    .withAudience(jwtAudience)
                    .withIssuer(jwtIssuer)
                    .withClaim("userId", userId.toString())
                    .withExpiresAt(Date(System.currentTimeMillis() + 86400000))
                    .sign(Algorithm.HMAC256(jwtSecret))
                
                call.respond(HttpStatusCode.Created, LoginResponse(token, userId.toString()))
            } catch (e: Exception) {
                call.respond(HttpStatusCode.InternalServerError, ErrorResponse("Registration failed: ${e.message}"))
            }
        }
        
        post("/login") {
            try {
                val request = call.receive<LoginRequest>()
                
                val user = dbQuery {
                    Users.select { Users.email eq request.email }.singleOrNull()
                }
                
                if (user == null || !BCrypt.checkpw(request.password, user[Users.passwordHash])) {
                    return@post call.respond(HttpStatusCode.Unauthorized, ErrorResponse("Invalid credentials"))
                }
                
                val userId = user[Users.id]
                val token = JWT.create()
                    .withAudience(jwtAudience)
                    .withIssuer(jwtIssuer)
                    .withClaim("userId", userId.toString())
                    .withExpiresAt(Date(System.currentTimeMillis() + 86400000))
                    .sign(Algorithm.HMAC256(jwtSecret))
                
                call.respond(HttpStatusCode.OK, LoginResponse(token, userId.toString()))
            } catch (e: Exception) {
                call.respond(HttpStatusCode.InternalServerError, ErrorResponse("Login failed: ${e.message}"))
            }
        }
    }
}
