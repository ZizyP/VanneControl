package com.pistoncontrol.database

import org.jetbrains.exposed.sql.Column
import org.jetbrains.exposed.sql.ColumnType
import org.jetbrains.exposed.sql.Table
import org.jetbrains.exposed.sql.statements.api.PreparedStatementApi
import org.postgresql.util.PGobject

/**
 * Custom JSONB Column Type for PostgreSQL
 * 
 * This tells Exposed how to properly handle JSONB columns:
 * 1. Converts Kotlin String → PostgreSQL JSONB
 * 2. Uses PGobject which PostgreSQL JDBC driver understands
 * 3. Automatically handles the casting
 * 
 * LEARNING: This is necessary because Exposed doesn't have built-in
 * JSONB support that works out-of-the-box with PostgreSQL.
 */
class JsonbColumnType : ColumnType() {
    
    /**
     * SQL type name - tells PostgreSQL this is JSONB
     */
    override fun sqlType(): String = "JSONB"
    
    /**
     * Convert from database → Kotlin
     * When reading from database, we get a PGobject and extract the JSON string
     * 
     * IMPORTANT: Return type must be Any (not String?) to match parent class
     */
    override fun valueFromDB(value: Any): Any {
        return when (value) {
            is PGobject -> value.value ?: ""
            is String -> value
            else -> ""
        }
    }
    
    /**
     * Convert from Kotlin → database
     * When writing to database, we create a PGobject with type "jsonb"
     * This tells PostgreSQL to treat it as JSONB, not text
     */
    override fun notNullValueToDB(value: Any): Any {
        val jsonString = when (value) {
            is String -> value
            else -> value.toString()
        }
        
        return PGobject().apply {
            type = "jsonb"
            this.value = jsonString
        }
    }
    
    /**
     * Handle nullable values
     */
    override fun setParameter(stmt: PreparedStatementApi, index: Int, value: Any?) {
        if (value == null) {
            stmt.setNull(index, this)
        } else {
            stmt[index] = notNullValueToDB(value)
        }
    }
}

/**
 * Extension function to easily create JSONB columns
 * 
 * Usage in Table:
 *   val payload = jsonb("payload").nullable()
 */
fun Table.jsonb(name: String): Column<String> {
    return registerColumn(name, JsonbColumnType())
}
