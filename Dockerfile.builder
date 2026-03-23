# Use Ubuntu's latest image - start with a builder
FROM ubuntu:latest AS builder

# Update and install jdk + wget
RUN apt update && apt upgrade -y
RUN apt install curl wget -y

WORKDIR /minecraft
COPY latest_mc.sh /minecraft/latest_mc.sh
RUN chmod +x latest_mc.sh
RUN chmod 755 latest_mc.sh
RUN ./latest_mc.sh

FROM ubuntu:latest

# Update and install jdk + wget
RUN apt update && apt upgrade -y
RUN apt install openjdk-25-jdk -y

# Download Minecraft to the /minecraft directory for running
WORKDIR /minecraft

# Copy the minecraft server from the builder to the server
COPY --from=builder /minecraft/server.jar /minecraft/server.jar

# Mark the EULA as agreed to
RUN rm eula.txt
RUN echo "eula=true" > eula.txt

# Run the Minecraft server on container start
# Note: This is running with 2gb of memory made available
ENTRYPOINT ["java", "-Xms2048M", "-Xmx2048M", "--enable-native-access=ALL-UNNAMED", "-jar", "server.jar", "nogui"]

# Useful for troubleshooting your dockerfile
# ENTRYPOINT ["tail", "-f", "/dev/null"]