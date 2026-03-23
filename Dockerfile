# Use Ubuntu's latest image
FROM ubuntu:latest

# Update and install jdk + wget
RUN apt update && apt upgrade -y
RUN apt install wget openjdk-25-jdk -y

# Download Minecraft to the /minecraft directory for running
RUN mkdir /minecraft
WORKDIR /minecraft

# This leverages the latest mc download script's output
COPY ./build/server.jar /minecraft/server.jar

# Mark the EULA as agreed to
RUN echo "eula=true" > eula.txt

# Run the Minecraft server on container start
# Note: This is running with 2gb of memory made available
ENTRYPOINT ["java", "-Xms2048M", "-Xmx2048M", "--enable-native-access=ALL-UNNAMED", "-jar", "server.jar", "nogui"]

# Useful for troubleshooting your dockerfile - very useful
# ENTRYPOINT ["tail", "-f", "/dev/null"]