FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q -e -DskipTests dependency:go-offline
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/outbox-producer-service-0.0.1.jar app.jar

# Spring Kafka IAM config via env vars (ECS-friendly)
ENV SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL="SASL_SSL"
ENV SPRING_KAFKA_PROPERTIES_SASL_MECHANISM="AWS_MSK_IAM"
ENV SPRING_KAFKA_PROPERTIES_SASL_JAAS_CONFIG="software.amazon.msk.auth.iam.IAMLoginModule required;"
ENV SPRING_KAFKA_PROPERTIES_SASL_CLIENT_CALLBACK_HANDLER_CLASS="software.amazon.msk.auth.iam.IAMClientCallbackHandler"

# You will set this in ECS:
ENV SPRING_KAFKA_BOOTSTRAP_SERVERS=""
ENV APP_TOPIC="outbox.events.test"

ENTRYPOINT ["java","-jar","/app/app.jar"]
