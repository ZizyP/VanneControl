#!/bin/bash
echo "🔧 Fixing AuthRoutes.kt..."

cat > backend/src/main/kotlin/com/pistoncontrol/routes/AuthRoutes.kt << 'EOF'
package com.pistoncontrol.routes

import com.pistoncontrol.database.DatabaseFactory.dbQuery
import com.pistoncontrol.database.Users
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import org.jetbrains.exposed.sql.*
import org.mindrot.jbcrypt.BCrypt
import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import java.time.Instant
import java.util.*

@Serializable
data class LoginRequest(val email: String, val password: String)

@Serializable
data class RegisterRequest(val email: String, val password: String)

@Serializable
data class AuthResponse(val token: String, val user: UserInfo)

@Serializable
data class UserInfo(val id: String, val email: String, val role: String)

fun Route.authRoutes(jwtSecret: String, jwtIssuer: String, jwtAudience: String) {
    
    post("/auth/register") {
        try {
            val request = call.receive<RegisterRequest>()
            
            if (!request.email.contains("@")) {
                return@post call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid email"))
            }
            
            if (request.password.length < 8) {
                return@post call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Password must be at least 8 characters"))
            }
            
            val existing = dbQuery {
                Users.select { Users.email eq request.email }.singleOrNull()
            }
            
            if (existing != null) {
                return@post call.respond(HttpStatusCode.Conflict, mapOf("error" to "Email already registered"))
            }
            
            // Generate UUID and hash password BEFORE database operation
            val userId = UUID.randomUUID()
            val passwordHash = BCrypt.hashpw(request.password, BCrypt.gensalt())
            
            // Insert without trying to retrieve ID from result
            dbQuery {
                Users.insert {
                    it[id] = userId
                    it[email] = request.email
                    it[Users.passwordHash] = passwordHash
                    it[role] = "user"
                    it[createdAt] = Instant.now()
                    it[updatedAt] = Instant.now()
                }
            }
            
            val token = JWT.create()
                .withAudience(jwtAudience)
                .withIssuer(jwtIssuer)
                .withClaim("userId", userId.toString())
                .withClaim("email", request.email)
                .withClaim("role", "user")
                .withExpiresAt(Date(System.currentTimeMillis() + 86400000))
                .sign(Algorithm.HMAC256(jwtSecret))
            
            call.respond(HttpStatusCode.Created, AuthResponse(
                token = token,
                user = UserInfo(userId.toString(), request.email, "user")
            ))
        } catch (e: Exception) {
            e.printStackTrace()
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "Registration failed: ${e.message}"))
        }
    }
    
    post("/auth/login") {
        try {
            val request = call.receive<LoginRequest>()
            
            val user = dbQuery {
                Users.select { Users.email eq request.email }.singleOrNull()
            }
            
            if (user == null || !BCrypt.checkpw(request.password, user[Users.passwordHash])) {
                return@post call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Invalid credentials"))
            }
            
            val token = JWT.create()
                .withAudience(jwtAudience)
                .withIssuer(jwtIssuer)
                .withClaim("userId", user[Users.id].toString())
                .withClaim("email", user[Users.email])
                .withClaim("role", user[Users.role])
                .withExpiresAt(Date(System.currentTimeMillis() + 86400000))
                .sign(Algorithm.HMAC256(jwtSecret))
            
            call.respond(HttpStatusCode.OK, AuthResponse(
                token = token,
                user = UserInfo(user[Users.id].toString(), user[Users.email], user[Users.role])
            ))
        } catch (e: Exception) {
            e.printStackTrace()
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "Login failed: ${e.message}"))
        }
    }
}
EOF

echo "✅ AuthRoutes.kt updated!"
echo "Now rebuilding..."

docker compose build backend
docker compose up -d backend

echo "⏳ Waiting for backend to start..."
sleep 15

echo "🧪 Testing registration..."
curl -s -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"testuser@example.com","password":"password123"}'

echo -e "\n\n✅ Done!"
