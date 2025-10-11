# Multi-stage build for optimized image size

# Stage 1: Build stage
FROM gradle:8.5-jdk17-alpine AS build

# Set working directory
WORKDIR /app

# Copy gradle configuration
COPY build.gradle.kts settings.gradle.kts gradle.properties ./

# Download dependencies (cached layer)
RUN gradle dependencies --no-daemon --quiet || true

# Copy source code
COPY src ./src

# Build the application
RUN gradle buildFatJar --no-daemon --info

# Verify JAR was built
RUN ls -lh /app/build/libs/

# Stage 2: Runtime stage
FROM eclipse-temurin:17-jre-alpine

# Install necessary runtime dependencies
RUN apk add --no-cache \
    curl \
    wget \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 1000 ktor && \
    adduser -D -u 1000 -G ktor ktor

# Set working directory
WORKDIR /app

# Copy the built JAR from build stage
COPY --from=build --chown=ktor:ktor /app/build/libs/*-all.jar app.jar

# Switch to non-root user
USER ktor

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# JVM options for container
ENV JAVA_OPTS="-XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=75.0 \
    -XX:+UseG1GC \
    -XX:+UseStringDeduplication \
    -Djava.security.egd=file:/dev/./urandom"

# Run the application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
